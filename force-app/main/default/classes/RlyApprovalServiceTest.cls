/**
 * @description Tests for approving, rejecting and re-checking releases, and for the release lists
 * (RlyApprovalService, RlyReleasesController). Each test runs as an active System Administrator with the
 * Release Relay Approver permission set via System.runAs. Records are inserted before Test.startTest;
 * callouts come after it.
 */
@IsTest
private class RlyApprovalServiceTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    @IsTest
    static void approveStartsMergeAndDeploy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.approve(rel.Id, 'Looks good');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            String dispatched = mock.bodyFor('/dispatches');
            System.assertEquals('Deploying', saved.Status__c, 'Deploying');
            System.assertEquals('Approved', saved.Approval_Status__c, 'Approved');
            System.assertEquals('merge', saved.Pending_Run__c, 'Merge run');
            System.assert(dispatched.contains('"mode":"merge"') && dispatched.contains('"target_environment":"sit"'), dispatched);
            System.assert(d.isApprover, 'Approver');
        }
    }

    @IsTest
    static void rejectNeedsAComment() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            Boolean refused = false;
            try {
                RlyReleasesController.reject(rel.Id, '');
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'A comment is required');
            RlyReleasesController.reject(rel.Id, 'Split the layout change out');
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Rejected', saved.Status__c, 'Rejected');
            System.assertEquals('Rejected', saved.Approval_Status__c, 'Approval rejected');
        }
    }

    @IsTest
    static void rejectClosesThePullRequest() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.reject(rel.Id, 'Validation failed: fix the test and raise again');
            Test.stopTest();
            String calls = mock.callLog();
            System.assert(calls.contains('PATCH callout:RLY_GitHub/repos/acme/release/pulls/42'), 'Pull request closed: ' + calls);
            System.assert(calls.contains('/issues/42/comments'), 'Reason commented');
            System.assertEquals(null, RlyReleaseTestData.reload(rel.Id).Error_Message__c, 'No error');
        }
    }

    @IsTest
    static void checkAgainRerunsTheChecks() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Failed', Validation_Status__c = 'Passed');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.checkAgain(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            String dispatched = mock.bodyFor('/dispatches');
            System.assertEquals('Validating', saved.Status__c, 'Checking again');
            System.assertEquals('Pending', saved.Scan_Status__c, 'Scan pending');
            System.assert(dispatched.contains('"mode":"check"'), dispatched);
        }
    }

    @IsTest
    static void refusesActionsAtTheWrongTime() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            Integer refused = 0;
            try { RlyReleasesController.approve(rel.Id, null); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.checkAgain(rel.Id); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.bypassScan(rel.Id, 'A long enough reason'); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.getRelease(null); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Nothing happens out of order');
        }
    }

    @IsTest
    static void listsReleases() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            System.assertEquals(1, RlyReleasesController.listReleases('mine').size(), 'Mine');
            System.assertEquals(1, RlyReleasesController.listReleases('all').size(), 'All');
            System.assertEquals(1, RlyReleasesController.listReleases('approvals').size(), 'Waiting for approval');
            System.assert(RlyReleasesController.isApprover(), 'Approver');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals(2, d.items.size(), 'Items');
            System.assertEquals('DEV1', d.sourceName, 'Source');
            System.assert(!d.running, 'Not running');
        }
    }
}
