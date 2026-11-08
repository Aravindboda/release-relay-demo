/**
 * @description Tests for build 46's parts: one active Git connection (RlyGitConnections, RlyReleaseStore.git and gitFor,
 * the Releases list's older-repository badge, the stamp at raise), the methods for each pair of providers, the
 * checklists and secrets per provider, the repository reads per provider (RlyMigrationRepo), and reading checks and
 * results (RlyMigrationSync.checkOf, RlyMigrationSummary, RlyMigrationState). GitHub and GitLab connections are created
 * in the test setup; every Git call is answered by RlyHttpMock. Every test runs as an existing active System
 * Administrator through System.runAs.
 */
@IsTest
private class RlyMigrationPartsTest {

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

    // A release from DEV1 into SIT at a status (not inserted).
    private static RLY_Release__c release(String status) {
        return new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes', Request_Type__c = 'Changes',
            Source_Org__c = orgId('DEV1'), Target_Org__c = orgId('SIT'), Org_Label__c = 'DEV1', Target_Branch__c = 'sit',
            Source_Environment__c = 'dev1', Target_Environment__c = 'sit', Scan_Status__c = 'Pending', Validation_Status__c = 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Component_Count__c = 1);
    }

    private static String refusal(Exception e) {
        return e.getMessage();
    }

    @IsTest
    static void oneActiveConnectionSwitchesOnlyWithoutOpenReleases() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c old = release('PR open');
            insert old;
            old = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :old.Id];
            System.assertEquals(gitHubId(), RlyGitConnections.activeId(), 'The oldest counts while none is active');
            System.assertEquals(1, RlyGitConnections.openReleases(gitHubId()).size(), 'A blank release counts as the oldest connection\'s');
            System.assertEquals(0, RlyGitConnections.openReleases(gitLabId()).size(), 'Nothing open on GitLab');
            String noReason;
            String stillOpen;
            try {
                RlyGitConnections.switchTo(gitLabId(), '');
            } catch (RlyReleaseException e) {
                noReason = refusal(e);
            }
            try {
                RlyGitConnections.switchTo(gitLabId(), 'Move to GitLab');
            } catch (RlyReleaseException e) {
                stillOpen = refusal(e);
            }
            update new RLY_Release__c(Id = old.Id, Status__c = 'Closed', Git_Connection__c = null);
            Test.startTest();
            RlyGitConnections.switchTo(gitLabId(), 'Move to GitLab');
            RlyGitConnections.forget();
            RLY_Release__c fresh = release('Submitted');
            RlyReleaseStore.insertRelease(fresh, new List<RLY_Release_Item__c>());
            Map<Id, String> badges = RlyRepoBadges.olderRepositories(new Set<Id>{ old.Id, fresh.Id });
            Test.stopTest();
            System.assert(noReason != null && noReason.contains('Say why'), 'A reason is needed: ' + noReason);
            System.assert(stillOpen != null && stillOpen.contains(old.Name), 'Open releases block the switch: ' + stillOpen);
            System.assertEquals(gitLabId(), RlyGitConnections.activeId(), 'GitLab is active');
            System.assertEquals(gitLabId(), RlyReleaseStore.git().Id, 'The hub\'s connection is the active one');
            System.assertEquals(gitHubId(), RlyReleaseStore.gitFor(RlyReleaseStore.release(old.Id)).Id, 'An old release keeps GitHub');
            System.assertEquals(gitLabId(), [SELECT Git_Connection__c FROM RLY_Release__c WHERE Id = :fresh.Id].Git_Connection__c,
                'A new release is stamped with the active connection');
            System.assertEquals('GitHub', badges.get(old.Id), 'The old release gets the GitHub badge');
            System.assert(!badges.containsKey(fresh.Id), 'A release in the active repository has no badge');
        }
    }

    @IsTest
    static void methodsChecklistsAndSecretsPerProvider() {
        System.runAs(RlyTestData.admin()) {
            RLY_Git_Connection__c gh = new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
                Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main');
            RLY_Git_Connection__c bb = new RLY_Git_Connection__c(Provider__c = 'Bitbucket', Repository__c = 'team/repo', Named_Credential__c = 'RLY_Bitbucket',
                Pipeline_Branch__c = 'main');
            RLY_Git_Connection__c az = new RLY_Git_Connection__c(Provider__c = 'AzureDevOps', Repository__c = 'org/proj/repo',
                Named_Credential__c = 'RLY_AzureDevOps', Pipeline__c = '12', Pipeline_Branch__c = 'main');
            RLY_Git_Connection__c gl = new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'group/project', Named_Credential__c = 'RLY_GitLab',
                Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main');
            Test.startTest();
            List<RlyMigrationMethods.Method> toGitLab = RlyMigrationMethods.forPair(gh, gl, 0);
            List<RlyMigrationMethods.Method> toAzureFull = RlyMigrationMethods.forPair(gh, az, 3);
            List<RlyMigrationMethods.Method> fromBitbucket = RlyMigrationMethods.forPair(bb, gl, null);
            List<RlyMigrationMethods.Method> toGitHub = RlyMigrationMethods.forPair(gl, gh, null);
            List<RlyMigrationMethods.Method> toBitbucket = RlyMigrationMethods.forPair(az, bb, null);
            List<RlyMigrationMethods.Method> noTarget = RlyMigrationMethods.forPair(gh, null, null);
            RlyMigrationChecklist.NewSetup n = new RlyMigrationChecklist.NewSetup();
            n.environments = new List<String>{ 'dev1', 'sit', 'prod' };
            n.prodBranch = 'prod';
            Integer items = 0;
            for (RLY_Git_Connection__c c : new List<RLY_Git_Connection__c>{ gh, gl, bb, az }) {
                n.target = c;
                items += RlyMigrationChecklist.newSetup(n, new RlyMigrationState()).size();
                items += RlyMigrationChecklist.oldSetup(c, new RlyMigrationState()).size();
            }
            String tokenText = RlyMigrationChecklist.tokenHint(gh, gl);
            String optional = RlyMigrationSecrets.optionalNames('GitLab', 'x: $SF_USERNAME $RELAY_MONITOR ${CI_PIPELINE_ID} $MODE vars.SCAN_RULES');
            List<RlyMigrationSecrets.Row> rows = RlyMigrationSecrets.rows('GitLab', n.environments);
            Test.stopTest();
            System.assert(toGitLab[0].possible && toGitLab[1].possible && toGitLab[2].possible, 'GitHub → empty GitLab: all three');
            System.assertEquals(4, toGitLab[1].clicks.size(), 'GitLab\'s GitHub importer clicks');
            System.assert(!toAzureFull[0].possible && toAzureFull[1].possible && !toAzureFull[2].possible, 'A full repository: only the importer');
            System.assert(!fromBitbucket[0].possible && fromBitbucket[0].why.contains('no migrate job'), 'Bitbucket\'s pipeline has no migrate job');
            System.assertEquals('Verify a copy you made', toGitHub[1].label, 'GitHub has no guided importer');
            System.assertEquals(3, toBitbucket[1].clicks.size(), 'Bitbucket\'s importer clicks');
            System.assert(!noTarget[0].possible, 'Configure the new connection first');
            System.assertEquals('The new provider\'s own importer', noTarget[1].label, 'No provider named before the connection is saved');
            System.assert(!noTarget[1].summary.contains('has no importer'), 'No "has no importer": ' + noTarget[1].summary);
            System.assert(noTarget[1].cons.startsWith('Done by hand in the new provider;'), 'No empty provider name: ' + noTarget[1].cons);
            RlyMigrationRepo.Refs refs = new RlyMigrationRepo.Refs();
            refs.branches = new List<String>{ 'a', 'b', 'c', 'd', 'e', 'f', 'g' };
            refs.more = true;
            System.assertEquals('a, b, c, d, e and 2+ more', refs.someNames(), 'A few branch names and how many more');
            refs.branches = new List<String>{ 'a', 'b' };
            refs.more = false;
            System.assertEquals('a, b', refs.someNames(), 'All when few');
            System.assert(items > 30, 'Checklists for every provider: ' + items);
            System.assert(tokenText.contains('write_repository'), tokenText);
            System.assertEquals('RELAY_MONITOR, SCAN_RULES', optional, 'Only names someone enters');
            System.assertEquals(4, rows.size(), 'One row per environment and one for all');
            System.assert(rows[3].names.contains('RELAY_TOKEN'), 'GitLab pushes with RELAY_TOKEN');
            System.assertEquals('RLY_Pipeline_Azure', RlyMigrationSecrets.resourceOf('AzureDevOps'), 'Azure\'s pipeline file');
        }
    }

    @IsTest
    static void repositoryReadsPerProvider() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/repositories/team/repo/refs/branches').reply(200, '{"values":[{"name":"main"}]}')
                .match('GET', '/repositories/team/repo/pullrequests').reply(200, '{"values":[{"id":3,"title":"T","links":{"html":{"href":"https://bitbucket.org/team/repo/pull-requests/3"}},'
                    + '"source":{"branch":{"name":"a"}},"destination":{"branch":{"name":"sit"}}}]}')
                .match('GET', '/_apis/git/repositories/repo/refs').reply(200, '{"value":[{"name":"refs/heads/main"},{"name":"refs/heads/sit"}]}')
                .match('GET', '/_apis/git/repositories/repo/pullrequests').reply(200, '{"value":[{"pullRequestId":9,"title":"T",'
                    + '"sourceRefName":"refs/heads/a","targetRefName":"refs/heads/sit"}]}')
                .match('GET', '/projects/group/project/merge_requests').reply(200, '[{"iid":12,"title":"T","web_url":"https://gitlab.com/group/project/-/merge_requests/12",'
                    + '"source_branch":"a","target_branch":"sit"}]');
            Test.setMock(HttpCalloutMock.class, mock);
            RlyGit bb = RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'Bitbucket', Repository__c = 'team/repo', Named_Credential__c = 'RLY_Bitbucket'));
            RlyGit az = RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'AzureDevOps', Repository__c = 'org/proj/repo',
                Named_Credential__c = 'RLY_AzureDevOps', Pipeline__c = '12'));
            RlyGit gl = RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'group/project', Named_Credential__c = 'RLY_GitLab',
                Pipeline_Branch__c = 'main'));
            Test.startTest();
            RlyMigrationRepo.Refs bbRefs = RlyMigrationRepo.refs(bb);
            RlyMigrationRepo.Refs azRefs = RlyMigrationRepo.refs(az);
            List<RlyMigrationRepo.OpenRequest> bbOpen = RlyMigrationRepo.openRequests(bb);
            List<RlyMigrationRepo.OpenRequest> azOpen = RlyMigrationRepo.openRequests(az);
            List<RlyMigrationRepo.OpenRequest> glOpen = RlyMigrationRepo.openRequests(gl);
            Test.stopTest();
            System.assertEquals('main', bbRefs.branches[0], 'Bitbucket branches');
            System.assertEquals(new List<String>{ 'main', 'sit' }, azRefs.branches, 'Azure DevOps branches without refs/heads/');
            System.assertEquals('#3', bbOpen[0].label, 'Bitbucket pull request');
            System.assertEquals('a → sit', azOpen[0].branches, 'Azure DevOps pull request branches');
            System.assertEquals('!12', glOpen[0].label, 'GitLab merge request');
            System.assertEquals('https://dev.azure.com/org/proj/_git/repo', RlyMigrationRepo.pushUrl(az), 'Azure DevOps push address');
            System.assertEquals('https://bitbucket.org/team/repo.git', RlyMigrationRepo.pushUrl(bb), 'Bitbucket push address');
            System.assertEquals('azure', RlyMigrationRepo.providerKey('AzureDevOps'), 'The migrate job\'s name');
        }
    }

    @IsTest
    static void checksAndSummariesReadTheirResults() {
        System.runAs(RlyTestData.admin()) {
            RlySyncResult.View same = new RlySyncResult.View();
            same.syncId = 'SYN-1';
            same.status = 'Succeeded';
            same.done = true;
            RlySyncResult.View differs = new RlySyncResult.View();
            differs.status = 'Succeeded';
            differs.done = true;
            differs.counts = new Map<String, Integer>{ 'onlyInOrg' => 2, 'different' => 1 };
            RlySyncResult.View failed = new RlySyncResult.View();
            failed.status = RlySyncStore.FAILED;
            Map<String, Object> going = new Map<String, Object>{ 'status' => 'In progress', 'phase' => 'branches',
                'branches' => new Map<String, Object>{ 'found' => 10, 'pushed' => 5, 'failed' => 0 } };
            Test.startTest();
            RlyMigrationState.OrgCheck inSync = RlyMigrationSync.checkOf(same, 'drift');
            RlyMigrationState.OrgCheck differ = RlyMigrationSync.checkOf(differs, 'parts');
            RlyMigrationState.OrgCheck broken = RlyMigrationSync.checkOf(failed, 'drift');
            RlyMigrationView.Summary progress = RlyMigrationSummary.of(going);
            RlyMigrationState bad = RlyMigrationState.of('{not json');
            Test.stopTest();
            System.assertEquals(RlyMigrationSync.IN_SYNC, inSync.status, 'Nothing differs');
            System.assertEquals(RlyMigrationSync.DIFFERS, differ.status, 'Differences');
            System.assert(differ.detail.contains('3 component(s)') && differ.detail.contains('only in the org'), differ.detail);
            System.assertEquals(RlyMigrationSync.FAILED, broken.status, 'Failed');
            System.assertEquals(57, progress.percent, 'Half the branches pushed');
            System.assertEquals(null, RlyMigrationSummary.of(null), 'No result, no summary');
            System.assertEquals(0, bad.events.size(), 'An unreadable state starts empty');
        }
    }

    @IsTest
    static void onlyAdminsUseTheMigrationTab() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            String refused;
            Test.startTest();
            try {
                RlyMigrationController.getMigration();
            } catch (AuraHandledException e) {
                refused = refusal(e);
            }
            Test.stopTest();
            System.assert(refused != null && refused.contains('admins'), 'Admins only: ' + refused);
        }
    }
}
