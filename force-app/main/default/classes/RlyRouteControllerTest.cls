/**
 * @description Tests for the hub's Git connection and route (RlyRouteController, RlyRouteRules, RlyGitValidator,
 * RlyGitCheck). Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it (a callout can't follow DML).
 */
@IsTest
private class RlyRouteControllerTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static void insertRoute() {
        insert new List<RLY_Org__c>{
            RlyTestData.org('DEV1', 'Developer', 'dev1'),
            RlyTestData.stage('UAT', 'uat', 2),
            RlyTestData.stage('SIT', 'sit', 1),
            RlyTestData.org('PROD', 'Hub', 'prod')
        };
    }

    private static String gitJson(String provider, String repo, String pipeline) {
        return JSON.serialize(new Map<String, Object>{
            'Provider__c' => provider, 'Repository__c' => repo, 'Named_Credential__c' => 'RLY_' + provider,
            'Pipeline__c' => pipeline, 'Pipeline_Branch__c' => 'main', 'Source_Path__c' => 'force-app/main/default/', 'Code_Scan__c' => true
        });
    }

    private static RlyHttpMock gitHubRepo() {
        return new RlyHttpMock()
            .match('GET', '/branches/dev1').reply(404, '{"message":"Branch not found"}')
            .match('GET', '/branches/').reply(200, '{"name":"x"}')
            .match('GET', '/contents/').reply(200, '{"type":"file"}')
            .match('GET', '/git/ref/heads/main').reply(200, '{"object":{"sha":"abc123"}}')
            .match('POST', '/git/refs').reply(201, '{"ref":"refs/heads/dev1"}')
            .match('GET', '/repos/acme/sfdx').reply(200, '{"default_branch":"main"}');
    }

    @IsTest
    static void routeIsBuiltFromTheOrgs() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            RlyRouteController.Setup s = RlyRouteController.getSetup();
            System.assertEquals(null, s.git, 'No Git connection yet');
            System.assertEquals(1, s.developers.size(), 'One developer org');
            System.assertEquals('SIT', s.stages[0].Name, 'Stage order 1 first');
            System.assertEquals('UAT', s.stages[1].Name, 'Then 2');
            System.assertEquals('PROD', s.stages[2].Name, 'The hub last');
            System.assert(s.warnings.isEmpty(), 'A complete route: ' + s.warnings);

            List<String> w = RlyRouteRules.warnings(
                new List<RLY_Org__c>(),
                new List<RLY_Org__c>{ new RLY_Org__c(Name = 'SIT', Role__c = 'Stage', Branch__c = 'sit'),
                                      new RLY_Org__c(Name = 'UAT', Role__c = 'Stage', Branch__c = 'sit'),
                                      new RLY_Org__c(Name = 'QA', Role__c = 'Stage') });
            String joined = String.join(w, ' | ');
            System.assert(joined.contains('more than one org'), joined);
            System.assert(joined.contains('QA has no branch'), joined);
            System.assert(joined.contains('no Git environment'), joined);
            System.assert(joined.contains('role Hub'), joined);
            System.assert(joined.contains('developer org'), joined);
            System.assert(RlyRouteRules.warnings(new List<RLY_Org__c>(), new List<RLY_Org__c>())[0].contains('at least one stage'), 'Empty route');

            Map<String, Id> ids = new Map<String, Id>();
            for (RLY_Org__c o : [SELECT Id, Name FROM RLY_Org__c WHERE Name IN ('SIT', 'UAT', 'PROD', 'DEV1')]) {
                ids.put(o.Name, o.Id);
            }
            RlyRouteController.saveRoute(new List<Id>{ ids.get('PROD'), ids.get('UAT'), ids.get('SIT') });
            List<RLY_Org__c> stages = RlyRouteController.getSetup().stages;
            System.assertEquals('UAT', stages[0].Name, 'Reordered');
            System.assertEquals('PROD', stages[2].Name, 'The hub stays last');

            Boolean refused = false;
            try {
                RlyRouteController.saveRoute(new List<Id>{ ids.get('DEV1') });
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Developer orgs are not stages');
        }
    }

    @IsTest
    static void gitHubConnectionIsCheckedWithItsBranches() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            Id gitId = RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            RLY_Git_Connection__c saved = [SELECT Name, Source_Path__c, Status__c FROM RLY_Git_Connection__c WHERE Id = :gitId];
            System.assertEquals('GitHub acme/sfdx', saved.Name, 'Named after the repository');
            System.assertEquals('force-app/main/default', saved.Source_Path__c, 'Trailing slash removed');
            System.assertEquals(gitId, RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml')), 'One connection per hub');

            Test.setMock(HttpCalloutMock.class, gitHubRepo());
            Test.startTest();
            RLY_Git_Connection__c checked = RlyRouteController.checkGit();
            Test.stopTest();
            System.assertEquals('Connected', checked.Status__c, checked.Status_Message__c);
            System.assert(checked.Status_Message__c.contains('Default branch: main'), checked.Status_Message__c);
            System.assert(checked.Status_Message__c.contains('Missing branches: dev1'), checked.Status_Message__c);
        }
    }

    @IsTest
    static void missingBranchesAreCreated() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            RlyHttpMock mock = gitHubRepo();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<String> created = RlyRouteController.createBranches();
            Test.stopTest();
            System.assertEquals(new List<String>{ 'dev1' }, created, 'Only the missing branch');
            System.assert(mock.callLog().contains('POST callout:RLY_GitHub/repos/acme/sfdx/git/refs'), mock.calls);
        }
    }

    @IsTest
    static void failedChecksSayWhy() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/contents/.github').reply(404, '{}')
                .match('GET', '/repos/acme/sfdx/branches/main').reply(200, '{}')
                .match('GET', '/contents/scripts').reply(200, '{}')
                .match('GET', '/repos/acme/sfdx').reply(200, '{"default_branch":"main"}'));
            Test.startTest();
            RLY_Git_Connection__c checked = RlyRouteController.checkGit();
            Test.stopTest();
            System.assertEquals('Failed', checked.Status__c, 'The workflow file is missing');
            System.assert(checked.Status_Message__c.contains('.github/workflows/release-relay.yml'), checked.Status_Message__c);
        }
    }

    @IsTest
    static void refusesBadConnections() {
        System.runAs(RlyTestData.admin()) {
            List<String> problems = RlyGitValidator.validate(new RLY_Git_Connection__c(Provider__c = 'Svn', Repository__c = '',
                Named_Credential__c = '1 bad', Pipeline__c = 'bad file!', Pipeline_Branch__c = '', Source_Path__c = '../up'));
            System.assertEquals(6, problems.size(), 'Every field: ' + problems);
            List<String> shape = RlyGitValidator.validate(new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'no-slash',
                Named_Credential__c = 'RLY_GitHub', Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app'));
            System.assert(shape[0].contains('owner/repository'), shape[0]);
            Integer refused = 0;
            try { RlyRouteController.saveGit('nope'); } catch (AuraHandledException e) { refused++; }
            try { RlyRouteController.checkGit(); } catch (AuraHandledException e) { refused++; }
            try { RlyRouteController.createBranches(); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(3, refused, 'Bad JSON refused; nothing to check or create branches with yet');
        }
    }
}
