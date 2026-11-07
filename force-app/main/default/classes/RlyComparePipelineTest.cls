/**
 * @description Tests for Compare in the pipeline (RlyComparePipeline, RlyComparePipelineResult and their
 * RlyCompareController methods). DEV1's Metadata API and GitHub answer through RlyHttpMock; nothing depends on org data.
 * Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyComparePipelineTest {

    private static final String SOAP_HEAD = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope '
        + 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
    private static final String SOAP_TAIL = '</soapenv:Body></soapenv:Envelope>';
    private static final String RETRIEVE_ID = RlyTestData.fakeId('09S', 9);
    private static final String COMPARE_ID = 'CMP-1762400000000';
    private static final String TOKEN = 'a1b2c3';
    private static final String ZIP = EncodingUtil.base64Encode(Blob.valueOf('zip-bytes'));
    private static final String SUMMARY = 'results/' + COMPARE_ID + '/compare.json';

    private static RlyHttpMock retrieveMock(Boolean done) {
        String status = done
            ? '<checkRetrieveStatusResponse><result><done>true</done><id>' + RETRIEVE_ID + '</id><status>Succeeded</status>'
                + '<success>true</success><zipFile>' + ZIP + '</zipFile></result></checkRetrieveStatusResponse>'
            : '<checkRetrieveStatusResponse><result><done>false</done><id>' + RETRIEVE_ID + '</id><status>InProgress</status></result></checkRetrieveStatusResponse>';
        return new RlyHttpMock()
            .match('POST', '/services/Soap/m/').ifBodyHas('<met:retrieve>').reply(200, SOAP_HEAD + '<retrieveResponse><result><done>false</done><id>'
                + RETRIEVE_ID + '</id><state>Queued</state></result></retrieveResponse>' + SOAP_TAIL)
            .match('POST', '/services/Soap/m/').reply(200, SOAP_HEAD + status + SOAP_TAIL)
            .match('PUT', '/contents/compare-inbox/').reply(201, '{"commit":{"html_url":"https://github.com/acme/release/commit/1"}}')
            .match('POST', '/dispatches').reply(204, '');
    }

    private static String summaryJson(String attempt, String status) {
        return JSON.serialize(new Map<String, Object>{
            'request' => COMPARE_ID, 'step' => 'compare', 'status' => status, 'attempt' => attempt, 'message' => 'Part 1 is broken.',
            'runUrl' => 'https://github.com/acme/release/actions/runs/7',
            'components' => new List<Object>{
                new Map<String, Object>{ 'key' => 'ApexClass:A', 'status' => 'changed', 'files' => new List<Object>{
                    new Map<String, Object>{ 'path' => 'force-app/main/default/classes/A.cls', 'status' => 'changed', 'n' => 1, 'kind' => 'text' },
                    new Map<String, Object>{ 'path' => 'force-app/main/default/staticresources/logo.resource', 'status' => 'changed',
                        'reason' => 'Binary file: open it in GitHub.' } } },
                new Map<String, Object>{ 'key' => 'ApexClass:Z', 'status' => 'missing', 'reason' => 'Not in DEV1\'s copy.', 'files' => new List<Object>() },
                new Map<String, Object>{ 'key' => 'ApexClass:C', 'status' => 'deleted', 'files' => new List<Object>() }
            }
        });
    }

    private static Map<String, Object> runJob(Id devId) {
        return new Map<String, Object>{ 'compareId' => COMPARE_ID, 'sourceOrgId' => devId, 'targetBranch' => 'sit',
            'keys' => new List<String>{ 'ApexClass:A', 'CustomObject:Order__c' }, 'deleted' => new List<String>{ 'ApexClass:C' }, 'parts' => 1 };
    }

    @IsTest
    static void partRetrievesEveryTypeAndCommitsItsZip() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock m = retrieveMock(true);
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            String id = RlyCompareController.startPipelinePart(dev.Id, new List<String>{ 'ApexClass:A', 'CustomObject:Order__c' });
            String retrieveBody = m.bodyFor('/services/Soap/m/');
            RlyComparePipeline.PartState st = RlyCompareController.stagePipelinePart(JSON.serialize(new Map<String, Object>{
                'compareId' => COMPARE_ID, 'n' => 1, 'retrieveId' => id, 'sourceOrgId' => dev.Id }));
            Test.stopTest();
            System.assertEquals(RETRIEVE_ID, id, 'The part\'s retrieve id comes back');
            System.assert(retrieveBody.contains('Order__c') && retrieveBody.contains('CustomObject'),
                'Types the hub can\'t show are retrieved too');
            System.assertEquals(true, st.done, 'The zip is on the results branch');
            String put = m.bodyFor('/contents/compare-inbox/' + COMPARE_ID + '/1.zip');
            System.assert(put != null && put.contains(ZIP) && put.contains('release-relay-results'), 'The zip goes as the org sent it, on the results branch');
        }
    }

    @IsTest
    static void partWaitsForItsRetrieve() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock m = retrieveMock(false);
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyComparePipeline.PartState st = RlyCompareController.stagePipelinePart(JSON.serialize(new Map<String, Object>{
                'compareId' => COMPARE_ID, 'n' => 2, 'retrieveId' => RETRIEVE_ID, 'sourceOrgId' => dev.Id }));
            Test.stopTest();
            System.assertEquals(false, st.done, 'Still retrieving');
            System.assertEquals(null, m.bodyFor('/contents/compare-inbox/'), 'Nothing committed yet');
        }
    }

    @IsTest
    static void runStartsTheComparePipeline() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyHttpMock m = retrieveMock(true);
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyComparePipeline.Started s = RlyCompareController.runPipelineCompare(JSON.serialize(runJob(dev.Id)));
            Test.stopTest();
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(m.bodyFor('/dispatches'));
            Map<String, Object> inputs = (Map<String, Object>) body.get('inputs');
            System.assertEquals('compare', inputs.get('mode'), 'Mode compare');
            System.assertEquals(COMPARE_ID, inputs.get('request_id'), 'The compare id is the request id');
            System.assertEquals('sit', inputs.get('target'), 'Compared with the first stage\'s branch');
            System.assertEquals('ApexClass:A,CustomObject:Order__c', inputs.get('components'), 'Every component goes');
            System.assertEquals('ApexClass:C', inputs.get('deletions'), 'Deletions go apart');
            Map<String, Object> options = (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(inputs.get('options')));
            System.assertEquals(s.token, options.get('attempt'), 'The result will echo the token');
            System.assertEquals(1, options.get('batches'), 'Parts sent');
            System.assertEquals('Release Relay ' + COMPARE_ID + ' (compare)', s.runTitle, 'Run title as the workflow names it');
            System.assertEquals('SIT', s.targetName, 'Target named');
        }
    }

    @IsTest
    static void runRefusesBadInput() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, retrieveMock(true));
            Map<String, Object> badId = runJob(dev.Id);
            badId.put('compareId', 'CMP-12');
            Map<String, Object> badKey = runJob(dev.Id);
            badKey.put('keys', new List<String>{ 'ApexClass:A,B' });
            Map<String, Object> noParts = runJob(dev.Id);
            noParts.put('parts', 0);
            Test.startTest();
            List<String> errors = new List<String>();
            for (Map<String, Object> j : new List<Map<String, Object>>{ badId, badKey, noParts }) {
                try {
                    RlyCompareController.runPipelineCompare(JSON.serialize(j));
                    errors.add('none');
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assert(errors[0].contains('CMP-'), 'Compare id checked: ' + errors[0]);
            System.assert(errors[1].contains('Type:Name'), 'Keys checked: ' + errors[1]);
            System.assert(errors[2].contains('every part'), 'Parts must be sent first: ' + errors[2]);
        }
    }

    @IsTest
    static void onlyGitHubRunsIt() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            conn.Provider__c = 'GitLab';
            update conn;
            String error;
            Test.startTest();
            try {
                RlyCompareController.runPipelineCompare(JSON.serialize(runJob(dev.Id)));
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(RlyComparePipeline.GITHUB_ONLY, error, 'GitLab has no compare job yet');
        }
    }

    @IsTest
    static void checkReadsTheResultOfThisRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', SUMMARY).reply(200, summaryJson(TOKEN, 'Succeeded')));
            Test.startTest();
            RlyComparePipelineResult.Result r = RlyCompareController.checkPipelineCompare(COMPARE_ID, TOKEN);
            Test.stopTest();
            System.assertEquals(true, r.done, 'Result read');
            System.assertEquals(false, r.failed, 'It succeeded');
            System.assertEquals(3, r.components.size(), 'Every component, in order');
            RlyCompareFiles.ComponentDiff a = r.components[0];
            System.assertEquals('changed', a.status, 'Status kept');
            System.assertEquals(1, a.files[0].n, 'The file\'s number, to open it later');
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, a.files[1].status, 'A file without text says why');
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, r.components[1].status, 'Missing reads as Not available');
            System.assertEquals('Not in DEV1\'s copy.', r.components[1].reason, 'With the pipeline\'s reason');
            System.assertEquals(true, r.components[2].deleted, 'Deletion flagged');
        }
    }

    @IsTest
    static void checkIgnoresAnEarlierRunAndWatchesTheRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', SUMMARY).reply(200, summaryJson('older', 'Succeeded'))
                .match('GET', '/runs?event=workflow_dispatch').reply(200, '{"workflow_runs":[{"id":7,"display_title":"Release Relay '
                    + COMPARE_ID + ' (compare)","html_url":"https://github.com/acme/release/actions/runs/7","status":"in_progress"}]}'));
            Test.startTest();
            RlyComparePipelineResult.Result r = RlyCompareController.checkPipelineCompare(COMPARE_ID, TOKEN);
            Test.stopTest();
            System.assertEquals(false, r.done, 'Another run\'s result isn\'t this one');
            System.assertEquals('in_progress', r.runStatus, 'The run is going');
            System.assertEquals('https://github.com/acme/release/actions/runs/7', r.runUrl, 'Linked to the run');
        }
    }

    @IsTest
    static void checkFailsWhenTheRunEndsWithoutResultOrSaysFailed() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/runs?event=workflow_dispatch').reply(200, '{"workflow_runs":[{"id":7,"display_title":"Release Relay '
                    + COMPARE_ID + ' (compare)","html_url":"https://x","status":"completed","conclusion":"failure"}]}'));
            Test.startTest();
            RlyComparePipelineResult.Result ended = RlyCompareController.checkPipelineCompare(COMPARE_ID, TOKEN);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', SUMMARY).reply(200, summaryJson(TOKEN, 'Failed')));
            RlyComparePipelineResult.Result failed = RlyCompareController.checkPipelineCompare(COMPARE_ID, TOKEN);
            Test.stopTest();
            System.assert(ended.done && ended.failed, 'A run that ended without a result fails the compare');
            System.assert(failed.done && failed.failed, 'A Failed result fails it');
            System.assertEquals('Part 1 is broken.', failed.message, 'With the pipeline\'s message');
        }
    }

    @IsTest
    static void fileReadsBothCopiesOrTheDiff() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + COMPARE_ID + '/f/1.json').reply(200, '{"path":"force-app/main/default/classes/A.cls","left":"a","right":"b"}')
                .match('GET', 'results/' + COMPARE_ID + '/f/2.json').reply(200, '{"path":"force-app/main/default/classes/D.cls","patch":"@@ -1 +1 @@\\n-a\\n+b"}'));
            Test.startTest();
            RlyCompareFiles.FileDiff text = RlyCompareController.pipelineCompareFile(COMPARE_ID, 1);
            RlyCompareFiles.FileDiff patch = RlyCompareController.pipelineCompareFile(COMPARE_ID, 2);
            String gone;
            try {
                RlyCompareController.pipelineCompareFile(COMPARE_ID, 3);
            } catch (AuraHandledException e) {
                gone = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('changed', text.status, 'Both copies, compared');
            System.assertEquals('b', text.right, 'Right copy');
            System.assert(patch.patch.startsWith('@@'), 'A large file comes as its diff');
            System.assertEquals('changed', patch.status, 'A diff means changed');
            System.assert(gone != null && gone.contains('compare again'), 'A pruned file says so: ' + gone);
        }
    }
}
