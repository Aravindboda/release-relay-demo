/**
 * @description Tests for the two-approver rule (RlyTwoApprovers and its parts of RlyApprovalService, RlyReleasePhase and
 * RlyReleaseLinks): a hotfix into an org with Hotfix_Two_Approvers__c needs two different approvers, neither the person
 * who raised it. Each test runs through System.runAs as an active System Administrator with Release Relay Admin (who
 * raises the release); the approvers are new users, acting through approveAs as the Slack path does. Records are
 * inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyTwoApproversTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static User approver(String alias) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User u = new User(Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8', LastName = alias,
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId, TimeZoneSidKey = 'America/Chicago',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@example.com');
        System.runAs(RlyTestData.admin()) {
            insert u;
        }
        return [SELECT Id, Name FROM User WHERE Id = :u.Id];
    }

    // A hotfix into SIT, which needs two approvers.
    private static RLY_Release__c hotfixIntoTwoApproverOrg() {
        RLY_Release__c rel = RlyReleaseTestData.hotfixRelease('Ready for approval');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
        update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id, Hotfix_Two_Approvers__c = true);
        return rel;
    }

    private static String refusal(Id relId, RlyApprover who) {
        try {
            RlyApprovalService.approveAs(relId, who);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void secondApproverStartsTheMerge() {
        User firstUser = approver('rlyfirst');
        User secondUser = approver('rlysecnd');
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = hotfixIntoTwoApproverOrg();
            System.assert(refusal(rel.Id, RlyApprover.currentUser('Mine')).contains('You raised this hotfix'), 'Not the one who raised it');
            RlyApprovalService.approveAs(rel.Id, RlyApprover.slackUser(firstUser, 'Looks right'));
            RLY_Release__c waiting = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', waiting.Status__c, 'Still waiting');
            System.assertEquals(firstUser.Id, waiting.Approved_By__c, 'First approval recorded');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assert(d.needsSecondApprover, 'Needs a second approver');
            System.assertEquals(firstUser.Name, d.firstApprover, 'Who approved first');
            System.assertEquals('Approved by ' + firstUser.Name + '. Waiting for a second approver.', d.notice, 'The notice');
            System.assert(refusal(rel.Id, RlyApprover.slackUser(firstUser, null)).contains('already approved'), 'Not twice by the same person');

            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyApprovalService.approveAs(rel.Id, RlyApprover.slackUser(secondUser, null));
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'The merge started');
            System.assertEquals(firstUser.Id, saved.Approved_By__c, 'The first approver stays');
            System.assertEquals(secondUser.Id, saved.Second_Approved_By__c, 'The second approver is recorded');
            System.assertNotEquals(null, saved.Second_Approved_On__c, 'With the time');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"merge"'), 'Merge dispatched');
        }
    }

    @IsTest
    static void otherReleasesNeedOneApprover() {
        User firstUser = approver('rlyonly1');
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id, Hotfix_Two_Approvers__c = true);
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            Test.startTest();
            RlyApprovalService.approveAs(rel.Id, RlyApprover.slackUser(firstUser, null));
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'Not a hotfix: one approval is enough');
            System.assertEquals(null, saved.Second_Approved_By__c, 'No second approver');
            System.assert(!RlyTwoApprovers.waitsForSecond(RlyReleaseStore.release(rel.Id)), 'Nothing to wait for');
            System.assertEquals(null, RlyTwoApprovers.notice(new RLY_Release__c()), 'No notice');
        }
    }
}
