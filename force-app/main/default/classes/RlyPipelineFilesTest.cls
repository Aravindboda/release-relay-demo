/**
 * @description Tests for the pipeline files (RlyPipelineFiles, RlyRouteController.getPipelineFiles and
 * updatePipelineFiles, RlyPipelineUpdate, RlyGit.openPullRequest). Every test runs as an existing active System Administrator through
 * System.runAs (or as a user without the admin permission set). DML happens before Test.startTest; callouts after it.
 */
@IsTest
private class RlyPipelineFilesTest {

    private static final String WORKFLOW_URL = '/repos/acme/release/contents/.github/workflows/release-relay.yml';
    private static final String SCRIPT_URL = '/repos/acme/release/contents/scripts/release-relay.js';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static void connectGitHub() {
        insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
            Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default',
            Code_Scan__c = true, Status__c = 'Connected');
    }

    // The packaged version of a GitHub hub's files (the workflow and the script), read like the class reads it.
    private static Integer packaged() {
        Integer lowest;
        for (StaticResource sr : [SELECT Body FROM StaticResource WHERE Name IN ('RLY_Pipeline_GitHub', 'RLY_Pipeline_Script')]) {
            Integer found = RlyPipelineFiles.versionIn(sr.Body.toString());
            lowest = lowest == null || found < lowest ? found : lowest;
        }
        return lowest;
    }

    private static String stamped(Integer fileVersion) {
        return '# Release Relay pipeline files: version ' + fileVersion + '\nname: Release Relay\n';
    }

    @IsTest
    static void upToDate() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            Integer v = packaged();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', WORKFLOW_URL + '?ref=main').reply(200, stamped(v))
                .match('GET', SCRIPT_URL + '?ref=main').reply(200, '#!/usr/bin/env node\n// ' + stamped(v)));
            Test.startTest();
            RlyPipelineFiles.Status s = RlyRouteController.getPipelineFiles();
            Test.stopTest();
            System.assert(v != null && v > 0, 'Packaged files carry a version: ' + v);
            System.assertEquals(v, s.packagedVersion, 'Packaged version');
            System.assertEquals(v, s.repoVersion, 'Repository version');
            System.assert(s.upToDate, s.message);
            System.assert(s.isAdmin, 'Admin');
            System.assertEquals('GitHub', s.provider, 'Provider');
            System.assertEquals('main', s.branch, 'Pipeline branch');
            System.assertEquals(5, s.files.size(), 'Every packaged file');
            System.assertEquals('RLY_Pipeline_GitHub', s.files[0].resourceName, 'This hub\'s provider first');
            System.assertEquals('release-relay.yml', s.files[0].name, 'File name');
            System.assertEquals('.github/workflows/release-relay.yml', s.files[0].repoPath, 'Workflow path');
            System.assertEquals(RlyPipelineFiles.EVERY_PROVIDER, s.files[1].provider, 'Then the script');
            System.assert(s.files[1].forThisHub && !s.files[2].forThisHub && !s.files[4].forThisHub, 'Other providers last');
            System.assertEquals(null, s.files[2].repoVersion, 'Other providers\' files aren\'t read');
            System.assert(s.message.startsWith('Up to date'), s.message);
        }
    }

    @IsTest
    static void olderInTheRepository() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            Integer v = packaged();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', WORKFLOW_URL + '?ref=main').reply(200, stamped(v - 1))
                .match('GET', SCRIPT_URL + '?ref=main').reply(200, stamped(v)));
            Test.startTest();
            RlyPipelineFiles.Status s = RlyRouteController.getPipelineFiles();
            Test.stopTest();
            System.assertEquals(v - 1, s.repoVersion, 'The lowest version in the repository');
            System.assertEquals(v - 1, s.files[0].repoVersion, 'The workflow\'s version');
            System.assertEquals(v, s.files[1].repoVersion, 'The script\'s version');
            System.assert(!s.upToDate, 'An update is available');
            System.assert(s.message.contains('version ' + v + ' available'), s.message);
            System.assertEquals(0, RlyPipelineFiles.versionIn('name: no version line'), 'Unnumbered files are the oldest');
        }
    }

    @IsTest
    static void missingInTheRepository() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', WORKFLOW_URL + '?ref=main').reply(200, 'name: Release Relay\n'));
            Test.startTest();
            RlyPipelineFiles.Status s = RlyRouteController.getPipelineFiles();
            Test.stopTest();
            System.assertEquals(null, s.repoVersion, 'A file is missing');
            System.assertEquals(0, s.files[0].repoVersion, 'The workflow is there, without a version');
            System.assertEquals(null, s.files[1].repoVersion, 'The script isn\'t there');
            System.assert(!s.upToDate, 'Not up to date');
            System.assert(s.message.contains('scripts/release-relay.js'), s.message);
        }
    }

    @IsTest
    static void updateViaPullRequest() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            Integer v = packaged();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/git/ref/heads/main').reply(200, '{"object":{"sha":"abc123"}}')
                .match('POST', '/git/refs').reply(201, '{"ref":"refs/heads/release-relay/pipeline-files-v' + v + '"}')
                .match('PUT', '/contents/').reply(201, '{"content":{}}')
                .match('GET', '/pulls?').reply(200, '[]')
                .match('POST', '/repos/acme/release/pulls').reply(201, '{"number":7,"html_url":"https://github.com/acme/release/pull/7"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPipelineFiles.UpdateResult r = RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_PULL_REQUEST);
            Test.stopTest();
            System.assert(r.ok, r.message);
            System.assertEquals('https://github.com/acme/release/pull/7', r.url, 'The pull request');
            String calls = mock.callLog();
            System.assert(calls.contains('POST callout:RLY_GitHub/repos/acme/release/git/refs'), 'The update branch is created: ' + calls);
            System.assertEquals(2, calls.countMatches('PUT '), 'The workflow and the script: ' + calls);
            System.assert(mock.bodyFor(SCRIPT_URL).contains('pipeline-files-v' + v), 'Committed on the update branch');
            String pr = mock.bodyFor('/repos/acme/release/pulls');
            System.assert(pr.contains('pipeline files v' + v) && pr.contains('"base":"main"'), pr);
        }
    }

    @IsTest
    static void openPullRequestIsReused() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/branches/release-relay/pipeline-files-v').reply(200, '{"name":"x"}')
                .match('PUT', '/contents/').reply(200, '{"content":{}}')
                .match('GET', '/pulls?').reply(200, '[{"number":6,"state":"open","html_url":"https://github.com/acme/release/pull/6"}]');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPipelineFiles.UpdateResult r = RlyRouteController.updatePipelineFiles(null);
            Test.stopTest();
            System.assert(r.ok, r.message);
            System.assertEquals('https://github.com/acme/release/pull/6', r.url, 'The open pull request');
            System.assert(!mock.callLog().contains('POST '), 'No new branch or pull request: ' + mock.callLog());
        }
    }

    @IsTest
    static void updateViaCommit() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/contents/').reply(200, '{"sha":"old1"}')
                .match('PUT', '/contents/').reply(200, '{"commit":{"sha":"c0ffee","html_url":"https://github.com/acme/release/commit/c0ffee"}}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPipelineFiles.UpdateResult r = RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_COMMIT);
            Test.stopTest();
            System.assert(r.ok, r.message);
            System.assertEquals('https://github.com/acme/release/commit/c0ffee', r.url, 'The commit');
            System.assert(mock.bodyFor(WORKFLOW_URL).contains('"sha":"old1"'), 'Replaces the file on the pipeline branch');
            System.assert(mock.bodyFor(WORKFLOW_URL).contains('"branch":"main"'), 'Straight to the pipeline branch');
            System.assert(!mock.callLog().contains('POST '), 'No branch or pull request: ' + mock.callLog());
        }
    }

    @IsTest
    static void workflowsPermissionMissing() {
        System.runAs(RlyTestData.admin()) {
            connectGitHub();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('PUT', '/contents/.github/workflows/').reply(403, '{"message":"Resource not accessible by personal access token"}'));
            Test.startTest();
            RlyPipelineFiles.UpdateResult r = RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_COMMIT);
            Test.stopTest();
            System.assert(!r.ok, 'Refused');
            System.assertEquals(RlyGitAdvice.WORKFLOWS_ADVICE, r.message, 'Says which permission the token needs');
            System.assertEquals(null, r.url, 'No link');
        }
    }

    @IsTest
    static void otherProvidersAndNoConnection() {
        System.runAs(RlyTestData.admin()) {
            RlyPipelineFiles.Status unconnected = RlyRouteController.getPipelineFiles();
            System.assertEquals(null, unconnected.provider, 'No Git connection');
            System.assert(unconnected.packagedVersion != null, 'The packaged version is known without a connection');
            System.assertEquals('RLY_Pipeline_Script', unconnected.files[0].resourceName, 'Only the script is for every hub');
            System.assertEquals(false, RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_COMMIT).ok, 'Nothing to update');
            insert new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/salesforce', Named_Credential__c = 'RLY_GitLab',
                Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/repository/branches/').reply(200, '{}'));
            Test.startTest();
            RlyPipelineFiles.Status s = RlyRouteController.getPipelineFiles();
            RlyPipelineFiles.UpdateResult r = RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_PULL_REQUEST);
            String unsupported;
            try {
                RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/salesforce',
                    Named_Credential__c = 'RLY_GitLab')).openPullRequest('a', 'main', 'Title');
            } catch (RlyGit.GitException e) {
                unsupported = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('GitLab', s.provider, 'GitLab hub');
            System.assertEquals('.gitlab-ci.yml', s.files[0].repoPath, 'GitLab\'s file first');
            System.assert(s.message.contains('isn\'t available for GitLab'), s.message);
            System.assert(!r.ok && r.message.contains('isn\'t available for GitLab'), r.message);
            System.assert(unsupported != null && unsupported.startsWith('Opening pull requests'), unsupported);
        }
    }

    @IsTest
    static void onlyAdminsUpdate() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlyPipelineFiles.Status s = RlyRouteController.getPipelineFiles();
            System.assert(!s.isAdmin, 'Not an admin');
            Boolean refused = false;
            try {
                RlyRouteController.updatePipelineFiles(RlyPipelineFiles.VIA_COMMIT);
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Updating needs the admin permission set');
        }
    }
}
