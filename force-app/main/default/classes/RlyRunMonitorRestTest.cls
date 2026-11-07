/**
 * @description Tests for the pipeline run endpoint (RlyRunMonitorRest, RlyRunMonitorInbound, RlyRunMonitorInput): a
 * start then an end upsert one row by run id and attempt, a late start never sets a finished run back, a release is
 * found by its number, bad bodies are refused (400), values in the wrong format are skipped with warnings, unknown keys
 * are ignored and a caller without Release Relay Admin is refused (403). Each test runs through System.runAs as the
 * active System Administrator with Release Relay Admin, or a user without it.
 */
@IsTest
private class RlyRunMonitorRestTest {

    private static final String RUN_URL = 'https://github.com/acme/release/actions/runs/4870';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // Calls the endpoint with a body and returns its JSON answer.
    private static Map<String, Object> call(Object body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/rly/pipeline-run';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body instanceof String ? (String) body : JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RlyRunMonitorRest.post();
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static RLY_Pipeline_Run__c saved(String runKey) {
        return [SELECT Id, Status__c, Started__c, Finished__c, Duration_Seconds__c, Release__c, Request_Id__c, Branch__c,
                       Target_Org__c, Workflow_Step__c, Mode__c, Actor__c, Run_Url__c, Failure_Message__c, Steps__c
                FROM RLY_Pipeline_Run__c WHERE Run_Id__c = :runKey];
    }

    @IsTest
    static void startThenEndUpsertsOneRow() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('PR open', 'check');
            Datetime began = System.now().addMinutes(-5);
            Test.startTest();
            Map<String, Object> start = call(new Map<String, Object>{
                'runId' => '4870', 'attempt' => 1, 'status' => 'in_progress', 'mode' => 'check', 'step' => 'Check-only deploy',
                'branch' => 'feature/rel-00001', 'targetOrg' => 'sit', 'started' => JSON.serialize(began).remove('"'),
                'actor' => 'Test user', 'runUrl' => RUN_URL, 'requestId' => rel.Name.toLowerCase(), 'somethingElse' => 'ignored' });
            Integer startCode = RestContext.response.statusCode;
            Map<String, Object> finish = call(new Map<String, Object>{
                'runId' => 4870, 'status' => 'failure', 'failureMessage' => 'validate: Check-only deploy failed',
                'steps' => new List<Object>{
                    new Map<String, Object>{ 'name' => 'Raise pull request', 'outcome' => 'success', 'seconds' => 30 },
                    new Map<String, Object>{ 'name' => 'Check-only deploy', 'outcome' => 'failure', 'seconds' => 90.4 },
                    new Map<String, Object>{ 'outcome' => 'skipped' } } });
            Map<String, Object> late = call(new Map<String, Object>{ 'runId' => '4870', 'attempt' => '1', 'status' => 'running' });
            Test.stopTest();
            System.assertEquals(200, startCode, 'The start is saved');
            System.assertEquals(true, start.get('ok'), 'ok');
            System.assertEquals('4870-1', start.get('runKey'), 'Run id and attempt make the key');
            System.assertEquals(rel.Name, start.get('release'), 'The release is found by its number');
            System.assertEquals('Failed', finish.get('status'), 'The end is saved');
            System.assertEquals('Failed', late.get('status'), 'A late start never sets a finished run back');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE Id != null], 'One row per run attempt');
            RLY_Pipeline_Run__c row = saved('4870-1');
            System.assertEquals(rel.Id, row.Release__c, 'Linked to the release');
            System.assertEquals(rel.Name, row.Request_Id__c, 'Request id upper-cased');
            System.assertEquals('feature/rel-00001', row.Branch__c, 'The start\'s branch stays');
            System.assertEquals('Check-only deploy', row.Workflow_Step__c, 'Step');
            System.assertEquals('check', row.Mode__c, 'Mode');
            System.assertEquals('Test user', row.Actor__c, 'Actor');
            System.assertEquals(RUN_URL, row.Run_Url__c, 'Run URL');
            System.assertNotEquals(null, row.Finished__c, 'Finished stamped');
            System.assertNotEquals(null, row.Duration_Seconds__c, 'Duration worked out');
            System.assert(row.Duration_Seconds__c >= 290, 'Duration counts from the start sent: ' + row.Duration_Seconds__c);
            System.assertEquals('validate: Check-only deploy failed', row.Failure_Message__c, 'Failure message');
            List<RlyRunMonitorViews.Step> steps = RlyRunMonitorRows.steps(row.Steps__c);
            System.assertEquals(2, steps.size(), 'A job without a name is left out');
            System.assertEquals('failure', steps[1].outcome, 'Outcome kept');
            System.assertEquals(90, steps[1].seconds, 'Seconds rounded');
        }
    }

    @IsTest
    static void refusesBadBodies() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Map<String, Object> noRun = call(new Map<String, Object>{ 'status' => 'queued' });
            Integer noRunCode = RestContext.response.statusCode;
            Map<String, Object> badStatus = call(new Map<String, Object>{ 'runId' => '12', 'status' => 'sleeping' });
            Map<String, Object> badAttempt = call(new Map<String, Object>{ 'runId' => '12', 'attempt' => 0, 'status' => 'queued' });
            Map<String, Object> notJson = call('not json');
            Map<String, Object> noBody = call(null);
            Map<String, Object> listBody = call('[1,2]');
            Test.stopTest();
            System.assertEquals(400, noRunCode, 'Bad body answers 400');
            System.assertEquals(RlyRunMonitorInbound.NO_RUN_ID, noRun.get('error'), 'No run id');
            System.assertEquals(RlyRunMonitorInbound.NO_STATUS, badStatus.get('error'), 'Unknown status');
            System.assertEquals(RlyRunMonitorInbound.BAD_ATTEMPT, badAttempt.get('error'), 'Attempt 0');
            System.assertEquals(RlyRunMonitorInbound.NO_RUN_ID, notJson.get('error'), 'Bad JSON');
            System.assertEquals(RlyRunMonitorInbound.NO_RUN_ID, noBody.get('error'), 'No body');
            System.assertEquals(RlyRunMonitorInbound.NO_RUN_ID, listBody.get('error'), 'Not an object');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE Id != null], 'Nothing saved');
        }
    }

    @IsTest
    static void skipsBadValuesWithWarnings() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Map<String, Object> out = call(new Map<String, Object>{
                'runId' => '77', 'attempt' => 2, 'status' => 'Succeeded', 'started' => 'yesterday', 'runUrl' => 'http://example.com/run',
                'requestId' => 'REL-99999', 'steps' => 'not a list', 'durationSeconds' => 61, 'finished' => '2026-01-02T03:04:05Z' });
            Test.stopTest();
            System.assertEquals(200, RestContext.response.statusCode, 'Saved');
            List<Object> warnings = (List<Object>) out.get('warnings');
            System.assertEquals(4, warnings.size(), 'started, runUrl, steps and the unknown release: ' + warnings);
            System.assertEquals(null, out.get('release'), 'No release linked');
            RLY_Pipeline_Run__c row = saved('77-2');
            System.assertEquals('Succeeded', row.Status__c, 'Status');
            System.assertEquals(61, row.Duration_Seconds__c.intValue(), 'The duration sent is kept');
            System.assertEquals(null, row.Release__c, 'No release');
            System.assertEquals('REL-99999', row.Request_Id__c, 'Request id kept');
            System.assertNotEquals(null, row.Started__c, 'Started defaults to now');
            System.assertEquals(null, row.Run_Url__c, 'Only https addresses');
        }
    }

    @IsTest
    static void refusesCallerWithoutAdmin() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            Test.startTest();
            Map<String, Object> out = call(new Map<String, Object>{ 'runId' => '5', 'status' => 'queued' });
            Test.stopTest();
            System.assertEquals(403, RestContext.response.statusCode, 'Refused');
            System.assertEquals(RlyRunMonitorInbound.NOT_ADMIN, out.get('error'), 'Says why');
        }
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE Id != null], 'Nothing saved');
        }
    }

    @IsTest
    static void readsValues() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(RlyRunMonitorInput.CANCELLED, RlyRunMonitorInput.status('Canceled'), 'GitHub spelling');
            System.assertEquals(RlyRunMonitorInput.QUEUED, RlyRunMonitorInput.status('waiting'), 'Waiting is queued');
            System.assertEquals(RlyRunMonitorInput.SUCCEEDED, RlyRunMonitorInput.status('success'), 'success');
            System.assertEquals(null, RlyRunMonitorInput.status(42), 'A number is no status');
            System.assertEquals('12', RlyRunMonitorInput.text(12, 10), 'Numbers read as text');
            System.assertEquals('ab', RlyRunMonitorInput.text('  abc ', 2), 'Trimmed and cut');
            System.assertEquals(null, RlyRunMonitorInput.text(true, 5), 'A Boolean is no text');
            System.assertEquals(3L, RlyRunMonitorInput.whole(2.6), 'Decimals round');
            System.assertEquals(null, RlyRunMonitorInput.whole('2x'), 'Not digits');
            System.assertNotEquals(null, RlyRunMonitorInput.moment('2026-11-06T14:05:00.000Z'), 'With milliseconds');
            System.assertNotEquals(null, RlyRunMonitorInput.moment('2026-11-06T14:05:00Z'), 'Without milliseconds');
            System.assertEquals(null, RlyRunMonitorInput.moment('6 Nov'), 'Not ISO');
            System.assertEquals(null, RlyRunMonitorInput.releaseNumber('REL-1'), 'Too short');
            System.assertEquals('REL-00042', RlyRunMonitorInput.releaseNumber('rel-00042'), 'Upper-cased');
            String steps = RlyRunMonitorSteps.steps('[{"name":"Code scan","outcome":"success","seconds":"12","extra":1}]');
            System.assert(steps.contains('Code scan') && !steps.contains('extra'), 'Only name, outcome and seconds: ' + steps);
            System.assertEquals(null, RlyRunMonitorSteps.steps(new List<Object>{ 'x' }), 'No usable job');
            System.assertEquals(0, RlyRunMonitorRows.steps('{bad').size(), 'Bad saved JSON gives no jobs');
            System.assertEquals(true, RlyRunMonitorInput.isFinal('Failed'), 'Failed is final');
            System.assertEquals(false, RlyRunMonitorInput.isFinal('Queued'), 'Queued is not');
        }
    }

    // A release whose checks failed in run 4871 (a test failed); GitHub ended that run green.
    private static RLY_Release__c checksFailed(String runId) {
        RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
        rel.Run_ID__c = runId;
        rel.Status__c = RlyRunMonitorChecks.CHECKS_FAILED;
        rel.Validation_Status__c = 'Failed';
        rel.Validation_Result__c = JSON.serialize(new Map<String, Object>{ 'status' => 'Failed', 'message' => '1 test failure(s)',
            'testFailures' => new List<Object>{ new Map<String, Object>{ 'name' => 'LabelFormatterTest', 'method' => 'formats', 'message' => 'x' } } });
        rel.Scan_Status__c = 'Passed';
        update rel;
        return rel;
    }

    @IsTest
    static void aGreenRunWhoseChecksFailedIsSavedFailed() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = checksFailed('4871');
            Test.startTest();
            Map<String, Object> answer = call(new Map<String, Object>{ 'runId' => '4871', 'status' => 'success', 'mode' => 'hub',
                'requestId' => rel.Name });
            Map<String, Object> other = call(new Map<String, Object>{ 'runId' => '4872', 'status' => 'success', 'requestId' => rel.Name });
            Test.stopTest();
            System.assertEquals('Failed', answer.get('status'), 'The run its checks failed in shows Failed');
            RLY_Pipeline_Run__c row = saved('4871-1');
            System.assert(row.Failure_Message__c.contains('1 test failed (LabelFormatterTest.formats)'), 'With why: ' + row.Failure_Message__c);
            System.assertEquals('Succeeded', other.get('status'), 'Another run of the release stays as GitHub says');
        }
    }

    @IsTest
    static void aReleaseTurningChecksFailedFailsItsGreenRun() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            call(new Map<String, Object>{ 'runId' => '4873', 'status' => 'success', 'requestId' => rel.Name });
            RLY_Release__c failed = checksFailed('4873');
            failed.Id = rel.Id;
            Test.startTest();
            Integer marked = RlyRunMonitorChecks.afterRead(failed, 'Validating');
            Integer again = RlyRunMonitorChecks.afterRead(failed, RlyRunMonitorChecks.CHECKS_FAILED);
            Test.stopTest();
            System.assertEquals(1, marked, 'The green attempt is marked');
            System.assertEquals(0, again, 'Only when the release has just turned Checks failed');
            System.assertEquals('Failed', saved('4873-1').Status__c, 'Failed on the monitor');
        }
    }

    @IsTest
    static void theReasonNamesWhatFailed() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c conflict = new RLY_Release__c(Validation_Status__c = 'Failed', Target_Branch__c = 'sit',
                Validation_Result__c = '{"conflicts":[{"file":"a"}]}', Scan_Status__c = 'Failed', Scan_Blocking__c = 2);
            RLY_Release__c message = new RLY_Release__c(Validation_Status__c = 'Error', Validation_Result__c = 'not json');
            RLY_Release__c bare = new RLY_Release__c(Validation_Status__c = 'Passed');
            Test.startTest();
            String a = RlyRunMonitorChecks.reasonFor(conflict);
            String b = RlyRunMonitorChecks.reasonFor(message);
            String c = RlyRunMonitorChecks.reasonFor(bare);
            Test.stopTest();
            System.assertEquals('Checks failed: conflicts with sit; code scan: 2 blocking findings.', a, 'Conflict and scan');
            System.assertEquals('Checks failed: the check-only deploy failed.', b, 'No result to read');
            System.assertEquals('Checks failed.', c, 'Nothing more to say');
            System.assertEquals(null, RlyRunMonitorChecks.failedChecksOf(null, 1L), 'No release: GitHub\'s word stands');
        }
    }
}
