/**
 * @description Tests for several Git connections (build 45): the connections cards and their saves (RlyConnectionController,
 * RlyConnectionStore), an org's connection and moving it (RlyOrgConnection), one route per connection
 * (RlyConnectionRoutes, RlyRouteLanes, RlyPromoteController, RlyReleaseStart), promotions staying in their repository
 * (RlyPromoteConnection), the release list's repository (RlyReleaseRepo), the release page (RlyReleaseGitView) and
 * keeping the other repositories' prod branches in step (RlyProdSync, RlyProdSyncRun, RlyProdSyncStore).
 * The second connection (GitLab) is created in the test setup. Every test runs as an existing active System
 * Administrator through System.runAs; DML happens before Test.startTest and callouts after it.
 */
@IsTest
private class RlyConnectionsTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            insert new RLY_Git_Connection__c(Name = 'GitLab group/project', Provider__c = 'GitLab', Repository__c = 'group/project',
                Named_Credential__c = 'RLY_GitLab', Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main',
                Source_Path__c = 'force-app/main/default', Code_Scan__c = true, Status__c = 'Connected', Active__c = true);
            Test.setCreatedDate([SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1].Id, Datetime.now().addDays(-1));
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

    private static String connectionJson(Map<String, Object> extra) {
        Map<String, Object> m = new Map<String, Object>{ 'Provider__c' => 'Bitbucket', 'Repository__c' => 'team/repo',
            'Named_Credential__c' => 'RLY_Bitbucket', 'Pipeline__c' => 'release-relay', 'Pipeline_Branch__c' => 'main',
            'Source_Path__c' => 'force-app/main/default', 'Code_Scan__c' => true };
        m.putAll(extra);
        return JSON.serialize(m);
    }

    private static String refusal(String connectionJson) {
        try {
            RlyConnectionController.saveConnection(connectionJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return 'saved';
    }

    private static Map<String, Object> orgInput(String name, String role) {
        return new Map<String, Object>{
            'Name' => name, 'Role__c' => role, 'My_Domain__c' => 'https://' + name.toLowerCase() + '.my.salesforce.com',
            'Login_Type__c' => 'Production', 'Username__c' => 'relay@' + name.toLowerCase() + '.demo',
            'Consumer_Key__c' => RlyTestData.CONSUMER_KEY, 'Certificate__c' => 'release_relay',
            'Git_Environment__c' => name.toLowerCase(), 'Branch__c' => name.toLowerCase(), 'Environment__c' => 'Developer_Pro'
        };
    }

    private static String orgRefusal(Map<String, Object> input) {
        try {
            RlyOrgController.saveOrg(JSON.serialize(input));
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return 'saved';
    }

    private static RLY_Release__c releaseIn(Id connectionId, String status, Id targetId) {
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Release_Type__c = 'Release', Source_Org__c = orgId('DEV1'), Target_Org__c = targetId,
            Org_Label__c = 'DEV1', Target_Branch__c = 'sit', Source_Environment__c = 'dev1', Target_Environment__c = 'sit',
            Scan_Status__c = 'Passed', Validation_Status__c = 'Passed', Approval_Status__c = 'Approved', Deploy_Status__c = 'Deployed',
            Merge_Commit__c = RlyReleaseTestData.sha('a'), Last_Synced__c = System.now().addMinutes(-5), Component_Count__c = 1,
            Git_Connection__c = connectionId);
        insert rel;
        insert new List<RLY_Release_Item__c>{
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService'),
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'LightningComponentBundle', Component_Name__c = 'accountCard')
        };
        return [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
    }

    @IsTest
    static void cardsShowEveryConnectionAndOneConnectionPerProvider() {
        System.runAs(RlyTestData.admin()) {
            RlyConnectionController.Connections c = RlyConnectionController.getConnections();
            System.assertEquals(2, c.cards.size(), 'GitHub and GitLab');
            System.assert(c.cards[0].isMain, 'The oldest active connection is the main one');
            System.assertEquals('GitHub', c.cards[0].providerLabel, 'GitHub first');
            System.assertEquals('Pull request', c.cards[0].changeRequestLabel, 'GitHub says pull request');
            System.assertEquals('https://github.com/acme/release', c.cards[0].webUrl, 'The repository\'s web address');
            System.assertEquals(new List<String>{ 'DEV1', 'SIT' }, c.cards[0].orgNames, 'Orgs without a connection are on the main one');
            System.assert(c.cards[1].orgNames.isEmpty(), 'Nothing on GitLab yet');
            System.assertEquals(new List<String>{ 'Bitbucket', 'AzureDevOps' }, c.notSetUp, 'The providers not set up');
            System.assertEquals(2, RlyConnectionCards.choices().size(), 'Two choices for an org');

            String dup = refusal(connectionJson(new Map<String, Object>{ 'Provider__c' => 'GitLab', 'Repository__c' => 'other/project',
                'Named_Credential__c' => 'RLY_GitLab', 'Pipeline__c' => '.gitlab-ci.yml' }));
            System.assert(dup.contains('already a GitLab connection'), 'One connection per provider: ' + dup);
            System.assert(refusal(connectionJson(new Map<String, Object>{ 'Repository__c' => '' })).contains('Repository is required'),
                'Checked like the Git connection');

            Id added = RlyConnectionController.saveConnection(connectionJson(new Map<String, Object>()));
            RLY_Git_Connection__c saved = [SELECT Name, Active__c, Status__c, Source_Path__c FROM RLY_Git_Connection__c WHERE Id = :added];
            System.assertEquals('Bitbucket team/repo', saved.Name, 'Named after the provider and repository');
            System.assert(saved.Active__c, 'A new connection is active');
            System.assertEquals('Not checked', saved.Status__c, 'Checked next');

            String mainOff = refusal(JSON.serialize(new Map<String, Object>{ 'Id' => gitHubId(), 'Provider__c' => 'GitHub',
                'Repository__c' => 'acme/release', 'Named_Credential__c' => 'RLY_GitHub', 'Pipeline__c' => 'release-relay.yml',
                'Pipeline_Branch__c' => 'main', 'Source_Path__c' => 'force-app/main/default', 'Active__c' => false }));
            System.assert(mainOff.contains('main connection stays active'), mainOff);
            update new RLY_Org__c(Id = orgId('SIT'), Git_Connection__c = added);
            String withOrgs = refusal(connectionJson(new Map<String, Object>{ 'Id' => added, 'Active__c' => false }));
            System.assert(withOrgs.contains('Move its orgs'), withOrgs);
            update new RLY_Org__c(Id = orgId('SIT'), Git_Connection__c = null);
            RlyConnectionController.saveConnection(connectionJson(new Map<String, Object>{ 'Id' => added, 'Active__c' => false }));
            System.assert(![SELECT Active__c FROM RLY_Git_Connection__c WHERE Id = :added].Active__c, 'Switched off');
            Boolean gone = false;
            try {
                RlyConnectionController.checkConnection(RlyTestData.fakeId('a00', 1));
            } catch (Exception e) {
                gone = true;
            }
            System.assert(gone, 'A connection that isn\'t there');
        }
    }

    @IsTest
    static void checkingCreatingBranchesAndPipelineFilesUseTheConnection() {
        System.runAs(RlyTestData.admin()) {
            Id github = gitHubId();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/branches/dev1').reply(404, '{"message":"Branch not found"}')
                .match('GET', '/branches/').reply(200, '{"name":"x"}')
                .match('GET', '/contents/').reply(404, '{"message":"Not Found"}')
                .match('GET', '/git/ref/heads/main').reply(200, '{"object":{"sha":"abc123"}}')
                .match('POST', '/git/refs').reply(201, '{"ref":"refs/heads/dev1"}')
                .match('GET', '/repos/acme/release').reply(200, '{"default_branch":"main"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyConnectionCards.BranchCheck found = RlyConnectionController.checkBranch(github, 'sit');
            RlyConnectionCards.BranchCheck missing = RlyConnectionController.checkBranch(github, 'dev1');
            RlyConnectionCards.BranchCheck bad = RlyConnectionController.checkBranch(github, 'a..b');
            RlyBranchCreate.Result created = RlyConnectionController.createBranchesFor(github, 0);
            RlyPipelineFiles.Status files = RlyConnectionController.pipelineFilesFor(github);
            RlyConnectionCards.Card card = RlyConnectionController.checkConnection(github);
            Test.stopTest();
            System.assert(found.found, 'sit is there');
            System.assertEquals('sit exists in GitHub', found.message, 'Said with the provider');
            System.assert(!missing.found && missing.message.contains('Create missing branches'), missing.message);
            System.assert(!bad.found && bad.message.contains('branch name'), 'A bad name isn\'t checked');
            System.assertEquals(new List<String>{ 'dev1' }, created.created, 'The missing route branch is created');
            System.assertEquals('GitHub', files.provider, 'The connection\'s own files');
            System.assertEquals(null, files.repoVersion, 'Not in the repository');
            System.assertEquals('Failed', card.status, 'The pipeline files are missing: ' + card.record.Status_Message__c);
        }
    }

    @IsTest
    static void anOrgPicksItsConnectionAndMovesOnlyWithoutOpenReleases() {
        System.runAs(RlyTestData.admin()) {
            Id gitlab = gitLabId();
            String noPick = orgRefusal(orgInput('DEV2', 'Developer'));
            System.assert(noPick.contains('Pick the Git connection'), 'Several connections: the org picks one: ' + noPick);
            Map<String, Object> dev2 = orgInput('DEV2', 'Developer');
            dev2.put('Git_Connection__c', gitlab);
            Id dev2Id = RlyOrgController.saveOrg(JSON.serialize(dev2));
            System.assertEquals(gitlab, [SELECT Git_Connection__c FROM RLY_Org__c WHERE Id = :dev2Id].Git_Connection__c, 'On GitLab');

            Map<String, Object> hub = orgInput('PROD2', 'Hub');
            hub.put('Git_Connection__c', gitlab);
            System.assert(orgRefusal(hub) != 'saved' || [SELECT Git_Connection__c FROM RLY_Org__c WHERE Name = 'PROD2'].Git_Connection__c == null,
                'The hub never has a connection');

            RLY_Release__c open = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('b'));
            update new RLY_Release__c(Id = open.Id, Status__c = 'Ready for approval');
            RLY_Org__c dev1 = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Certificate__c, Git_Environment__c, Branch__c,
                                      Environment__c FROM RLY_Org__c WHERE Name = 'DEV1'];
            Map<String, Object> move = new Map<String, Object>{ 'Id' => dev1.Id, 'Name' => dev1.Name, 'Role__c' => dev1.Role__c,
                'My_Domain__c' => dev1.My_Domain__c, 'Login_Type__c' => dev1.Login_Type__c, 'Username__c' => dev1.Username__c,
                'Certificate__c' => dev1.Certificate__c, 'Git_Environment__c' => dev1.Git_Environment__c, 'Branch__c' => dev1.Branch__c,
                'Environment__c' => 'Developer_Pro', 'Git_Connection__c' => gitlab };
            String blocked = orgRefusal(move);
            System.assert(blocked.contains('open releases') && blocked.contains(open.Name), 'Open releases keep it: ' + blocked);

            update new RLY_Release__c(Id = open.Id, Status__c = 'Closed');
            System.assertEquals('saved', orgRefusal(move), 'No open release: it moves');
            System.assertEquals(gitlab, [SELECT Git_Connection__c FROM RLY_Org__c WHERE Id = :dev1.Id].Git_Connection__c, 'On GitLab now');
            System.assertEquals(gitHubId(), [SELECT Git_Connection__c FROM RLY_Release__c WHERE Id = :open.Id].Git_Connection__c,
                'Its history stays with the old repository');
            System.assertEquals(gitlab, RlyReleaseStore.gitForOrg(dev1.Id).Id, 'Its next release starts in GitLab');
            System.assertEquals(gitHubId(), RlyReleaseStore.gitForOrg(orgId('PROD')).Id, 'The hub is on the main connection');
            System.assertEquals(gitHubId(), RlyReleaseStore.gitFor(new RLY_Release__c(Id = open.Id)).Id, 'Read again for its connection');

            update new RLY_Git_Connection__c(Id = gitlab, Active__c = false);
            Map<String, Object> back = move.clone();
            back.put('Git_Connection__c', gitHubId());
            System.assertEquals('saved', orgRefusal(back), 'Back to GitHub');
            Map<String, Object> again = move.clone();
            System.assert(orgRefusal(again).contains('isn\'t active'), 'Only active connections take orgs');
        }
    }

    @IsTest
    static void eachConnectionHasItsOwnRouteEndingAtTheHub() {
        System.runAs(RlyTestData.admin()) {
            Id gitlab = gitLabId();
            RLY_Org__c dev2 = RlyTestData.org('DEV2', 'Developer', 'dev2');
            dev2.Git_Connection__c = gitlab;
            RLY_Org__c qa = RlyTestData.stage('QA', 'qa', 1);
            qa.Git_Connection__c = gitlab;
            insert new List<RLY_Org__c>{ dev2, qa };

            System.assertEquals('SIT', RlyConnectionRoutes.firstStageFor(gitHubId()).Name, 'GitHub releases go to SIT');
            System.assertEquals('QA', RlyConnectionRoutes.firstStageFor(gitlab).Name, 'GitLab releases go to QA');
            System.assertEquals('QA', RlyRaiseRoute.target(RlyReleaseStore.org(dev2.Id)).Name, 'Raised from DEV2: into QA');
            System.assertEquals(new List<String>{ 'qa' }, RlyPipelineOptions.stageBranchesFor(gitlab), 'GitLab\'s stage branches');
            System.assertEquals(new List<String>{ 'dev2' }, RlyConnectionRoutes.developerBranchesFor(gitlab), 'GitLab\'s developer branches');
            System.assertEquals(new List<String>{ 'dev1' }, RlyConnectionRoutes.developerBranchesFor(null), 'The main connection\'s');
            List<RLY_Org__c> gitlabRoute = RlyRouteRules.ordered(RlyConnectionRoutes.routeOrgsFor(gitlab));
            System.assertEquals('PROD', gitlabRoute[gitlabRoute.size() - 1].Name, 'The hub ends every route');

            RlyRouteController.Setup s = RlyRouteController.getSetup();
            System.assertEquals(2, s.lanes.size(), 'One lane per connection');
            System.assert(s.lanes[0].isMain, 'The main connection first');
            System.assertEquals('GitLab group/project', s.lanes[1].label, 'Named after the provider and repository');
            System.assertEquals('DEV2', s.lanes[1].developers[0].Name, 'Its developer org');
            System.assertEquals('QA', s.lanes[1].stages[0].Name, 'Its stage');
            System.assertEquals('PROD', s.lanes[1].stages[1].Name, 'Then the hub');

            update new RLY_Org__c(Id = qa.Id, Git_Connection__c = gitHubId(), Stage_Order__c = 2);
            List<RlyRouteLanes.Lane> lanes = RlyRouteController.getSetup().lanes;
            System.assert(String.join(lanes[1].warnings, ' ').contains('no stage org'), 'GitLab has nowhere to release to: ' + lanes[1].warnings);
            System.assert(String.join(RlyRouteLanes.allWarnings(lanes), ' ').startsWith('GitLab: '), 'Each warning says its connection');

            RlyPromoteController.PromoteBoard board = RlyPromoteController.getPromote();
            System.assertEquals(2, board.connectionCount, 'Grouped by connection');
            System.assertEquals('SIT', board.stages[0].stageName, 'SIT first');
            System.assertEquals('QA', board.stages[0].nextName, 'Then QA on GitHub\'s route');
            System.assertEquals('GitHub acme/release', board.stages[0].connectionLabel, 'Each stage says its connection');

            RlyReleaseStart.Start start = RlyReleaseStart.build();
            System.assertEquals(2, start.routes.size(), 'One route per connection on New Release');
            System.assertEquals(gitHubId(), start.mainConnectionId, 'The main connection');
            System.assertEquals('SIT', start.routes[0].targetName, 'GitHub: into SIT');
            System.assertEquals(null, start.routes[1].targetName, 'GitLab has no stage now');
        }
    }

    @IsTest
    static void aPromotionOnlyCombinesReleasesFromItsStagesConnection() {
        System.runAs(RlyTestData.admin()) {
            Id gitlab = gitLabId();
            Id sitId = orgId('SIT');
            RLY_Release__c legacy = releaseIn(null, 'Deployed', sitId);
            update new RLY_Org__c(Id = sitId, Git_Connection__c = gitlab);
            String refused;
            try {
                RlyPromotion.Request req = new RlyPromotion.Request();
                req.stageId = sitId;
                req.releaseIds = new List<Id>{ legacy.Id };
                req.title = 'To production';
                RlyPromotion.create(req);
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('one Git connection'), 'It stays in GitHub: ' + refused);

            update new RLY_Release__c(Id = legacy.Id, Git_Connection__c = gitlab);
            RlyPromotion.Request ok = new RlyPromotion.Request();
            ok.stageId = sitId;
            ok.releaseIds = new List<Id>{ legacy.Id };
            ok.title = 'To production';
            Id promotionId = RlyPromotion.create(ok);
            RLY_Release__c p = [SELECT Git_Connection__c, Target_Org__r.Name FROM RLY_Release__c WHERE Id = :promotionId];
            System.assertEquals(gitlab, p.Git_Connection__c, 'The promotion stays in its releases\' repository');
            System.assertEquals('PROD', p.Target_Org__r.Name, 'To the hub, GitLab\'s next stop');
        }
    }

    @IsTest
    static void theListShowsEachReleasesRepositoryAndFiltersByIt() {
        System.runAs(RlyTestData.admin()) {
            Id gitlab = gitLabId();
            RLY_Release__c inGitLab = releaseIn(gitlab, 'Deployed', orgId('SIT'));
            RLY_Release__c inGitHub = releaseIn(null, 'Deployed', orgId('SIT'));
            List<RlyReleasesController.Row> everyRow = RlyReleasesController.listReleasesFor('{"state":"all"}');
            Map<Id, RlyReleasesController.Row> byId = new Map<Id, RlyReleasesController.Row>();
            for (RlyReleasesController.Row r : everyRow) {
                byId.put(r.id, r);
            }
            System.assertEquals('GitLab', byId.get(inGitLab.Id).provider, 'GitLab badge');
            System.assertEquals('group/project', byId.get(inGitLab.Id).repository, 'Its repository');
            System.assertEquals('GitHub', byId.get(inGitHub.Id).provider, 'Without a connection: the main one');
            List<RlyReleasesController.Row> onlyGitLab = RlyReleasesController.listReleasesFor('{"state":"all","connectionId":"' + gitlab + '"}');
            System.assertEquals(1, onlyGitLab.size(), 'The Repository filter');
            System.assertEquals(inGitLab.Id, onlyGitLab[0].id, 'Only GitLab\'s');

            RlyReleasesController.Detail d = RlyReleasesController.getRelease(inGitHub.Id);
            System.assertEquals('GitHub', d.gitProvider, 'The release\'s own provider');
            System.assertEquals('Pull request', d.changeRequestLabel, 'GitHub says pull request');
            System.assertEquals('acme/release', d.repository, 'Its repository');
            System.assertEquals('GitLab', RlyReleasesController.getRelease(inGitLab.Id).gitProvider, 'The GitLab release says GitLab');
        }
    }

    @IsTest
    static void aProductionDeployRaisesAReleaseIntoTheOtherRepositorysProd() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseIn(gitLabId(), 'Deployed', orgId('PROD'));
            RlyBackPromoteQueue.afterDeploy(RlyReleaseStore.release(rel.Id));
            RLY_Release__c queued = [SELECT Prod_Sync__c, Prod_Sync_State__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals(RlyProdSync.QUEUED, queued.Prod_Sync_State__c, 'Queued by the save after the deploy');
            List<RlyProdSync.Entry> entries = RlyProdSync.entriesOf(queued.Prod_Sync__c);
            System.assertEquals(1, entries.size(), 'Only the other connection');
            System.assertEquals('GitHub', entries[0].provider, 'GitHub\'s prod branch');
            System.assertEquals('prod', entries[0].branch, 'The hub\'s branch');
            System.assertEquals(RlyProdSync.RUNNING, RlyProdSync.views(queued.Prod_Sync__c)[0].state, 'Waiting to start');

            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            Test.startTest();
            Boolean stepped = RlyProdSync.step(rel.Id);
            Test.stopTest();
            System.assert(stepped, 'One step');
            RLY_Release__c started = [SELECT Prod_Sync__c, Prod_Sync_State__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals(RlyProdSync.STARTED, started.Prod_Sync_State__c, 'Raised: ' + started.Prod_Sync__c);
            Id syncId = RlyProdSync.entriesOf(started.Prod_Sync__c)[0].releaseId;
            RLY_Release__c sync = [SELECT Release_Type__c, Source_Org__r.Name, Target_Org__r.Name, Target_Branch__c, Target_Environment__c,
                                          Source_Environment__c, Git_Connection__c, Retrieve_Id__c, Status__c, Validation_Status__c,
                                          (SELECT Id FROM Release_Items__r)
                                   FROM RLY_Release__c WHERE Id = :syncId];
            System.assertEquals(RlyProdSync.TYPE_PROD_SYNC, sync.Release_Type__c, 'An automatic release');
            System.assertEquals('PROD', sync.Source_Org__r.Name, 'From the hub org');
            System.assertEquals('PROD', sync.Target_Org__r.Name, 'Into the hub\'s branch');
            System.assertEquals('prod', sync.Target_Branch__c, 'prod');
            System.assertEquals(null, sync.Target_Environment__c, 'No target environment: no validation, no deploy');
            System.assertEquals('prod', sync.Source_Environment__c, 'Retrieved from the hub org');
            System.assertEquals(gitHubId(), sync.Git_Connection__c, 'In the other repository');
            System.assertEquals(RlyFlowScenario.RETRIEVE_ID, sync.Retrieve_Id__c, 'Retrieved like a normal raise');
            System.assertEquals('Retrieving', sync.Status__c, 'Retrieving');
            System.assertEquals('Not configured', sync.Validation_Status__c, 'No validation');
            System.assertEquals(2, sync.Release_Items__r.size(), 'The deployed release\'s components');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals(1, d.prodSync.size(), 'Shown on the release');
            System.assertEquals(RlyProdSync.RUNNING, d.prodSync[0].state, 'Running');
            System.assert(d.running, 'The page keeps checking until it ends');
        }
    }

    @IsTest
    static void theAutomaticReleaseMergesWithoutADeploy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c sync = releaseIn(gitHubId(), 'Ready for approval', orgId('PROD'));
            update new RLY_Release__c(Id = sync.Id, Release_Type__c = RlyProdSync.TYPE_PROD_SYNC, Target_Environment__c = null,
                Source_Branch__c = 'feature/' + sync.Name.toLowerCase(), Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending');
            RLY_Release__c merged = releaseIn(gitHubId(), 'Deploying', orgId('PROD'));
            update new RLY_Release__c(Id = merged.Id, Release_Type__c = RlyProdSync.TYPE_PROD_SYNC, Target_Environment__c = null,
                Pending_Run__c = 'merge', Check_Token__c = 'tok1');
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/dispatches').reply(204, '')
                .match('GET', '/' + merged.Name + '/merge.json').reply(200, '{"status":"Merged","sha":"' + RlyReleaseTestData.sha('c')
                    + '","attempt":"tok1"}')
                .match('GET', '/runs?').reply(200, '{"workflow_runs":[]}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Release__c rel = RlyReleaseStore.release(sync.Id);
            RlyGit git = RlyGit.forConnection(RlyReleaseStore.gitFor(rel));
            RlyProdSync.afterChecks(rel, git);
            RLY_Release__c deploying = RlyReleaseStore.release(merged.Id);
            RlyDeployReader.readDeploy(deploying, git);
            Test.stopTest();
            System.assertEquals('Deploying', rel.Status__c, 'Its merge started without an approver');
            System.assertEquals('merge', rel.Pending_Run__c, 'Mode merge');
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'));
            Map<String, Object> inputs = (Map<String, Object>) body.get('inputs');
            System.assertEquals('merge', inputs.get('mode'), 'A merge');
            System.assertEquals('', inputs.get('target_environment'), 'No target environment: the deploy job doesn\'t run');
            System.assert(!RlyReleaseTestData.dispatchedOptions(mock).containsKey('syncBranches'), 'Nothing is merged back down');
            System.assertEquals('Deployed', deploying.Status__c, 'Merged is all it does: ' + deploying.Error_Message__c);
            System.assert(!RlyBackPromoteQueue.isHubDeploy(deploying), 'It never starts another prod sync or back promote');
        }
    }

    @IsTest
    static void eachRepositorysLineSaysHowItWentAndCanBeTriedAgain() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseIn(gitLabId(), 'Deployed', orgId('PROD'));
            RLY_Release__c ok = releaseIn(gitHubId(), 'Deployed', orgId('PROD'));
            RLY_Release__c bad = releaseIn(gitHubId(), 'Checks failed', orgId('PROD'));
            update new RLY_Release__c(Id = bad.Id, Error_Message__c = 'The scan found blocking problems.');
            List<RlyProdSync.Entry> entries = new List<RlyProdSync.Entry>();
            for (Integer i = 0; i < 3; i++) {
                RlyProdSync.Entry e = new RlyProdSync.Entry();
                e.connectionId = i == 0 ? gitHubId() : RlyTestData.fakeId('a01', i);
                e.provider = 'GitHub';
                e.repository = 'acme/release';
                e.branch = 'prod';
                e.status = i == 2 ? RlyProdSync.FAILED : RlyProdSync.STARTED;
                e.message = i == 2 ? 'Couldn\'t raise it: no sign-in.' : null;
                e.releaseId = i == 0 ? ok.Id : (i == 1 ? bad.Id : null);
                entries.add(e);
            }
            System.assertEquals(RlyProdSync.FAILED, RlyProdSyncEntries.stateOf(entries), 'One failed');
            List<RlyProdSync.View> views = RlyProdSync.views(JSON.serialize(entries));
            System.assertEquals(RlyProdSync.SYNCED, views[0].state, 'prod kept in step');
            System.assertEquals('prod kept in step in GitHub.', views[0].message, 'Said plainly');
            System.assertEquals(RlyProdSync.FAILED, views[1].state, 'Its release failed');
            System.assert(views[1].message.contains('blocking problems'), views[1].message);
            System.assertEquals('Couldn\'t raise it: no sign-in.', views[2].message, 'Why it couldn\'t be raised');
            System.assert(RlyProdSync.entriesOf('not json').isEmpty(), 'Unreadable: nothing');

            update new RLY_Release__c(Id = rel.Id, Prod_Sync__c = JSON.serialize(entries), Prod_Sync_State__c = RlyProdSync.FAILED);
            System.assert(!RlyProdSync.step(rel.Id), 'Nothing queued or running: no step');
            RlyProdSync.retry(rel.Id, RlyTestData.fakeId('a01', 1));
            RLY_Release__c again = [SELECT Prod_Sync__c, Prod_Sync_State__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals(RlyProdSync.QUEUED, again.Prod_Sync_State__c, 'Queued again');
            System.assertEquals(null, RlyProdSync.entriesOf(again.Prod_Sync__c)[1].releaseId, 'A new release next time');

            RlyProdSync.Entry gone = new RlyProdSync.Entry();
            gone.connectionId = RlyTestData.fakeId('a01', 9);
            RlyProdSyncRun.Raised r = RlyProdSyncRun.raise(gone, rel);
            System.assert(r.problem.contains('isn\'t there'), 'A connection that is gone: ' + r.problem);
            RlyProdSyncRun.save(r, gone);
            System.assertEquals(RlyProdSync.FAILED, gone.status, 'Failed, never blocking');
        }
    }

    @IsTest
    static void oneConnectionQueuesNoProdSync() {
        System.runAs(RlyTestData.admin()) {
            Boolean deleted = true;
            try {
                delete [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitLab'];
            } catch (DmlException e) {
                deleted = false; // skipped, not failed: the rest still runs
            }
            RLY_Release__c rel = releaseIn(null, 'Deployed', orgId('PROD'));
            RlyProdSync.queue(RlyReleaseStore.release(rel.Id));
            System.assert(!deleted || [SELECT Prod_Sync_State__c FROM RLY_Release__c WHERE Id = :rel.Id].Prod_Sync_State__c == null,
                'One connection: nothing to keep in step');
            RlyProdSync.queue(null);
            System.assert(!RlyProdSync.isProdSync(rel), 'An ordinary release');
        }
    }
}
