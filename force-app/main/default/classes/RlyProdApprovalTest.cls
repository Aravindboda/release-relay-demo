/**
 * @description Tests for the build 49 add-ons when they are held (RlyRoles, RlyProdApproval, the approvers window's
 * Production mark in RlySlackApproverRows, Deploy now anyway in RlyWindowGate): runs as an active System Administrator
 * with Release Relay Approver, Admin, Production Approver and Release Window Bypass. Records are inserted before
 * Test.startTest.
 */
@IsTest
private class RlyProdApprovalTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
        RlyTestData.assignPermissionSet('RLY_Admin');
        RlyTestData.assignPermissionSet('RLY_Prod_Approver_Addon');
        RlyTestData.assignPermissionSet('RLY_Window_Bypass_Addon');
    }

    @IsTest
    static void holdersApproveProduction() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = new RLY_Release__c(Status__c = 'Ready for approval', Target_Org__r = new RLY_Org__c(Role__c = 'Hub'));
            RlyProdApproval.save(RlyProdApproval.STATE_ON);
            System.assert(RlyProdApproval.needsAddon(rel), 'Production needs the add-on');
            System.assert(RlyProdApproval.mayApprove(rel, UserInfo.getUserId()), 'The test user holds it');
            System.assertEquals(null, RlyProdApproval.noteFor(rel), 'No note for a holder');
            RlyProdApproval.require(rel, RlyApprover.currentUser(null));
            Set<Id> holders = RlyRoles.holdersOf(RlyProdApproval.PERMISSION, null);
            System.assert(holders.contains(UserInfo.getUserId()), 'Listed as a holder');
            System.assert(RlyRoles.userHolds(RlyProdApproval.PERMISSION, UserInfo.getUserId()), 'Holds it');
            RlyProdApproval.View v = RlyProdApproval.view();
            System.assert(v.holderCount >= 1 && !v.holderNames.isEmpty(), 'Holders shown: ' + v.holderCount);
            Boolean marked = false;
            for (RlySlackApproverRows.Row r : new RlySlackApproverRows('Manual', null).rows()) {
                marked = marked || (r.userId == UserInfo.getUserId() && r.access.endsWith('· Production'));
            }
            System.assert(marked, 'The approvers window marks production approvers');
            System.assert(RlySlackApprovers.load().prodNote.startsWith(RlyProdApproval.NOTE), 'The window says the rule is on');
            RLY_Release__c sit = new RLY_Release__c(Status__c = 'Ready for approval', Target_Org__r = new RLY_Org__c(Role__c = 'Stage'));
            System.assert(!RlyProdApproval.needsAddon(sit), 'Other orgs don\'t');
        }
    }

    @IsTest
    static void bypassHoldersSeeDeployNowAnyway() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyWindowGate.mayBypass(), 'Holds the Release Window Bypass add-on');
            String refused;
            try {
                RlyWindowGate.deployNow(null, 'Production incident');
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('waiting for the window'), 'Passes the add-on check: ' + refused);
        }
    }

    @IsTest
    static void raiserCantApproveOwnProductionRelease() {
        System.runAs(RlyTestData.admin()) {
            String me = UserInfo.getUserId();
            RlyProdApproval.save(RlyProdApproval.STATE_ON);
            RLY_Release__c own = (RLY_Release__c) JSON.deserialize('{"attributes":{"type":"RLY_Release__c"},"CreatedById":"' + me
                + '","Status__c":"Ready for approval","Target_Org__r":{"attributes":{"type":"RLY_Org__c"},"Role__c":"Hub"}}', RLY_Release__c.class);
            System.assert(RlyProdApproval.isOwnProduction(own, me), 'The raiser of a production release');
            System.assertEquals(RlyProdApproval.OWN_NOTE, RlyProdApproval.noteFor(own), 'The page tells the raiser');
            String refused;
            try {
                RlyProdApproval.require(own, RlyApprover.currentUser(null));
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assertEquals(RlyProdApproval.OWN_NOTE, refused, 'Refused for the raiser');
            RLY_Release__c sit = (RLY_Release__c) JSON.deserialize('{"attributes":{"type":"RLY_Release__c"},"CreatedById":"' + me
                + '","Status__c":"Ready for approval","Target_Org__r":{"attributes":{"type":"RLY_Org__c"},"Role__c":"Stage"}}', RLY_Release__c.class);
            System.assert(!RlyProdApproval.isOwnProduction(sit, me), 'Other orgs keep self-approval');
            RlyProdApproval.save('Off');
            System.assert(!RlyProdApproval.isOwnProduction(own, me), 'Off: production approval isn\'t governed');
        }
    }
}
