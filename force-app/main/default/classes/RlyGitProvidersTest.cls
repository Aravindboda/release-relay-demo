/**
 * @description Tests for the four Git providers (RlyGit, RlyGitHub, RlyGitLab, RlyBitbucket, RlyAzureRepos) and
 * their error advice (RlyGitAdvice). Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyGitProvidersTest {

    private static RlyHttpMock providers() {
        return new RlyHttpMock()
            // GitLab
            .match('GET', '/projects/acme/salesforce/repository/branches/nope').reply(404, '{}')
            .match('GET', '/projects/acme/salesforce/repository/branches/').reply(200, '{}')
            .match('GET', '/projects/acme/salesforce/repository/files/').reply(200, '{}')
            .match('POST', '/projects/acme/salesforce/repository/branches').reply(201, '{}')
            .match('GET', '/projects/acme/salesforce').reply(200, '{"default_branch":"main"}')
            // Bitbucket
            .match('GET', '/repositories/ws/repo/refs/branches/nope').reply(404, '{}')
            .match('GET', '/repositories/ws/repo/refs/branches/').reply(200, '{"target":{"hash":"def456"}}')
            .match('GET', '/repositories/ws/repo/src/').reply(200, '{}')
            .match('POST', '/repositories/ws/repo/refs/branches').reply(201, '{}')
            .match('GET', '/repositories/ws/repo').reply(200, '{"mainbranch":{"name":"main"}}')
            // Azure DevOps
            .match('GET', '_apis/git/repositories/repo/refs?filter=heads/main').reply(200, '{"value":[{"name":"refs/heads/main","objectId":"aaa"}]}')
            .match('GET', '_apis/git/repositories/repo/refs?filter=').reply(200, '{"value":[]}')
            .match('GET', '_apis/git/repositories/repo/items').reply(200, '{}')
            .match('POST', '_apis/git/repositories/repo/refs').reply(200, '{"value":[{"success":true}]}')
            .match('GET', '_apis/git/repositories/repo?').reply(200, '{"defaultBranch":"refs/heads/main"}')
            .match('GET', '_apis/pipelines/12').reply(200, '{"id":12}');
    }

    @IsTest
    static void gitLabBitbucketAndAzure() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock mock = providers();
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
            System.assertEquals(3, mock.callLog().countMatches('POST '), 'One branch created per provider');
        }
    }

    @IsTest
    static void branchHeadsForEveryProvider() {
        System.runAs(RlyTestData.admin()) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/repos/acme/release/branches/gone').reply(404, '{}')
                .match('GET', '/repos/acme/release/branches/main').reply(200, '{"name":"main","commit":{"sha":"gh111"}}')
                .match('GET', '/projects/acme/salesforce/repository/branches/gone').reply(404, '{}')
                .match('GET', '/projects/acme/salesforce/repository/branches/main').reply(200, '{"commit":{"id":"gl222"}}')
                .match('GET', '/repositories/ws/repo/refs/branches/gone').reply(404, '{}')
                .match('GET', '/repositories/ws/repo/refs/branches/main').reply(200, '{"target":{"hash":"bb333"}}')
                .match('GET', '_apis/git/repositories/repo/refs?filter=heads/main').reply(200, '{"value":[{"name":"refs/heads/main","objectId":"az444"}]}')
                .match('GET', '_apis/git/repositories/repo/refs?filter=').reply(200, '{"value":[]}'));
            Map<String, RLY_Git_Connection__c> conns = new Map<String, RLY_Git_Connection__c>{
                'gh111' => new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub', Pipeline__c = 'release-relay.yml'),
                'gl222' => new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/salesforce', Named_Credential__c = 'RLY_GitLab'),
                'bb333' => new RLY_Git_Connection__c(Provider__c = 'Bitbucket', Repository__c = 'ws/repo', Named_Credential__c = 'RLY_Bitbucket'),
                'az444' => new RLY_Git_Connection__c(Provider__c = 'AzureDevOps', Repository__c = 'org/proj/repo', Named_Credential__c = 'RLY_AzureDevOps', Pipeline__c = '12')
            };
            Set<String> labels = new Set<String>();
            Test.startTest();
            for (String sha : conns.keySet()) {
                RlyGit git = RlyGit.forConnection(conns.get(sha));
                System.assertEquals(sha, git.branchHead('main'), conns.get(sha).Provider__c + ' head');
                System.assertEquals(null, git.branchHead('gone'), conns.get(sha).Provider__c + ' missing branch');
                labels.add(RlyGitName.labelFor(conns.get(sha)));
            }
            Test.stopTest();
            System.assertEquals(new Set<String>{ 'GitHub', 'GitLab', 'Bitbucket', 'Azure DevOps' }, labels, 'Provider names');
            System.assertEquals(null, RlyGitName.labelFor(null), 'No connection');
            System.assertEquals(null, RlyGitName.labelFor(new RLY_Git_Connection__c(Provider__c = 'Unknown', Repository__c = 'a/b',
                Named_Credential__c = 'RLY_Git')), 'A provider the hub doesn\'t know');
            System.assertEquals(null, RlyGitName.labelFor(new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'a/b')),
                'No Named Credential');
        }
    }

    @IsTest
    static void badConnectionsAreRefused() {
        System.runAs(RlyTestData.admin()) {
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
            System.assertEquals('a%20b/c.cls', RlyGitRequest.encodePath('a b/c.cls'), 'Path segments encoded, slashes kept');
        }
    }

    @IsTest
    static void providerErrorsGiveAdvice() {
        System.runAs(RlyTestData.admin()) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/repos/acme/sfdx/branches/main').reply(401, '{"message":"Bad credentials"}')
                .match('GET', '/repos/acme/sfdx/git/ref/heads/gone').reply(404, '{}')
                .match('GET', '/repos/acme/sfdx').reply(403, '{"message":"Forbidden"}'));
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
