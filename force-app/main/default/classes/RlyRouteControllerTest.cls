/**
 * Tests for the hub's Git connection, route and the four Git providers.
 * Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it (a callout can't follow DML).
 */
@IsTest
private class RlyRouteControllerTest {

    /** Answers by the first rule whose method and URL fragment match; anything else is 404. */
    private class GitMock implements HttpCalloutMock {
        private List<List<Object>> rules = new List<List<Object>>();
        public List<String> calls = new List<String>();

        public GitMock reply(String method, String fragment, Integer status, String body) {
            rules.add(new List<Object>{ method, fragment, status, body });
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            calls.add(req.getMethod() + ' ' + url);
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            for (List<Object> r : rules) {
                if (req.getMethod() == (String) r[0] && url.contains((String) r[1])) {
                    res.setStatusCode((Integer) r[2]);
                    res.setBody((String) r[3]);
                    return res;
                }
            }
            res.setStatusCode(404);
            res.setBody('{"message":"Not Found"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        User admin = admin();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Admin']) {
            if ([SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :admin.Id AND PermissionSetId = :ps.Id].isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id);
            }
        }
    }

    private static User admin() {
        return [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true
                ORDER BY CreatedDate ASC LIMIT 1];
    }

    private static RLY_Org__c org(String name, String role, String branch, Decimal stageOrder) {
        return new RLY_Org__c(Name = name, Role__c = role, Branch__c = branch, Stage_Order__c = stageOrder,
            Git_Environment__c = branch, My_Domain__c = 'https://' + name.toLowerCase() + '.my.salesforce.com',
            Login_Type__c = 'Production', Username__c = 'relay@' + name.toLowerCase() + '.demo',
            Client_Id__c = '3MVG9demo', Certificate__c = 'release_relay', Status__c = 'Connected');
    }

    private static void insertRoute() {
        insert new List<RLY_Org__c>{
            org('DEV1', 'Developer', 'dev1', null),
            org('UAT', 'Stage', 'uat', 2),
            org('SIT', 'Stage', 'sit', 1),
            org('PROD', 'Hub', 'prod', null)
        };
    }

    private static String gitJson(String provider, String repo, String pipeline) {
        return JSON.serialize(new Map<String, Object>{
            'Provider__c' => provider, 'Repository__c' => repo, 'Named_Credential__c' => 'RLY_' + provider,
            'Pipeline__c' => pipeline, 'Pipeline_Branch__c' => 'main', 'Source_Path__c' => 'force-app/main/default/', 'Code_Scan__c' => true
        });
    }

    private static GitMock gitHubRepo() {
        return new GitMock()
            .reply('GET', '/branches/dev1', 404, '{"message":"Branch not found"}')
            .reply('GET', '/branches/', 200, '{"name":"x"}')
            .reply('GET', '/contents/', 200, '{"type":"file"}')
            .reply('GET', '/git/ref/heads/main', 200, '{"object":{"sha":"abc123"}}')
            .reply('POST', '/git/refs', 201, '{"ref":"refs/heads/dev1"}')
            .reply('GET', '/repos/acme/sfdx', 200, '{"default_branch":"main"}');
    }

    @IsTest
    static void routeIsBuiltFromTheOrgs() {
        System.runAs(admin()) {
            insertRoute();
            RlyRouteController.Setup s = RlyRouteController.getSetup();
            System.assertEquals(null, s.git, 'No Git connection yet');
            System.assertEquals(1, s.developers.size(), 'One developer org');
            System.assertEquals('SIT', s.stages[0].Name, 'Stage order 1 first');
            System.assertEquals('UAT', s.stages[1].Name, 'Then 2');
            System.assertEquals('PROD', s.stages[2].Name, 'The hub last');
            System.assert(s.warnings.isEmpty(), 'A complete route: ' + s.warnings);

            List<String> w = RlyRouteController.routeWarnings(
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
            System.assert(RlyRouteController.routeWarnings(new List<RLY_Org__c>(), new List<RLY_Org__c>())[0].contains('at least one stage'), 'Empty route');

            Id sit = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
            Id uat = [SELECT Id FROM RLY_Org__c WHERE Name = 'UAT'].Id;
            Id prod = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD'].Id;
            RlyRouteController.saveRoute(new List<Id>{ prod, uat, sit });
            List<RLY_Org__c> stages = RlyRouteController.getSetup().stages;
            System.assertEquals('UAT', stages[0].Name, 'Reordered');
            System.assertEquals('PROD', stages[2].Name, 'The hub stays last');

            Boolean refused = false;
            try {
                RlyRouteController.saveRoute(new List<Id>{ [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1'].Id });
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Developer orgs are not stages');
        }
    }

    @IsTest
    static void gitHubConnectionIsCheckedWithItsBranches() {
        System.runAs(admin()) {
            insertRoute();
            Id gitId = RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            RLY_Git_Connection__c saved = [SELECT Name, Source_Path__c, Status__c FROM RLY_Git_Connection__c WHERE Id = :gitId];
            System.assertEquals('GitHub acme/sfdx', saved.Name, 'Named after the repository');
            System.assertEquals('force-app/main/default', saved.Source_Path__c, 'Trailing slash removed');
            System.assertEquals(gitId, RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml')), 'One connection per hub');

            GitMock mock = gitHubRepo();
            Test.setMock(HttpCalloutMock.class, mock);
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
        System.runAs(admin()) {
            insertRoute();
            RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            GitMock mock = gitHubRepo();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<String> created = RlyRouteController.createBranches();
            Test.stopTest();
            System.assertEquals(new List<String>{ 'dev1' }, created, 'Only the missing branch');
            System.assert(String.join(mock.calls, '\n').contains('POST callout:RLY_GitHub/repos/acme/sfdx/git/refs'), mock.calls);
        }
    }

    @IsTest
    static void failedChecksSayWhy() {
        System.runAs(admin()) {
            insertRoute();
            RlyRouteController.saveGit(gitJson('GitHub', 'acme/sfdx', 'release-relay.yml'));
            Test.setMock(HttpCalloutMock.class, new GitMock()
                .reply('GET', '/contents/.github', 404, '{}')
                .reply('GET', '/repos/acme/sfdx/branches/main', 200, '{}')
                .reply('GET', '/contents/scripts', 200, '{}')
                .reply('GET', '/repos/acme/sfdx', 200, '{"default_branch":"main"}'));
            Test.startTest();
            RLY_Git_Connection__c checked = RlyRouteController.checkGit();
            Test.stopTest();
            System.assertEquals('Failed', checked.Status__c, 'The workflow file is missing');
            System.assert(checked.Status_Message__c.contains('.github/workflows/release-relay.yml'), checked.Status_Message__c);
        }
    }

    @IsTest
    static void refusesBadConnections() {
        System.runAs(admin()) {
            List<String> problems = RlyRouteController.validate(new RLY_Git_Connection__c(Provider__c = 'Svn', Repository__c = '',
                Named_Credential__c = '1 bad', Pipeline__c = 'bad file!', Pipeline_Branch__c = '', Source_Path__c = '../up'));
            System.assertEquals(6, problems.size(), 'Every field: ' + problems);
            List<String> shape = RlyRouteController.validate(new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'no-slash',
                Named_Credential__c = 'RLY_GitHub', Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app'));
            System.assert(shape[0].contains('owner/repository'), shape[0]);
            Boolean unreadable = false;
            try {
                RlyRouteController.saveGit('nope');
            } catch (AuraHandledException e) {
                unreadable = true;
            }
            System.assert(unreadable, 'Bad JSON refused');
            Boolean noConnection = false;
            try {
                RlyRouteController.checkGit();
            } catch (AuraHandledException e) {
                noConnection = true;
            }
            System.assert(noConnection, 'Nothing to check yet');
            Boolean noConnectionToCreate = false;
            try {
                RlyRouteController.createBranches();
            } catch (AuraHandledException e) {
                noConnectionToCreate = true;
            }
            System.assert(noConnectionToCreate, 'Nothing to create branches with yet');
        }
    }

    @IsTest
    static void gitLabBitbucketAndAzure() {
        System.runAs(admin()) {
            GitMock mock = new GitMock()
                // GitLab
                .reply('GET', '/projects/acme/salesforce/repository/branches/nope', 404, '{}')
                .reply('GET', '/projects/acme/salesforce/repository/branches/', 200, '{}')
                .reply('GET', '/projects/acme/salesforce/repository/files/', 200, '{}')
                .reply('POST', '/projects/acme/salesforce/repository/branches', 201, '{}')
                .reply('GET', '/projects/acme/salesforce', 200, '{"default_branch":"main"}')
                // Bitbucket
                .reply('GET', '/repositories/ws/repo/refs/branches/nope', 404, '{}')
                .reply('GET', '/repositories/ws/repo/refs/branches/', 200, '{"target":{"hash":"def456"}}')
                .reply('GET', '/repositories/ws/repo/src/', 200, '{}')
                .reply('POST', '/repositories/ws/repo/refs/branches', 201, '{}')
                .reply('GET', '/repositories/ws/repo', 200, '{"mainbranch":{"name":"main"}}')
                // Azure DevOps
                .reply('GET', '_apis/git/repositories/repo/refs?filter=heads/main', 200, '{"value":[{"name":"refs/heads/main","objectId":"aaa"}]}')
                .reply('GET', '_apis/git/repositories/repo/refs?filter=', 200, '{"value":[]}')
                .reply('GET', '_apis/git/repositories/repo/items', 200, '{}')
                .reply('POST', '_apis/git/repositories/repo/refs', 200, '{"value":[{"success":true}]}')
                .reply('GET', '_apis/git/repositories/repo?', 200, '{"defaultBranch":"refs/heads/main"}')
                .reply('GET', '_apis/pipelines/12', 200, '{"id":12}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<RLY_Git_Connection__c> conns = new List<RLY_Git_Connection__c>{
                new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/salesforce', Named_Credential__c = 'RLY_GitLab', Pipeline__c = '.gitlab-ci.yml'),
                new RLY_Git_Connection__c(Provider__c = 'Bitbucket', Repository__c = 'ws/repo', Named_Credential__c = 'RLY_Bitbucket'),
                new RLY_Git_Connection__c(Provider__c = 'AzureDevOps', Repository__c = 'org/proj/repo', Named_Credential__c = 'RLY_AzureDevOps', Pipeline__c = '12')
            };
            for (RLY_Git_Connection__c c : conns) {
                RlyGit git = RlyGit.forConnection(c);
                System.assertEquals('main', git.defaultBranch(), c.Provider__c + ' default branch');
                System.assertEquals(true, git.branchExists('main'), c.Provider__c + ' branch found');
                System.assertEquals(false, git.branchExists('nope'), c.Provider__c + ' branch missing');
                System.assertEquals(true, git.fileExists('scripts/release-relay.js', 'main'), c.Provider__c + ' file');
                git.createBranch('sit', 'main');
                git.checkPipeline();
                System.assert(git.pipelineFiles().contains('scripts/release-relay.js'), c.Provider__c + ' pipeline files');
                System.assert(String.isNotBlank(git.repositoryHint()), 'Hint');
            }
            Test.stopTest();
            System.assertEquals(3, String.join(mock.calls, '\n').countMatches('POST '), 'One branch created per provider');

            Boolean badAzure = false;
            try {
                RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'AzureDevOps', Repository__c = 'org/proj/repo',
                    Named_Credential__c = 'RLY_AzureDevOps', Pipeline__c = 'release-relay.yml')).checkPipeline();
            } catch (RlyGit.GitException e) {
                badAzure = e.getMessage().contains('pipeline id');
            }
            System.assert(badAzure, 'Azure needs a pipeline id');
            Boolean noProvider = false;
            try {
                RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'Svn', Repository__c = 'x', Named_Credential__c = 'X'));
            } catch (RlyGit.GitException e) {
                noProvider = true;
            }
            System.assert(noProvider, 'Unknown provider refused');
            System.assertEquals('a%20b/c.cls', RlyGit.encPath('a b/c.cls'), 'Path segments encoded, slashes kept');
        }
    }

    @IsTest
    static void providerErrorsGiveAdvice() {
        System.runAs(admin()) {
            Test.setMock(HttpCalloutMock.class, new GitMock()
                .reply('GET', '/repos/acme/sfdx/branches/main', 401, '{"message":"Bad credentials"}')
                .reply('GET', '/repos/acme/sfdx/git/ref/heads/gone', 404, '{}')
                .reply('GET', '/repos/acme/sfdx', 403, '{"message":"Forbidden"}'));
            Test.startTest();
            RlyGit git = RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/sfdx',
                Named_Credential__c = 'RLY_GitHub', Pipeline__c = 'release-relay.yml'));
            List<String> messages = new List<String>();
            try { git.defaultBranch(); } catch (RlyGit.GitException e) { messages.add(e.getMessage()); }
            try { git.branchExists('main'); } catch (RlyGit.GitException e) { messages.add(e.getMessage()); }
            try { git.createBranch('x', 'gone'); } catch (RlyGit.GitException e) { messages.add(e.getMessage()); }
            Test.stopTest();
            System.assertEquals(3, messages.size(), 'Every call failed: ' + messages);
            System.assert(messages[0].contains('lacks permission'), messages[0]);
            System.assert(messages[1].contains('renew'), messages[1]);
            System.assert(messages[2].contains('wasn\'t found'), messages[2]);
        }
    }
}
