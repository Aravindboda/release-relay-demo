/**
 * @description Tests for the nightly archive endpoint (RlyArchiveRest, RlyArchiveNightly): every call stamps the last
 * call, skipped calls (not the production hub, not an admin, nightly off, no days, another run going, a finished run)
 * leave no row, nothing eligible leaves a Succeeded "Nothing to remove" row, and eligible releases go one pass per call
 * until done, with the GitHub run linked. Each test runs through System.runAs as the active System Administrator with
 * Release Relay Admin, or a user without it.
 */
@IsTest
private class RlyArchiveRestTest {

    private static final String RUN_URL = 'https://github.com/acme/release/actions/runs/4870';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // Calls the endpoint with a body and returns its JSON answer.
    private static Map<String, Object> call(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/rly/archive';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RlyArchiveRest.archive();
        System.assertEquals(200, RestContext.response.statusCode, 'Answered');
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static String body(Id runId) {
        Map<String, Object> m = new Map<String, Object>{ 'runUrl' => RUN_URL };
        if (runId != null) {
            m.put('runId', runId);
        }
        return JSON.serialize(m);
    }

    private static Integer runRows() {
        return [SELECT COUNT() FROM RLY_Archive_Run__c WHERE Id != null];
    }

    @IsTest
    static void skipsAndStamps() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.retention(30);
            Test.startTest();
            Map<String, Object> off = call(body(null));
            RlyArchiveTestData.nightly(null);
            Map<String, Object> noDays = call('not json');
            RlyArchiveTestData.nightly(30);
            RLY_Archive_Run__c going = RlyArchiveTestData.run(RlyArchiveRuns.RUN_NOW, RlyArchiveRuns.RUNNING, System.now());
            Map<String, Object> busy = call(null);
            Map<String, Object> ended = call(JSON.serialize(new Map<String, Object>{ 'runId' => going.Id }));
            Map<String, Object> badId = call(JSON.serialize(new Map<String, Object>{ 'runId' => 'abc' }));
            Test.stopTest();
            System.assertEquals(RlyArchiveNightly.SKIP_OFF, off.get('reason'), 'Nightly off');
            System.assertEquals(true, off.get('skipped'), 'Skipped');
            System.assertEquals(true, off.get('done'), 'Done');
            System.assertEquals(RlyArchiveNightly.SKIP_DAYS, noDays.get('reason'), 'No days');
            System.assertEquals(RlyArchiveNightly.SKIP_BUSY, busy.get('reason'), 'Another run is going');
            System.assertEquals(RlyArchiveNightly.SKIP_ENDED, ended.get('reason'), 'Not a nightly run');
            System.assertEquals(RlyArchiveNightly.SKIP_BUSY, badId.get('reason'), 'A bad id counts as a first call');
            System.assertEquals(1, runRows(), 'Skipped calls add no row');
            RLY_Git_Connection__c conn = RlyArchiveTestData.settings();
            System.assertNotEquals(null, conn.Last_Nightly_Call__c, 'Stamped');
            System.assertEquals(RlyArchiveNightly.SKIP_BUSY, conn.Last_Nightly_Result__c, 'Last result');
        }
    }

    @IsTest
    static void nothingToRemove() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.nightly(30);
            Test.startTest();
            Map<String, Object> out = call(body(null));
            Test.stopTest();
            System.assertEquals(true, out.get('done'), 'Done');
            System.assertEquals(false, out.get('skipped'), 'Not skipped');
            System.assertEquals(RlyArchiveNightly.NOTHING, out.get('reason'), 'Nothing to remove');
            RLY_Archive_Run__c row = [SELECT How__c, Status__c, Message__c, Pipeline_Run_Url__c FROM RLY_Archive_Run__c LIMIT 1];
            System.assertEquals(RlyArchiveRuns.NIGHTLY, row.How__c, 'Nightly');
            System.assertEquals(RlyArchiveRuns.SUCCEEDED, row.Status__c, 'Succeeded');
            System.assertEquals(RUN_URL, row.Pipeline_Run_Url__c, 'Linked to the GitHub run');
            System.assertEquals('Succeeded: nothing to remove', RlyArchiveTestData.settings().Last_Nightly_Result__c, 'Stamped');
        }
    }

    @IsTest
    static void passesUntilDone() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Deployed', 2);
            RlyArchiveTestData.nightly(30);
            RlyArchiveTestData.later(60);
            RlyArchiveBatch.passReleases = 1;
            Test.startTest();
            Map<String, Object> first = call(body(null));
            Id runId = Id.valueOf((String) first.get('runId'));
            String afterFirst = RlyArchiveTestData.settings().Last_Nightly_Result__c;
            Map<String, Object> second = call(body(runId));
            Test.stopTest();
            System.assertEquals(1, first.get('pass'), 'Pass 1');
            System.assertEquals(1, first.get('removed'), 'One release');
            System.assertEquals(5, first.get('records'), 'With its children');
            System.assertEquals(1, first.get('remaining'), 'One left');
            System.assertEquals(false, first.get('done'), 'Not done');
            System.assertEquals('Running: pass 1', afterFirst, 'Stamped after pass 1');
            System.assertEquals(2, second.get('pass'), 'Pass 2');
            System.assertEquals(true, second.get('done'), 'Done');
            System.assertEquals(0, second.get('remaining'), 'Nothing left');
            System.assertEquals('2 passes · all eligible removed · run #4870', second.get('reason'), 'Message with the run');
            RLY_Archive_Run__c row = [SELECT How__c, Status__c, Releases_Removed__c, Run_By__c FROM RLY_Archive_Run__c WHERE Id = :runId];
            System.assertEquals(RlyArchiveRuns.NIGHTLY, row.How__c, 'Nightly');
            System.assertEquals(RlyArchiveRuns.SUCCEEDED, row.Status__c, 'Succeeded');
            System.assertEquals(2, row.Releases_Removed__c, 'Both');
            System.assertEquals(UserInfo.getUserId(), row.Run_By__c, 'The caller');
            System.assertEquals(RlyArchiveRuns.SUCCEEDED, RlyArchiveTestData.settings().Last_Nightly_Result__c, 'Stamped');
        }
    }

    @IsTest
    static void failedPassIsStamped() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Deployed', 1);
            RlyArchiveTestData.nightly(30);
            RlyArchiveTestData.later(60);
            RlyArchivePass.failForTest = true;
            Test.startTest();
            Map<String, Object> out = call(body(null));
            Test.stopTest();
            System.assertEquals(true, out.get('done'), 'The run stops');
            System.assert(((String) out.get('reason')).contains('UNABLE_TO_LOCK_ROW'), 'Why');
            System.assert(RlyArchiveTestData.settings().Last_Nightly_Result__c.startsWith('Failed: '), 'Stamped');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Release__c WHERE Id != null], 'Nothing removed');
        }
    }

    @IsTest
    static void refusesOutsideTheHubAndNonAdmins() {
        User plain = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.nightly(30);
        }
        System.runAs(plain) {
            Map<String, Object> notAdmin = call(body(null));
            System.assertEquals(RlyArchiveNightly.SKIP_ADMIN, notAdmin.get('reason'), 'Needs Release Relay Admin');
        }
        System.runAs(RlyTestData.admin()) {
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.forget();
            Map<String, Object> sandbox = call(body(null));
            System.assertEquals(RlyArchiveNightly.SKIP_HUB, sandbox.get('reason'), 'Production hub only');
            System.assertEquals(0, runRows(), 'No rows');
        }
    }
}
