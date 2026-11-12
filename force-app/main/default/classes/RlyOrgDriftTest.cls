/**
 * @description Tests for the target org's own changes (build 60, D38: RlyOrgDrift) and the raise's kept lines on the
 * validation result (D40: RlyKeepResults). Every test runs as an existing active System Administrator through
 * System.runAs; releases are inserted by RlyReleaseTestData.
 */
@IsTest
private class RlyOrgDriftTest {

    private static final String DRIFT = '[{"component":"Layout:Account-Account Layout","items":["layoutItems:AccountSource"]}]';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    @IsTest
    static void approvingNeedsTheTick() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Org_Drift__c = DRIFT);
            String message;
            try {
                RlyReleasesController.approve(rel.Id, null, new List<String>());
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assert(message != null && message.contains('Tick'), 'Refused without the tick: ' + message);
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Still waiting');

            RLY_Release__c loaded = RlyReleaseStore.release(rel.Id);
            System.assertEquals(1, RlyOrgDrift.entries(loaded).size(), 'One component changed in SIT');
            RlyApprover slack = RlyApprover.slackUser(new User(Id = UserInfo.getUserId()), null);
            slack.acknowledgedDrift = true;
            String slackMessage;
            try {
                RlyOrgDrift.require(loaded, slack);
            } catch (RlyReleaseException e) {
                slackMessage = e.getMessage();
            }
            System.assert(slackMessage != null && slackMessage.contains('release page'), 'The Slack card can\'t confirm it');

            RlyApprover me = RlyApprover.currentUser(null);
            me.acknowledgedDrift = true;
            RlyOrgDrift.require(loaded, me);
            RlyReleaseLog.flush();
            List<RLY_Release_Event__c> events = [SELECT Detail__c FROM RLY_Release_Event__c WHERE Release__c = :rel.Id AND Event_Type__c = :RlyOrgDrift.EVENT];
            System.assertEquals(1, events.size(), 'History records the confirmation');
            System.assert(events[0].Detail__c.contains('Account-Account Layout'), events[0].Detail__c);
        }
    }

    @IsTest
    static void theStatusCheckSavesTheDrift() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseStore.release(RlyReleaseTestData.release('Ready for approval', 'hub').Id);
            rel.Org_Drift__c = DRIFT;
            RlyReleaseStore.saveAll(new List<RLY_Release__c>{ rel });
            System.assertEquals(DRIFT, RlyReleaseTestData.reload(rel.Id).Org_Drift__c, 'Saved with the check\'s other results, so approving sees it');
            rel.Org_Drift__c = null;
            RlyReleaseStore.saveAll(new List<RLY_Release__c>{ rel });
            System.assertEquals(null, RlyReleaseTestData.reload(rel.Id).Org_Drift__c, 'A new check clears it');
        }
    }

    @IsTest
    static void validationKeepsDriftAndKeptLines() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = new RLY_Release__c(Pending_Run__c = 'check',
                Validation_Result__c = '{"status":"Passed","raiseKept":[{"component":"Layout:L","items":["layoutItems:Fax"]}]}');
            Map<String, Object> val = new Map<String, Object>{ 'status' => 'Passed',
                RlyKeepResults.DRIFT_KEY => (List<Object>) JSON.deserializeUntyped(DRIFT) };
            RlyKeepResults.onValidation(rel, null, val);
            System.assert(val.containsKey(RlyKeepResults.KEPT_KEY), 'A check run again carries the raise\'s kept lines over');
            System.assert(rel.Org_Drift__c.contains('AccountSource'), 'The drift is kept for approving');

            Map<String, Object> clean = new Map<String, Object>{ 'status' => 'Passed', RlyKeepResults.DRIFT_KEY => new List<Object>() };
            RlyKeepResults.onValidation(rel, null, clean);
            System.assertEquals(null, rel.Org_Drift__c, 'No drift any more');
            RlyKeepResults.onValidation(rel, null, null);
            System.assertEquals(0, RlyOrgDrift.entries(new RLY_Release__c(Org_Drift__c = 'not json')).size(), 'Unreadable reads as none');
        }
    }
}
