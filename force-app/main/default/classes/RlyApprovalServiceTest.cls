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
            // A second vendor, and a third org sharing dev1: each branch is synced once.
            RLY_Org__c sharing = RlyTestData.org('DEV3', 'Developer', 'dev1');
            insert new List<RLY_Org__c>{ RlyTestData.org('DEV2', 'Developer', 'dev2'), sharing };
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
            Map<String, Object> options = RlyReleaseTestData.dispatchedOptions(mock);
            System.assertEquals(new List<Object>{ 'dev1', 'dev2' }, options.get('syncBranches'), 'Every developer branch, once');
            System.assert(!options.containsKey('validateMerged'), 'The merge itself isn\'t a validation');
            System.assert(d.isApprover, 'Approver');
        }
    }

    @IsTest
    static void laterStagesDontSyncBranches() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RLY_Org__c uat = RlyTestData.stage('UAT', 'uat', 2);
            insert uat;
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Target_Org__c = uat.Id, Target_Branch__c = 'uat');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.approve(rel.Id, null);
            Test.stopTest();
            System.assert(!RlyReleaseTestData.dispatchedOptions(mock).containsKey('syncBranches'), 'Only a merge into the first stage syncs');
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
    static void rejectClosesEvenWhenTheCommentFails() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/issues/42/comments').reply(500, '{"message":"Server error"}')
                .match('PATCH', '/pulls/42').reply(200, '{"state":"closed"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.reject(rel.Id, 'Not this sprint');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assert(mock.callLog().contains('PATCH callout:RLY_GitHub/repos/acme/release/pulls/42'), 'Closed anyway: ' + mock.callLog());
            System.assertEquals('Rejected', saved.Status__c, 'Rejected');
            System.assert(saved.Error_Message__c.startsWith('Rejected, but the comment couldn\'t be posted'), saved.Error_Message__c);
            System.assert(!saved.Error_Message__c.contains('couldn\'t be closed'), 'The close worked');
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
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('validateMerged'), 'Validated merged with sit');
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
