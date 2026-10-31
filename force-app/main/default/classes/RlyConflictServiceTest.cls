/**
 * @description Tests for resolving a release's conflicts with its target (RlyConflictService, RlyConflictRules,
 * RlyConflictResult and RlyReleasesController.resolveConflicts). Each test runs as an active System Administrator,
 * who raised the release, through System.runAs. Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyConflictServiceTest {

    private static final String SERVICE = 'force-app/main/default/classes/AccountService.cls';
    private static final String SERVICE_TEST = 'force-app/main/default/classes/AccountServiceTest.cls';

    // A release whose validation conflicts with sit, with its pull request open.
    private static RLY_Release__c conflicted() {
        RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Passed', Validation_Status__c = 'Failed',
            Validation_Result__c = RlyReleaseTestData.conflictResult());
        return rel;
    }

    private static Map<String, Object> resolution(String file, String choice, String content) {
        Map<String, Object> r = new Map<String, Object>{ 'file' => file, 'choice' => choice };
        if (content != null) {
            r.put('content', content);
        }
        return r;
    }

    private static String request(List<Object> resolutions) {
        return JSON.serialize(new Map<String, Object>{ 'resolutions' => resolutions });
    }

    private static Boolean refused(Id releaseId, String requestJson) {
        try {
            RlyReleasesController.resolveConflicts(releaseId, requestJson);
        } catch (AuraHandledException e) {
            return true;
        }
        return false;
    }

    @IsTest
    static void resolveCommitsTheChoicesAndChecksAgain() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = conflicted();
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.resolveConflicts(rel.Id, request(new List<Object>{
                resolution(SERVICE, 'edit', 'a\nb\nc\n'), resolution(SERVICE_TEST, 'theirs', 'ignored') }));
            Test.stopTest();
            String path = '.relay-inbox/' + rel.Name + '-resolve.json';
            System.assert(mock.callLog().contains('PUT callout:RLY_GitHub/repos/acme/release/contents/' + path), 'Committed: ' + mock.callLog());
            Map<String, Object> put = (Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor(path));
            System.assertEquals('feature/' + rel.Name.toLowerCase(), put.get('branch'), 'On the release branch');
            String committed = EncodingUtil.base64Decode(String.valueOf(put.get('content'))).toString();
            List<Object> resolutions = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(committed)).get('resolutions');
            System.assertEquals(2, resolutions.size(), 'One entry per file: ' + committed);
            System.assert(committed.contains('"choice":"edit"') && committed.contains('a\\nb\\nc\\n'), 'The edited text: ' + committed);
            System.assert(!committed.contains('ignored'), 'Content only goes with edit');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"resolve"'), 'Mode resolve');
            System.assertEquals('', ((Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches')))
                .get('inputs')).get('components'), 'No components for resolve');
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('validateMerged'), 'Validated merged again');
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Validating', saved.Status__c, 'Checking again');
            System.assertEquals('resolve', saved.Pending_Run__c, 'Waits for the resolve run');
            System.assertEquals('Pending', saved.Scan_Status__c, 'Scan again');
            System.assertEquals('Pending', saved.Validation_Status__c, 'Validation again');
            System.assertEquals(null, saved.Error_Message__c, 'No error');
            System.assert(d.canResolve, 'Whoever raised it can resolve');
            System.assert(d.running, 'Running');
        }
    }

    @IsTest
    static void resolveRefusesIncompleteOrBadChoices() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = conflicted();
            Map<String, Object> theirs = resolution(SERVICE_TEST, 'theirs', null);
            List<String> bad = new List<String>{
                request(new List<Object>{ resolution(SERVICE, 'mine', null) }),
                request(new List<Object>{ resolution(SERVICE, 'edit', 'a\n<<<<<<< mine\nb\n'), theirs }),
                request(new List<Object>{ resolution(SERVICE, 'edit', 'a\nb\n>>>>>>> sit\n'), theirs }),
                request(new List<Object>{ resolution(SERVICE, 'edit', ' '), theirs }),
                request(new List<Object>{ resolution(SERVICE, 'mine', null), resolution(SERVICE_TEST, 'edit', 'y') }),
                request(new List<Object>{ resolution(SERVICE, 'both', null), theirs }),
                request(new List<Object>{ resolution(SERVICE, 'mine', null), theirs, resolution('classes/Other.cls', 'mine', null) }),
                request(new List<Object>{ resolution(SERVICE, 'mine', null), theirs, resolution(SERVICE, 'theirs', null) }),
                'not json'
            };
            Integer count = 0;
            for (String requestJson : bad) {
                count += refused(rel.Id, requestJson) ? 1 : 0;
            }
            System.assertEquals(bad.size(), count, 'Missing file, markers left, empty edit, truncated edit, bad choice, '
                + 'unknown or repeated file and bad JSON are refused before any callout');
            System.assertEquals('Checks failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Nothing changed');
        }
    }

    @IsTest
    static void resolveNeedsAnOpenConflict() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = conflicted();
            String ok = request(new List<Object>{ resolution(SERVICE, 'mine', null), resolution(SERVICE_TEST, 'theirs', null) });
            Integer count = 0;
            update new RLY_Release__c(Id = rel.Id, Status__c = 'Ready for approval');
            count += refused(rel.Id, ok) ? 1 : 0;
            update new RLY_Release__c(Id = rel.Id, Status__c = 'Checks failed', PR_Number__c = null);
            count += refused(rel.Id, ok) ? 1 : 0;
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42,
                Validation_Result__c = RlyReleaseTestData.result('validate', '"status":"Failed","message":"1 test failure(s)"'));
            count += refused(rel.Id, ok) ? 1 : 0;
            count += refused(null, ok) ? 1 : 0;
            System.assertEquals(4, count, 'Wrong status, no pull request, no conflict and no release are refused');
        }
    }

    @IsTest
    static void longConflictsFitTheField() {
        System.runAs(RlyTestData.admin()) {
            List<Object> files = new List<Object>();
            String text = 'x'.repeat(15000);
            for (Integer n = 0; n < 6; n++) {
                files.add(new Map<String, Object>{ 'file' => 'classes/C' + n + '.cls', 'merged' => text, 'mine' => text, 'theirs' => text });
            }
            Map<String, Object> result = new Map<String, Object>{ 'status' => 'Conflict', 'conflicts' => files };
            String fitted = RlyConflictResult.fit(result);
            System.assert(fitted.length() <= RlyConflictResult.MAX_LENGTH, 'Fits: ' + fitted.length());
            Map<String, Map<String, Object>> byFile = RlyConflictResult.filesOf(fitted);
            System.assertEquals(6, byFile.size(), 'Still valid JSON with every file');
            System.assertEquals(true, byFile.get('classes/C0.cls').get('truncated'), 'Shortened files are marked');
            String small = RlyConflictResult.fit(new Map<String, Object>{ 'status' => 'Passed' });
            System.assertEquals('{"status":"Passed"}', small, 'A normal result is kept as it is');
            System.assert(RlyConflictResult.filesOf('not json').isEmpty(), 'Unreadable results have no files');
        }
    }
}
