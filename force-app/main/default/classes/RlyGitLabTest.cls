/**
 * @description Tests for the GitLab provider (build 45): RlyGitLab's files, pipelines and merge requests, RlyGitLabRuns,
 * RlyGitLabTree (and RlyGitTreeReader on GitLab), RlyGitLabDiffs (and RlyPullRequestFiles on GitLab), and the GitLab
 * advice in RlyGitAdvice. Every GitLab call is answered by RlyHttpMock. Every test runs as an active System
 * Administrator through System.runAs.
 */
@IsTest
private class RlyGitLabTest {

    private static final String WEB = 'https://gitlab.com/acme/salesforce';
    private static final String CLASS_PATH = 'force-app/main/default/classes/AccountService.cls';

    private static RLY_Git_Connection__c conn(String repository) {
        return new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = repository, Named_Credential__c = 'RLY_GitLab',
            Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default');
    }

    private static RlyGit gitLab() {
        return RlyGit.forConnection(conn('acme/salesforce'));
    }

    // A page of tree entries: n files under a folder.
    private static String blobs(String folder, Integer n) {
        List<Object> rows = new List<Object>();
        for (Integer i = 0; i < n; i++) {
            rows.add(new Map<String, Object>{ 'id' => 'b' + i, 'name' => 'C' + i + '.cls', 'type' => 'blob', 'path' => folder + '/C' + i + '.cls' });
        }
        return JSON.serialize(rows);
    }

    private static String diff(String path, String flag, String patch) {
        Map<String, Object> d = new Map<String, Object>{ 'old_path' => path, 'new_path' => path, 'diff' => patch,
            'new_file' => flag == 'new', 'deleted_file' => flag == 'deleted', 'renamed_file' => flag == 'renamed' };
        if (flag == 'renamed') {
            d.put('old_path', 'force-app/main/default/classes/OldService.cls');
        }
        return JSON.serialize(d);
    }

    @IsTest
    static void aMovedBranchIsSentAgain() {
        System.runAs(RlyTestData.admin()) {
            HttpResponse moved = new HttpResponse();
            moved.setStatusCode(400);
            moved.setBody('{"message":"9:reference update: reference does not point to expected object."}');
            HttpResponse other = new HttpResponse();
            other.setStatusCode(400);
            other.setBody('{"message":"A file with this name already exists"}');
            HttpResponse clash = new HttpResponse();
            clash.setStatusCode(409);
            clash.setBody('');
            System.assert(RlyGitCore.branchMoved(moved), 'GitLab\'s 400 for a moved branch is sent again (D46)');
            System.assert(RlyGitCore.branchMoved(clash), 'A 409 is sent again');
            System.assert(!RlyGitCore.branchMoved(other), 'Another 400 is not');
            System.assert(!RlyGitCore.branchMoved(null), 'No answer is not');
        }
    }

    @IsTest
    static void filesAreCommittedReadAndListed() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/repository/files/scripts%2Fnew.js?ref=main').reply(404, '')
                .match('GET', '/repository/files/.gitlab-ci.yml?ref=main').reply(200, '{"file_name":".gitlab-ci.yml"}')
                .match('POST', '/projects/acme/salesforce/repository/commits').reply(201, '{"id":"c1","web_url":"' + WEB + '/-/commit/c1"}')
                .match('GET', '/repository/files/.relay/values.json/raw?ref=main').reply(200, '{"values":{}}')
                .match('GET', 'tree?ref=sit&path=force-app&recursive=true&per_page=100&page=1').reply(200, blobs('force-app/classes', 100))
                .match('GET', 'tree?ref=sit&path=force-app&recursive=true&per_page=100&page=2').reply(200, blobs('force-app/lwc', 1))
                .match('GET', 'tree?ref=big').reply(200, blobs('x', 100));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyGit git = gitLab();
            String created = git.putFile(new RlyGitFile('scripts/new.js', 'main').withContent('YQ==', 'Add'));
            String createBody = mock.bodyFor('/repository/commits');
            String updated = git.putFile(new RlyGitFile('.gitlab-ci.yml', 'main').withContent('Yg==', 'Update'));
            String updateBody = mock.bodyFor('/repository/commits');
            String values = git.getFileRaw('.relay/values.json', 'main');
            String missing = git.getFileRaw('nope.txt', 'main');
            List<String> files = git.listFiles('sit', 'force-app/');
            String tooMany;
            try {
                git.listFiles('big', '');
            } catch (RlyGit.GitException e) {
                tooMany = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(WEB + '/-/commit/c1', created, 'Commit link');
            System.assert(createBody.contains('"action":"create"') && createBody.contains('"encoding":"base64"'), createBody);
            System.assert(updateBody.contains('"action":"update"') && updateBody.contains('"commit_message":"Update"'), updateBody);
            System.assertNotEquals(null, updated, 'Updated');
            System.assertEquals('{"values":{}}', values, 'Raw content');
            System.assertEquals(null, missing, 'A missing file is null');
            System.assertEquals(101, files.size(), 'Both pages');
            System.assertEquals('force-app/classes/C0.cls', files[0], 'Paths from the root');
            System.assert(tooMany != null && tooMany.contains('stopped at'), 'A folder too big is refused: ' + tooMany);
        }
    }

    @IsTest
    static void pipelinesStartAndAreFound() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/projects/acme/salesforce/pipeline').reply(201, '{"id":10}')
                .match('GET', '/acme/salesforce/pipelines?ref=main&source=api').reply(200, '[{"id":11,"status":"running","web_url":"u11",'
                    + '"name":"Release Relay REL-00002 (hub) · REL-00002: Other"},{"id":10,"status":"success","web_url":"u10",'
                    + '"name":"Release Relay REL-00001 (hub) · REL-00001: Region"},{"id":9,"status":"canceled","web_url":"u9",'
                    + '"name":"Release Relay REL-00001 (check)"}]')
                .match('GET', '/acme/older/pipelines?ref=main').reply(200, '[{"id":21,"status":"pending"},{"id":20,"status":"failed"}]')
                .match('GET', '/acme/older/pipelines/21/variables').reply(200, '[{"key":"REQUEST_ID","value":"REL-00004"},{"key":"MODE","value":"hub"}]')
                .match('GET', '/acme/older/pipelines/20/variables').reply(200, '[{"key":"REQUEST_ID","value":"REL-00003"},{"key":"MODE","value":"check"},'
                    + '{"key":"TITLE","value":"REL-00003: Fix"}]')
                .match('GET', '/acme/older/pipelines/21').reply(200, '{"id":21,"status":"pending","web_url":"u21"}')
                .match('GET', '/acme/older/pipelines/20').reply(200, '{"id":20,"status":"failed","web_url":"u20"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            gitLab().startPipeline(new Map<String, String>{ 'request_id' => 'REL-00001', 'mode' => 'hub', 'target_environment' => '',
                'options' => '{"hub":true}' });
            String started = mock.bodyFor('/pipeline');
            RlyGit.Run hub = gitLab().findRun('Release Relay REL-00001 (hub)');
            RlyGit.Run check = gitLab().findRun('Release Relay REL-00001 (check)');
            RlyGit.Run other = gitLab().findRun('Release Relay REL-00002 (hub)');
            RlyGit.Run none = gitLab().findRun('Release Relay REL-09999 (hub)');
            RlyGit.Run older = RlyGit.forConnection(conn('acme/older')).findRun('Release Relay REL-00003 (check)');
            Test.stopTest();
            System.assert(started.contains('"ref":"main"') && started.contains('"key":"REQUEST_ID"') && started.contains('"key":"OPTIONS"'), started);
            System.assert(!started.contains('TARGET_ENVIRONMENT'), 'Blank inputs are left out: ' + started);
            System.assertEquals('10', hub.id, 'Matched by name, title added');
            System.assert(hub.completed() && !hub.failed(), 'Succeeded');
            System.assertEquals('cancelled', check.conclusion, 'Cancelled');
            System.assertEquals('in_progress', other.status, 'Running');
            System.assertEquals(null, none, 'No such run');
            System.assertEquals('u20', older.url, 'Named from its variables');
            System.assertEquals('failure', older.conclusion, 'Failed');
        }
    }

    @IsTest
    static void mergeRequestsStandForPullRequests() {
        System.runAs(RlyTestData.admin()) {
            String diffs = '[' + diff(CLASS_PATH, 'renamed', '@@ -1,2 +1,3 @@\n a\n-b\n+B\n+C') + ','
                + diff('force-app/main/default/staticresources/logo.png', 'new', '') + ','
                + diff('force-app/main/default/classes/Old.cls', 'deleted', '@@ -1 +0,0 @@\n-x') + ','
                + diff('force-app/main/default/classes/Same.cls', 'none', '@@ -1 +1 @@\n-y\n+z') + ']';
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', 'source_branch=feature/rel-00001').reply(200, '[{"iid":7,"web_url":"' + WEB + '/-/merge_requests/7","state":"merged"}]')
                .match('GET', 'source_branch=feature/rel-00002').reply(200, '[{"iid":8,"web_url":"' + WEB + '/-/merge_requests/8","state":"opened"}]')
                .match('GET', 'source_branch=feature/none').reply(200, '[]')
                .match('POST', '/merge_requests/7/notes').reply(201, '{}')
                .match('POST', '/merge_requests').reply(201, '{"iid":9,"web_url":"' + WEB + '/-/merge_requests/9"}')
                .match('PUT', '/merge_requests/7').reply(200, '{"state":"closed"}')
                .match('GET', '/merge_requests/7/diffs?per_page=30&page=1').reply(200, diffs)
                .match('GET', '/merge_requests/7').reply(200, '{"iid":7,"changes_count":"1000+"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyGit git = gitLab();
            RlyGitChanges changes = RlyGitChanges.of(git);
            RlyGit.PullRequest merged = git.findPullRequest('feature/rel-00001', 'sit');
            RlyGit.PullRequest open = git.findPullRequest('feature/rel-00002', 'sit');
            RlyGit.PullRequest none = git.findPullRequest('feature/none', 'sit');
            String opened = git.openPullRequest('release-relay/pipeline-files-v25', 'main', 'Pipeline files v25\n\nUpdates them.');
            String openBody = mock.bodyFor('/merge_requests');
            git.commentOnPullRequest(7, 'Rejected: wrong org');
            git.closePullRequest(7);
            List<Object> files = changes.page(7, 1, 30);
            Map<String, Object> totals = changes.totals(7, 3, 2);
            Test.stopTest();
            System.assertEquals(7, merged.prNumber, 'iid');
            System.assertEquals('merged', merged.state, 'Merged');
            System.assertEquals('open', open.state, 'Opened is open');
            System.assertEquals(null, none, 'None');
            System.assertEquals(WEB + '/-/merge_requests/9', opened, 'Link');
            System.assert(openBody.contains('"title":"Pipeline files v25"') && openBody.contains('"description":"Updates them."'), openBody);
            System.assert(mock.callLog().contains('PUT callout:RLY_GitLab/projects/acme/salesforce/merge_requests/7'), mock.callLog());
            System.assertEquals(4, files.size(), 'Four files');
            Map<String, Object> renamed = (Map<String, Object>) files[0];
            System.assertEquals('renamed', renamed.get('status'), 'Renamed');
            System.assertEquals('force-app/main/default/classes/OldService.cls', renamed.get('previous_filename'), 'Old path');
            System.assertEquals(2, renamed.get('additions'), 'Lines added');
            System.assertEquals(1, renamed.get('deletions'), 'Lines removed');
            System.assertEquals('added', ((Map<String, Object>) files[1]).get('status'), 'New');
            System.assertEquals(false, ((Map<String, Object>) files[1]).containsKey('patch'), 'No preview');
            System.assertEquals('removed', ((Map<String, Object>) files[2]).get('status'), 'Deleted');
            System.assertEquals('modified', ((Map<String, Object>) files[3]).get('status'), 'Changed');
            System.assertEquals(1000, totals.get('changed_files'), 'Counted files');
            System.assertEquals(3, totals.get('additions'), 'The page\'s lines stay');
        }
    }

    @IsTest
    static void namesAndLinks() {
        System.runAs(RlyTestData.admin()) {
            RlyGit git = gitLab();
            RlyGitChanges changes = RlyGitChanges.of(git);
            System.assertEquals('Merge request', git.changeRequestLabel(), 'GitLab\'s word');
            System.assertEquals(WEB, git.webUrl(), 'Project link');
            System.assertEquals(WEB + '/-/tree/feature/rel-00001', git.branchUrl('feature/rel-00001'), 'Branch link');
            System.assertEquals(WEB, git.branchUrl(''), 'No branch: the project');
            System.assertEquals(WEB + '/-/merge_requests/7/diffs', changes.filesUrl(WEB + '/-/merge_requests/7/'), 'Changes view');
            System.assertEquals(null, changes.filesUrl(' '), 'No link');
            System.assertEquals(null, changes.fileUrl(null, CLASS_PATH), 'No Changes view');
            System.assertEquals(41, changes.fileUrl('', CLASS_PATH).length(), 'SHA-1 anchor');
            System.assertEquals(new List<String>{ '.gitlab-ci.yml', 'scripts/release-relay.js' }, git.pipelineFiles(), 'Pipeline files');
        }
    }

    @IsTest
    static void treeReaderReadsFoldersByPath() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', 'tree?ref=dev1&path=force-app/main/default/classes&recursive=true').reply(200, blobs('force-app/main/default/classes', 2))
                .match('GET', 'tree?ref=dev1&path=force-app/main/default&per_page').reply(200,
                    '[{"id":"t2","name":"classes","type":"tree","path":"force-app/main/default/classes"}]')
                .match('GET', 'tree?ref=dev1&per_page').reply(200, '[{"id":"t1","name":"force-app","type":"tree","path":"force-app"},'
                    + '{"id":"b1","name":"README.md","type":"blob","path":"README.md"},{"id":"x","type":"blob"}]');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyGitTreeReader reader = new RlyGitTreeReader(conn('acme/salesforce'));
            RlyGitTree.Tree root = reader.own('dev1');
            RlyGitTree.Tree folder = reader.own(RlyGitLabTree.folderRef('dev1', 'force-app/main/default'));
            RlyGitTree.Tree classes = reader.below(folder.entries[0].sha);
            RlyGitTree.Tree gone = reader.own('gone');
            Test.stopTest();
            System.assertEquals(2, root.entries.size(), 'Entries with a path');
            System.assertEquals('force-app', root.entries[0].path, 'Folder name');
            System.assertEquals('dev1:force-app', root.entries[0].sha, 'Folder reference');
            System.assertEquals('b1', root.entries[1].sha, 'File id');
            System.assertEquals('classes', folder.entries[0].path, 'Relative to the folder');
            System.assertEquals(2, classes.entries.size(), 'Every file below');
            System.assertEquals('C0.cls', classes.entries[0].path, 'Relative to the folder read');
            System.assertEquals(false, classes.truncated, 'Whole');
            System.assert(gone.entries.isEmpty(), 'A missing branch is empty');
            System.assert(RlyGitTreeReader.isTreeRef('dev1:force-app/main/default'), 'Folder reference');
            System.assert(RlyGitTreeReader.isTreeRef('0123456789abcdef0123456789abcdef01234567'), 'Tree sha');
            System.assert(!RlyGitTreeReader.isTreeRef('dev1:../secret'), 'No climbing out');
            System.assert(!RlyGitTreeReader.isTreeRef('dev1:/etc'), 'No absolute path');
            System.assert(!RlyGitTreeReader.isTreeRef(null), 'Nothing');
            System.assertEquals('', RlyGitLabTree.pathOf('dev1'), 'A branch is its root');
            System.assertEquals(true, RlyGitLabTree.isLastPage(100, ''), 'Empty X-Next-Page');
            System.assertEquals(false, RlyGitLabTree.isLastPage(3, '2'), 'X-Next-Page set');
        }
    }

    @IsTest
    static void changesCardListsMergeRequestFiles() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', null);
            String mrUrl = 'https://gitlab.com/acme/release/-/merge_requests/42';
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, PR_URL__c = mrUrl);
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Provider__c = 'GitLab');
            RlyReleaseStore.forgetGit();
            List<String> page = new List<String>();
            for (Integer i = 0; i < RlyPullRequestFiles.PAGE_SIZE; i++) {
                page.add(diff(i == 0 ? CLASS_PATH : 'force-app/main/default/classes/C' + i + '.cls', 'none', '@@ -1 +1 @@\n-a\n+b'));
            }
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/merge_requests/42/diffs?per_page=30&page=1').reply(200, '[' + String.join(page, ',') + ']')
                .match('GET', '/merge_requests/42').reply(200, '{"iid":42,"changes_count":"45"}'));
            Test.startTest();
            RlyPullRequestFiles.Changes c = RlyPullRequestFiles.files(rel.Id);
            RlyPullRequestFiles.FileChange opened = RlyPullRequestFiles.filePatch(rel.Id, 1, CLASS_PATH);
            Test.stopTest();
            System.assert(c.available, 'Listed: ' + c.message);
            System.assertEquals('GitLab', c.provider, 'Provider');
            System.assertEquals(mrUrl + '/diffs', c.filesUrl, 'Changes view');
            String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(CLASS_PATH)));
            System.assertEquals(mrUrl + '/diffs#' + hash, c.files[0].url, 'GitLab\'s anchor');
            System.assertEquals(45, c.totalFiles, 'Total from changes_count');
            System.assertEquals(30, c.additions, 'Lines counted on the page');
            System.assertEquals(2, c.nextPage, 'More pages');
            System.assertEquals('@@ -1 +1 @@\n-a\n+b', opened.patch, 'Patch when opened');
        }
    }

    @IsTest
    static void gitLabSettingsGetAdvice() {
        System.runAs(RlyTestData.admin()) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('POST', '/pipeline').reply(400, '{"message":{"base":["Insufficient permissions to set pipeline variables"]}}')
                .match('GET', '/repository/branches/main').reply(403, '{"error":"insufficient_scope"}'));
            Test.startTest();
            List<String> messages = new List<String>();
            try {
                gitLab().startPipeline(new Map<String, String>{ 'mode' => 'check' });
            } catch (RlyGit.GitException e) {
                messages.add(e.getMessage());
            }
            try {
                gitLab().branchHead('main');
            } catch (RlyGit.GitException e) {
                messages.add(e.getMessage());
            }
            Test.stopTest();
            System.assertEquals(2, messages.size(), 'Both refused: ' + messages);
            System.assert(messages[0].contains('Minimum role to use pipeline variables'), messages[0]);
            System.assert(messages[1].contains('api and write_repository'), messages[1]);
            System.assertEquals('queued', RlyGitLabRuns.toRun(new Map<String, Object>{ 'id' => 1, 'status' => 'odd' }).status, 'Unknown status');
            System.assertEquals('weird', RlyGitLabRuns.mergeRequestState('weird'), 'Unknown state kept');
            System.assertEquals(null, RlyGitLabRuns.textOf('not json', 'web_url'), 'Not JSON');
            System.assertEquals(null, RlyGitLabRuns.nameFromVariables(null), 'No variables');
            System.assertEquals(0, RlyGitLabDiffs.changesCount(null), 'No count');
        }
    }
}
