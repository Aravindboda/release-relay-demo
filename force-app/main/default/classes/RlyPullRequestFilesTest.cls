/**
 * @description Tests for RlyPullRequestFiles: a pull request's files with patches, pages, files without a
 * preview, releases without a pull request, other providers and errors. Every test runs as an active
 * System Administrator through System.runAs.
 */
@IsTest
private class RlyPullRequestFilesTest {

    private static final String PR_URL = 'https://github.com/acme/release/pull/42';
    private static final String CLASS_PATH = 'force-app/main/default/classes/AccountService.cls';

    private static RLY_Release__c withPullRequest() {
        RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', null);
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, PR_URL__c = PR_URL);
        return rel;
    }

    private static String fileJson(String filename, String status, String patch) {
        Map<String, Object> f = new Map<String, Object>{ 'filename' => filename, 'status' => status, 'additions' => 2, 'deletions' => 1 };
        if (patch != null) {
            f.put('patch', patch);
        }
        if (status == 'renamed') {
            f.put('previous_filename', 'force-app/main/default/classes/OldService.cls');
        }
        return JSON.serialize(f);
    }

    private static String fullPage(Integer pageNo) {
        List<String> rows = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            rows.add(fileJson('force-app/main/default/classes/C' + pageNo + '_' + i + '.cls', 'modified', '@@ -1 +1 @@\n-a\n+b'));
        }
        return '[' + String.join(rows, ',') + ']';
    }

    @IsTest
    static void listsFilesWithPatches() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            String page = '[' + fileJson(CLASS_PATH, 'modified', '@@ -1,2 +1,3 @@\n a\n-b\n+B\n+C') + ','
                + fileJson('force-app/main/default/staticresources/logo.png', 'added', null) + ','
                + fileJson('force-app/main/default/classes/AccountHelper.cls', 'renamed', '@@ -1 +1 @@\n-x\n+y') + ']';
            RlyHttpMock mock = new RlyHttpMock().match('GET', '/pulls/42/files?per_page=100&page=1').reply(200, page);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assert(c.available, 'Listed: ' + c.message);
            System.assertEquals(3, c.files.size(), 'Three files');
            System.assertEquals(6, c.additions, 'Lines added');
            System.assertEquals(3, c.deletions, 'Lines removed');
            System.assertEquals(false, c.truncated, 'All files read');
            System.assertEquals('GitHub', c.provider, 'Provider');
            System.assertEquals('SIT', c.targetName, 'Target org');
            System.assertEquals('DEV1', c.sourceName, 'Source org');
            System.assertEquals(PR_URL + '/files', c.filesUrl, 'Files view');
            String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(CLASS_PATH)));
            System.assertEquals(PR_URL + '/files#diff-' + hash, c.files[0].url, 'File anchor');
            System.assertEquals(null, c.files[0].note, 'Has a preview');
            System.assertEquals('No preview: open in GitHub.', c.files[1].note, 'Binary file');
            System.assertEquals('force-app/main/default/classes/OldService.cls', c.files[2].previousFilename, 'Renamed from');
            System.assertEquals(1, mock.calls.size(), 'One page');
        }
    }

    @IsTest
    static void readsUpToThreePages() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '&page=1').reply(200, fullPage(1))
                .match('GET', '&page=2').reply(200, fullPage(2))
                .match('GET', '&page=3').reply(200, fullPage(3))
                .match('GET', '/pulls/42').reply(200, '{"number":42,"changed_files":412}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assertEquals(300, c.files.size(), 'Three pages');
            System.assert(c.truncated, 'More than 300 files');
            System.assertEquals(412, c.totalFiles, 'Files in all');
            System.assertEquals(4, mock.calls.size(), 'Three pages and the pull request');
        }
    }

    @IsTest
    static void noPullRequestYet() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', 'hub');
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assertEquals(false, c.available, 'Nothing to list');
            System.assertEquals('This release has no pull request yet.', c.message, 'Message');
            System.assert(mock.calls.isEmpty(), 'No callouts');
        }
    }

    @IsTest
    static void otherProvidersGetAMessage() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            update new RLY_Git_Connection__c(Id = conn.Id, Provider__c = 'GitLab');
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assertEquals(false, c.available, 'Not listed');
            System.assertEquals('Changes are shown for GitHub only; open the pull request.', c.message, 'Message');
            System.assert(mock.calls.isEmpty(), 'No callouts');
        }
    }

    @IsTest
    static void providerErrorIsShown() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/pulls/42/files').reply(500, '{"message":"Server error"}'));
            Test.startTest();
            String message;
            try {
                RlyPullRequestFiles.files(rel.Id);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();
            System.assertNotEquals(null, message, 'The error reaches the page');
        }
    }

    @IsTest
    static void unknownReleaseIsRefused() {
        System.runAs(RlyTestData.admin()) {
            Id missing = Id.valueOf(RlyTestData.fakeId(RLY_Release__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix(), 7));
            Test.startTest();
            String message;
            try {
                RlyPullRequestFiles.files(missing);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('Release not found.', message, 'Refused');
        }
    }
}
