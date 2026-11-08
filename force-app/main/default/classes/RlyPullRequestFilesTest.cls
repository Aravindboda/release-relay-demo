/**
 * @description Tests for RlyPullRequestFiles: a pull request's files a page at a time without patches, a file's patch
 * when it's opened (cut when long), files without a preview, releases without a pull request, other providers and errors. Every test runs as an active
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
        for (Integer i = 0; i < RlyPullRequestFiles.PAGE_SIZE; i++) {
            rows.add(fileJson('force-app/main/default/classes/C' + pageNo + '_' + i + '.cls', 'modified', '@@ -1 +1 @@\n-a\n+b'));
        }
        return '[' + String.join(rows, ',') + ']';
    }

    @IsTest
    static void listsFilesWithoutTheirPatches() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            String page = '[' + fileJson(CLASS_PATH, 'modified', '@@ -1,2 +1,3 @@\n a\n-b\n+B\n+C') + ','
                + fileJson('force-app/main/default/staticresources/logo.png', 'added', null) + ','
                + fileJson('force-app/main/default/classes/AccountHelper.cls', 'renamed', '@@ -1 +1 @@\n-x\n+y') + ']';
            RlyHttpMock mock = new RlyHttpMock().match('GET', '/pulls/42/files?per_page=30&page=1').reply(200, page);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assert(c.available, 'Listed: ' + c.message);
            System.assertEquals(3, c.files.size(), 'Three files');
            System.assertEquals(6, c.additions, 'Lines added');
            System.assertEquals(3, c.deletions, 'Lines removed');
            System.assertEquals(null, c.nextPage, 'One page');
            System.assertEquals('GitHub', c.provider, 'Provider');
            System.assertEquals('SIT', c.targetName, 'Target org');
            System.assertEquals('DEV1', c.sourceName, 'Source org');
            System.assertEquals(PR_URL + '/files', c.filesUrl, 'Files view');
            String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(CLASS_PATH)));
            System.assertEquals(PR_URL + '/files#diff-' + hash, c.files[0].url, 'File anchor');
            System.assertEquals(true, c.files[0].hasPatch, 'Has a preview');
            System.assertEquals(null, c.files[0].patch, 'The patch isn\'t sent with the list');
            System.assertEquals(1, c.files[0].pageNo, 'Its page, to read the patch');
            System.assertEquals('No preview: open in GitHub.', c.files[1].note, 'Binary file');
            System.assertEquals('force-app/main/default/classes/OldService.cls', c.files[2].previousFilename, 'Renamed from');
            System.assertEquals(1, mock.calls.size(), 'One call');
        }
    }

    @IsTest
    static void bigPullRequestsComeAPageAtATime() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '&page=1').reply(200, fullPage(1))
                .match('GET', '&page=2').reply(200, '[' + fileJson('force-app/main/default/classes/Last.cls', 'added', '@@ +1 @@\n+a') + ']')
                .match('GET', '/pulls/42').reply(200, '{"number":42,"changed_files":3412,"additions":900,"deletions":40}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes first = RlyPullRequestFiles.files(rel.Id);
            RlyPullRequestFiles.Changes second = RlyPullRequestFiles.filesPage(rel.Id, first.nextPage);
            String refused;
            try {
                RlyPullRequestFiles.filesPage(rel.Id, 0);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(RlyPullRequestFiles.PAGE_SIZE, first.files.size(), 'A full page');
            System.assertEquals(2, first.nextPage, 'Then page 2');
            System.assertEquals(3412, first.totalFiles, 'Files in all');
            System.assertEquals(900, first.additions, 'The pull request\'s totals');
            System.assert(first.truncated, 'More than GitHub lists');
            System.assertEquals(1, second.files.size(), 'The last page');
            System.assertEquals(null, second.nextPage, 'Nothing after it');
            System.assertEquals(2, second.files[0].pageNo, 'Page kept');
            System.assert(refused != null && refused.contains('Pages go from 1'), 'Page checked: ' + refused);
        }
    }

    @IsTest
    static void aFilePatchIsReadWhenOpened() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withPullRequest();
            String big = '@@ -1 +1,3000 @@\n' + '+a line of code that is long enough\n'.repeat(1000);
            String page = '[' + fileJson(CLASS_PATH, 'modified', '@@ -1 +1 @@\n-b\n+B') + ','
                + fileJson('force-app/main/default/classes/Big.cls', 'modified', big) + ']';
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/pulls/42/files?per_page=30&page=1').reply(200, page));
            Test.startTest();
            RlyPullRequestFiles.FileChange small = RlyPullRequestFiles.filePatch(rel.Id, 1, CLASS_PATH);
            RlyPullRequestFiles.FileChange cut = RlyPullRequestFiles.filePatch(rel.Id, 1, 'force-app/main/default/classes/Big.cls');
            String gone;
            try {
                RlyPullRequestFiles.filePatch(rel.Id, 1, 'force-app/main/default/classes/Gone.cls');
            } catch (AuraHandledException e) {
                gone = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('@@ -1 +1 @@\n-b\n+B', small.patch, 'The whole patch');
            System.assertEquals(null, small.note, 'No note');
            System.assert(cut.patch.length() <= RlyPullRequestFiles.MAX_PATCH, 'Cut to the limit');
            System.assert(cut.patch.endsWith('enough'), 'Cut at a line end');
            System.assert(cut.note.contains('20,000') || cut.note.contains('20000'), 'Says it was cut: ' + cut.note);
            System.assert(gone != null && gone.contains('refresh'), 'A file no longer there says so: ' + gone);
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
            update new RLY_Git_Connection__c(Id = conn.Id, Provider__c = 'Bitbucket');
            RlyReleaseStore.forgetGit();
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            Test.stopTest();
            System.assertEquals(false, c.available, 'Not listed');
            System.assertEquals('Changes are shown for GitHub and GitLab only; open the pull request.', c.message, 'Message');
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
