/**
 * @description Tests for build 46: one active Git connection (RlyGitConnections, RlyReleaseStore.git and gitFor, the
 * Releases list's older-repository badge) and the Migration tab (RlyMigrationController, RlyMigrationOrgController and
 * the RlyMigration* classes). The current connection (GitHub) and the new one (GitLab) are created in the test setup;
 * every Git call is answered by RlyHttpMock. Every test runs as an existing active System Administrator through
 * System.runAs; DML happens before the callouts of each test.
 */
@IsTest
private class RlyMigrationTest {

    private static final String RUN_ID = 'MIG-1762531200001';
    private static final String TOKEN = 'tok-46';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setCreatedDate([SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1].Id, Datetime.now().addDays(-2));
            insert new RLY_Git_Connection__c(Name = 'GitLab group/project', Provider__c = 'GitLab', Repository__c = 'group/project',
                Named_Credential__c = 'RLY_GitLab', Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main',
                Source_Path__c = 'force-app/main/default', Status__c = 'Connected');
            RlyReleaseStore.forgetGit();
        }
    }

    private static Id gitHubId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1].Id;
    }

    private static Id gitLabId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitLab' LIMIT 1].Id;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    // A migration GitHub → GitLab with a method picked (not inserted).
    private static RLY_Migration__c migration(String method) {
        return new RLY_Migration__c(Migration_Id__c = 'MIG-1762531200000', Current_Connection__c = gitHubId(),
            New_Connection__c = gitLabId(), Status__c = RlyMigrationStore.OPEN, Step__c = 3, Method__c = method);
    }

    private static Map<String, Object> ref(String name, String sha, String targetSha) {
        return new Map<String, Object>{ 'ref' => 'refs/heads/' + name, 'kind' => 'branch', 'name' => name, 'source' => sha,
            'target' => targetSha, 'match' => sha == targetSha };
    }

    // migrate.json as the pipeline writes it.
    private static String result(String token, Boolean ready) {
        return JSON.serialize(new Map<String, Object>{ 'request' => RUN_ID, 'step' => 'migrate', 'status' => 'Succeeded',
            'attempt' => token, 'ready' => ready, 'phase' => 'done', 'method' => 'verify', 'dryRun' => true,
            'branches' => new Map<String, Object>{ 'found' => 4, 'pushed' => 0, 'failed' => 0 },
            'tags' => new Map<String, Object>{ 'found' => 1, 'pushed' => 0, 'failed' => 0 }, 'commits' => 42, 'mainCommits' => 40,
            'defaultBranch' => 'main', 'sizeKb' => 2048, 'targetEmpty' => false, 'targetRefCount' => 5,
            'access' => new Map<String, Object>{ 'read' => true, 'push' => null }, 'problems' => new List<Object>(),
            'namedBranches' => new List<Object>{ new Map<String, Object>{ 'name' => 'sit', 'inSource' => true, 'inTarget' => true } },
            'refs' => new List<Object>{ ref('main', 'a1', 'a1'), ref('sit', 'b2', 'b2'), ref('prod', 'c3', 'c3'),
                ref('release-relay-results', 'd4', 'e5'),
                new Map<String, Object>{ 'ref' => 'refs/tags/v1', 'kind' => 'tag', 'name' => 'v1', 'source' => 'f6', 'target' => 'f6', 'match' => true } } });
    }

    private static RlyMigrationState allInSync() {
        RlyMigrationState state = new RlyMigrationState();
        for (RLY_Org__c o : RlySyncStore.orgs()) {
            RlyMigrationState.OrgCheck c = new RlyMigrationState.OrgCheck();
            c.status = RlyMigrationSync.IN_SYNC;
            c.syncId = 'SYN-1762531200000';
            c.mode = 'drift';
            state.orgChecks.put(String.valueOf(o.Id), c);
        }
        state.mark('new.envs', RlyMigrationState.DONE);
        state.log('Test', 'Ready to switch');
        return state;
    }

    private static String refusal(Exception e) {
        return e.getMessage();
    }

    @IsTest
    static void startConfigureAndChoose() {
        System.runAs(RlyTestData.admin()) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/repos/acme/release/branches?per_page=50').reply(200, '[{"name":"main"},{"name":"dev1"},{"name":"sit"},{"name":"prod"}]'));
            Test.startTest();
            RlyMigrationView.View started = RlyMigrationController.startMigration();
            String again;
            try {
                RlyMigrationController.startMigration();
            } catch (AuraHandledException e) {
                again = refusal(e);
            }
            String sameProvider;
            try {
                RlyMigrationController.saveTarget(started.id, '{"Provider__c":"GitHub","Repository__c":"a/b","Named_Credential__c":"X","Pipeline_Branch__c":"main"}');
            } catch (AuraHandledException e) {
                sameProvider = refusal(e);
            }
            RlyMigrationController.saveTarget(started.id, '{"Provider__c":"GitLab","Repository__c":"group/project","Named_Credential__c":"RLY_GitLab",'
                + '"Pipeline__c":".gitlab-ci.yml","Pipeline_Branch__c":"main"}');
            RlyMigrationView.View chosen = RlyMigrationController.chooseMethod(started.id, RlyMigrationMethods.LIFT);
            String bogus;
            try {
                RlyMigrationController.chooseMethod(started.id, 'bogus');
            } catch (AuraHandledException e) {
                bogus = refusal(e);
            }
            RlyMigrationOrgController.markItem(started.id, 'new.envs', RlyMigrationState.DONE);
            RlyMigrationOrgController.acceptDifferences(started.id, 'SIT has a hotfix in flight');
            RlyMigrationView.View moved = RlyMigrationOrgController.goToStep(started.id, 5);
            String badStep;
            try {
                RlyMigrationOrgController.goToStep(started.id, 9);
            } catch (AuraHandledException e) {
                badStep = refusal(e);
            }
            RlyMigrationView.View current = RlyMigrationController.getMigration();
            Test.stopTest();
            System.assertEquals(4, started.holds.branches.size(), 'The current branches are read at the start');
            System.assert(again != null && again.contains('already going'), 'One migration at a time: ' + again);
            System.assert(sameProvider != null && sameProvider.contains('other than the current'), 'Another provider: ' + sameProvider);
            System.assertEquals(gitLabId(), chosen.target.id, 'The existing GitLab connection is reused');
            System.assertEquals(RlyMigrationMethods.LIFT, chosen.choose.method, 'Lift and shift picked');
            System.assertEquals(3, chosen.choose.methods.size(), 'Three methods');
            System.assert(bogus != null, 'An unknown method is refused');
            System.assertEquals(5, moved.step, 'Moved to step 5');
            System.assert(badStep != null && badStep.contains('1 to 8'), 'Steps 1 to 8: ' + badStep);
            System.assertEquals(started.id, current.id, 'The migration going is shown');
            System.assertEquals('SIT has a hotfix in flight', current.gate.acceptReason, 'The accepted reason is kept');
            System.assert(current.setup.newItems.size() > 5, 'The new setup checklist is there');
            System.assert(current.log.events.size() >= 4, 'Each step is logged');
        }
    }

    @IsTest
    static void newRepositoryIsChecked() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(null);
            insert m;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/projects/group/project/repository/branches?per_page=50').reply(200, '[]'));
            Test.startTest();
            RlyMigrationView.View v = RlyMigrationController.checkTargetRepository(m.Id);
            Test.stopTest();
            System.assertEquals('Reachable · empty', v.holds.targetCheck, 'An empty new repository');
            System.assertEquals(0, v.holds.targetBranches, 'No branches');
        }
    }

    @IsTest
    static void dryRunStartsInTheCurrentPipeline() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            insert m;
            RlyHttpMock mock = new RlyHttpMock().match('POST', '/actions/workflows/release-relay.yml/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            String noRun;
            try {
                RlyMigrationController.startRun(m.Id, RlyMigrationRun.RUN);
            } catch (AuraHandledException e) {
                noRun = refusal(e);
            }
            RlyMigrationView.View v = RlyMigrationController.startRun(m.Id, RlyMigrationRun.DRY);
            Test.stopTest();
            String body = mock.bodyFor('/dispatches');
            System.assert(noRun != null && noRun.contains('verified by the dry run'), 'The importer has no run: ' + noRun);
            System.assertEquals(RlyMigrationRun.STARTED, v.run.status, 'Started');
            System.assert(v.run.runId.startsWith('MIG-'), 'Its own request id');
            System.assert(body.contains('migrate') && body.contains('verify') && body.contains('gitlab.com/group/project.git'),
                'Mode migrate, verify, the target address: ' + body);
            System.assert(!body.contains('RELAY_MIGRATE_TOKEN'), 'No token in the inputs');
        }
    }

    @IsTest
    static void verifyResultIsReadWithWhatMoved() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            m.Run_Id__c = RUN_ID;
            m.Run_Token__c = TOKEN;
            m.Run_Kind__c = RlyMigrationRun.DRY;
            m.Run_Status__c = RlyMigrationRun.STARTED;
            insert m;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/contents/results/' + RUN_ID + '/migrate.json').reply(200, result(TOKEN, true))
                .match('GET', '/pulls?state=open').reply(200, '[{"number":41,"title":"Region field","html_url":"https://github.com/acme/release/pull/41",'
                    + '"head":{"ref":"feature/rel-00041"},"base":{"ref":"sit"}}]'));
            Test.startTest();
            RlyMigrationView.View v = RlyMigrationController.refreshRun(m.Id);
            Test.stopTest();
            System.assertEquals(RlyMigrationRun.READY, v.run.status, 'The verify is ready');
            System.assert(v.run.dry.ready, 'Ready');
            System.assert(v.run.dry.counts.contains('4 branch(es)') && v.run.dry.counts.contains('2 MB'), v.run.dry.counts);
            System.assertEquals(5, v.moved.rows.size(), 'Every ref listed');
            System.assertEquals('pipeline branch', v.moved.rows[0].role, 'The Release Relay branches first');
            System.assert(v.moved.allMatch, 'The results branch moving on is no difference: ' + v.moved.matched);
            System.assert(v.moved.rows[0].url.startsWith('https://gitlab.com/group/project/-/tree/'), 'Linked in GitLab');
            System.assertEquals(1, v.moved.requests.size(), 'The open pull request that stays');
            System.assertEquals('#41', v.moved.requests[0].label, 'Its number');
        }
    }

    @IsTest
    static void runThatEndedWithoutResultFails() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.LIFT);
            m.Run_Id__c = RUN_ID;
            m.Run_Token__c = TOKEN;
            m.Run_Kind__c = RlyMigrationRun.RUN;
            m.Run_Status__c = RlyMigrationRun.GOING;
            insert m;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/runs?event=workflow_dispatch').reply(200, '{"workflow_runs":[{"id":5,"display_title":"Release Relay '
                    + RUN_ID + ' (migrate)","html_url":"https://github.com/acme/release/actions/runs/5","status":"completed","conclusion":"failure"}]}')
                .match('GET', '/pulls?state=open').reply(200, '[]'));
            Test.startTest();
            RlyMigrationView.View v = RlyMigrationController.refreshRun(m.Id);
            Test.stopTest();
            System.assertEquals(RlyMigrationRun.FAILED, v.run.status, 'Failed');
            System.assertEquals('https://github.com/acme/release/actions/runs/5', v.run.runUrl, 'The run\'s link');
            System.assert(v.run.result.message.contains('without writing'), v.run.result.message);
        }
    }

    @IsTest
    static void pipelineFilesNeedTheCopyFirst() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c lift = migration(RlyMigrationMethods.LIFT);
            insert lift;
            RLY_Migration__c imported = migration(RlyMigrationMethods.IMPORTER);
            imported.Migration_Id__c = 'MIG-1762531200009';
            imported.Result__c = result(TOKEN, true);
            insert imported;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock());
            Test.startTest();
            String notCopied;
            try {
                RlyMigrationController.updatePipelineFiles(lift.Id);
            } catch (AuraHandledException e) {
                notCopied = refusal(e);
            }
            RlyMigrationView.View v = RlyMigrationController.updatePipelineFiles(imported.Id);
            Test.stopTest();
            System.assert(notCopied != null && notCopied.contains('Copy or verify'), 'The copy comes first: ' + notCopied);
            System.assert(v.log.events[0].what.startsWith('Pipeline files'), 'Logged: ' + v.log.events[0].what);
        }
    }

    @IsTest
    static void newConnectionCheckIsSaved() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            insert m;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock());
            Test.startTest();
            RlyMigrationView.View v = RlyMigrationController.checkNewConnection(m.Id);
            Test.stopTest();
            System.assertEquals('Failed', v.target.status, 'The unreachable repository fails its check');
            System.assert(v.log.events[0].what.startsWith('Checked the new connection'), v.log.events[0].what);
        }
    }

    @IsTest
    static void orgChecksRunAgainstTheNewConnection() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            insert m;
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/projects/group/project/pipeline').reply(201, '{"id":7,"web_url":"https://gitlab.com/group/project/-/pipelines/7"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySyncRuns.Started sit = RlyMigrationOrgController.startOrgCheck(m.Id, orgId('SIT'));
            RlySyncRuns.Started dev = RlyMigrationOrgController.startOrgCheck(m.Id, orgId('DEV1'));
            String part;
            try {
                RlyMigrationOrgController.stageOrgPart(m.Id, '{"compareId":"bad"}');
            } catch (AuraHandledException e) {
                part = refusal(e);
            }
            Test.stopTest();
            RlyMigrationState state = RlyMigrationState.of([SELECT State__c FROM RLY_Migration__c WHERE Id = :m.Id].State__c);
            System.assertEquals('drift', sit.mode, 'A stage is read by the drift job');
            System.assertEquals('parts', dev.mode, 'A developer org is sent in parts');
            System.assert(mock.callLog().contains('group/project/pipeline'), 'Started in the GitLab pipeline: ' + mock.callLog());
            System.assertEquals(2, state.orgChecks.size(), 'Both checks kept');
            System.assert(part != null, 'A bad part is refused');
        }
    }

    @IsTest
    static void orgCheckIsReadFromTheNewRepository() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            RlyMigrationState state = new RlyMigrationState();
            RlyMigrationState.OrgCheck c = new RlyMigrationState.OrgCheck();
            c.syncId = 'SYN-1762531200000';
            c.mode = 'drift';
            c.status = RlyMigrationSync.RUNNING;
            state.orgChecks.put(String.valueOf(orgId('SIT')), c);
            m.State__c = state.toJson();
            insert m;
            insert new RLY_Sync_Check__c(Sync_Id__c = 'SYN-1762531200000', Kind__c = RlySyncStore.KIND_ORG, Org__c = orgId('SIT'),
                Branch__c = 'sit', Token__c = TOKEN, Status__c = RlySyncStore.RUNNING, Run_Title__c = 'Release Relay SYN-1762531200000 (drift)');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/pipelines?ref=').reply(200, '[]'));
            Test.startTest();
            RlyMigrationView.View v = RlyMigrationOrgController.readOrgCheck(m.Id, orgId('SIT'));
            String unchecked;
            try {
                RlyMigrationOrgController.readOrgCheck(m.Id, orgId('DEV1'));
            } catch (AuraHandledException e) {
                unchecked = refusal(e);
            }
            Test.stopTest();
            String sitStatus;
            for (RlyMigrationView.OrgRow o : v.orgs) {
                sitStatus = o.name == 'SIT' ? o.status : sitStatus;
            }
            System.assertEquals(RlyMigrationSync.RUNNING, sitStatus, 'Still running');
            System.assert(unchecked != null && unchecked.contains('Check that org first'), unchecked);
        }
    }

    @IsTest
    static void switchNowThenFinishWithTheReport() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c notReady = migration(RlyMigrationMethods.IMPORTER);
            notReady.Migration_Id__c = 'MIG-1762531200008';
            notReady.Status__c = RlyMigrationStore.CANCELLED;
            insert notReady;
            RLY_Migration__c m = migration(RlyMigrationMethods.IMPORTER);
            m.Dry_Run__c = result(TOKEN, true);
            m.Result__c = result(TOKEN, true);
            m.Run_Kind__c = RlyMigrationRun.DRY;
            m.Run_Status__c = RlyMigrationRun.READY;
            m.State__c = allInSync().toJson();
            insert m;
            Test.startTest();
            String closed;
            try {
                RlyMigrationOrgController.switchNow(notReady.Id);
            } catch (AuraHandledException e) {
                closed = refusal(e);
            }
            String early;
            try {
                RlyMigrationOrgController.finishMigration(m.Id);
            } catch (AuraHandledException e) {
                early = refusal(e);
            }
            RlyMigrationView.View switched = RlyMigrationOrgController.switchNow(m.Id);
            RlyMigrationView.View finished = RlyMigrationOrgController.finishMigration(m.Id);
            Test.stopTest();
            System.assert(closed != null && closed.contains('cancelled'), 'A cancelled migration can\'t switch: ' + closed);
            System.assert(early != null && early.contains('Switch first'), 'The report comes after the switch: ' + early);
            System.assertEquals(RlyMigrationStore.SWITCHED, switched.status, 'Switched');
            System.assertEquals(8, switched.step, 'On to the old setup');
            System.assertEquals(gitLabId(), RlyGitConnections.activeId(), 'GitLab is the active connection');
            System.assertEquals(RlyMigrationStore.FINISHED, finished.status, 'Finished');
            System.assert(finished.log.reportUrl != null && finished.log.reportUrl.contains('/sfc/servlet.shepherd/document/download/'),
                'The report downloads: ' + finished.log.reportUrl);
            System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :m.Id], 'The report is in the migration\'s Files');
        }
    }

    @IsTest
    static void switchWaitsForEveryCondition() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = migration(RlyMigrationMethods.LIFT);
            insert m;
            Test.startTest();
            String notYet;
            try {
                RlyMigrationOrgController.switchNow(m.Id);
            } catch (AuraHandledException e) {
                notYet = refusal(e);
            }
            RlyMigrationView.View cancelled = RlyMigrationOrgController.cancelMigration(m.Id);
            Test.stopTest();
            System.assert(notYet != null && notYet.contains('Dry run passed'), 'The missing conditions are named: ' + notYet);
            System.assertEquals(null, cancelled.id, 'Back to the start');
            System.assertEquals(RlyMigrationStore.CANCELLED, [SELECT Status__c FROM RLY_Migration__c WHERE Id = :m.Id].Status__c, 'Cancelled');
        }
    }
}
