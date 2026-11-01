/**
 * @description Tests for sandbox copies of the hub: RlyHubGuard (the hub, a copy, first-time setup, the page status),
 * the status reader only reading in a copy, actions refused there, and the post-copy script RlySandboxCopy. Every test
 * runs as an active System Administrator via System.runAs.
 */
@IsTest
private class RlyHubGuardTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    // The hub record carries another org's Id: this org is a copy.
    private static void makeCopy() {
        update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Role__c = 'Hub' LIMIT 1].Id, Org_Id__c = RlyTestData.fakeId('00D', 7));
        RlyHubGuard.known = null;
    }

    @IsTest
    static void hubAndFirstTimeSetup() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyHubGuard.isHub(), 'No hub record yet: first-time setup counts as the hub');
            RlyReleaseTestData.route();
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Role__c = 'Hub' LIMIT 1].Id,
                Org_Id__c = String.valueOf(UserInfo.getOrganizationId()).left(15));
            RlyHubGuard.known = null;
            System.assert(RlyHubGuard.isHub(), 'Same org, 15 against 18 characters');
            RlyHubGuard.requireHub();
            RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
            System.assertEquals(false, s.isHubCopy, 'Not a copy');
            System.assertEquals(null, s.message, 'No banner');
        }
    }

    @IsTest
    static void copyRefusesActionsAndOnlyReads() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            makeCopy();
            RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
            System.assertEquals(true, s.isHubCopy, 'A copy');
            System.assertEquals(RlyHubGuard.COPY_MESSAGE, s.message, 'Banner');
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(0, mock.calls.size(), 'No callouts in a copy: ' + mock.callLog());
            System.assertEquals('Workflow running', d.release.Status__c, 'Nothing moved');
            Integer refused = 0;
            try {
                RlyApprovalService.approveRelease(rel.Id, 'ok');
            } catch (AuraHandledException e) {
                refused += e.getMessage() == RlyHubGuard.COPY_MESSAGE ? 1 : 0;
            }
            try {
                RlyReleasesController.checkAgain(rel.Id);
            } catch (AuraHandledException e) {
                refused += e.getMessage() == RlyHubGuard.COPY_MESSAGE ? 1 : 0;
            }
            try {
                RlyRouteController.createBranches();
            } catch (AuraHandledException e) {
                refused += e.getMessage() == RlyHubGuard.COPY_MESSAGE ? 1 : 0;
            }
            System.assertEquals(3, refused, 'Approve, check again and branches are refused in a copy');
        }
    }

    @IsTest
    static void postCopyScriptQuietsSlackAndGit() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyReleaseTestData.slackOn('Deployed');
            Test.startTest();
            Test.testSandboxPostCopyScript(new RlySandboxCopy(), UserInfo.getOrganizationId(), UserInfo.getOrganizationId(), 'Hub copy');
            Test.stopTest();
            System.assertEquals(false, [SELECT Enabled__c FROM RLY_Notification__c LIMIT 1].Enabled__c, 'Slack off');
            RLY_Git_Connection__c g = [SELECT Status__c, Status_Message__c FROM RLY_Git_Connection__c LIMIT 1];
            System.assertEquals('Not checked', g.Status__c, 'Git not checked');
            System.assertEquals(RlySandboxCopy.NOTE, g.Status_Message__c, 'Note left');
        }
    }
}
