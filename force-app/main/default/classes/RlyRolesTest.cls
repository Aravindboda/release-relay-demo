/**
 * @description Tests for build 49's roles without add-ons (RlyRoles, RlyProdApproval, RlyAccessController, the Deploy now
 * anyway add-on in RlyWindowGate, the deployment team's data moves in RlyDataRules, the Auditor in RlyArchiveService and
 * RlyWorkItemsController): runs as an active System Administrator with Release Relay Approver and Admin but none of the
 * add-ons, or as a new user with only the Auditor or Deployment Team permission set. Records are inserted before
 * Test.startTest.
 */
@IsTest
private class RlyRolesTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A new user holding one permission set (inserted as the test user).
    private static User userWith(String setName) {
        User u = RlyTestData.plainUser();
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :setName LIMIT 1];
        System.runAs(RlyTestData.admin()) {
            if (!sets.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sets[0].Id);
            }
        }
        return u;
    }

    // A release into the hub, ready for approval.
    private static RLY_Release__c prodRelease() {
        RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
        Id prodId = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id;
        update new RLY_Release__c(Id = rel.Id, Target_Org__c = prodId, Target_Branch__c = 'prod', Target_Environment__c = 'prod');
        return RlyReleaseStore.release(rel.Id);
    }

    @IsTest
    static void productionApprovalIsOffUntilAnAdminTurnsItOn() {
        User slackPerson = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = prodRelease();
            System.assert(RlyProdApproval.isProduction(rel), 'Into the hub');
            System.assert(!RlyProdApproval.isOn(), 'Off after the upgrade');
            System.assert(RlyProdApproval.mayApprove(rel, UserInfo.getUserId()), 'Every approver until it is on');
            RlyProdApproval.View v = RlyAccessController.prodApproval();
            System.assertEquals(RlyProdApproval.BANNER_TEXT, v.banner, 'Admins see the banner');
            System.assert(v.canEdit, 'Admins change it');
            v = RlyAccessController.saveProdApproval('On');
            System.assert(v.isOn && v.banner == null, 'On, no banner');
            System.assert(v.changedText.startsWith('Turned on'), v.changedText);
            System.assert(RlyProdApproval.needsAddon(rel), 'Production needs the add-on now');
            System.assertEquals(RlyProdApproval.NOTE, RlyProdApproval.noteFor(rel), 'The page says why');
            String refused;
            try {
                RlyApprovalService.approveRelease(rel.Id, null);
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assertEquals(RlyProdApproval.NOTE, refused, 'Approver alone can\'t approve production');
            RlyApprover slackUser = RlyApprover.slackUser(new User(Id = slackPerson.Id, LastName = 'Plain'), null);
            try {
                RlyProdApproval.require(rel, slackUser);
                refused = null;
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assertEquals(RlyProdApproval.NOTE, refused, 'A Slack approver without it is refused too');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals(RlyProdApproval.NOTE, d.prodAddonNote, 'On the release page');
            System.assert(d.canRerun, 'Approvers run the checks again');
            v = RlyAccessController.saveProdApproval('Off');
            System.assert(!v.isOn, 'Off again');
        }
    }

    @IsTest
    static void onlyAdminsChangeProductionApproval() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            String refused;
            try {
                RlyAccessController.saveProdApproval('On');
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('admin'), 'Refused: ' + refused);
            RlyProdApproval.View v = RlyAccessController.prodApproval();
            System.assert(!v.canEdit && v.banner == null, 'Read only, no banner');
        }
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RLY_Release__c bare = [SELECT Id, Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assert(!RlyProdApproval.isProduction(bare), 'SIT, read from the org when the release has no Target_Org__r');
            update new RLY_Release__c(Id = rel.Id, Target_Org__c = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id);
            bare = [SELECT Id, Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assert(RlyProdApproval.isProduction(bare), 'The hub');
        }
    }

    @IsTest
    static void aNewHubStartsWithProductionApprovalOn() {
        System.runAs(RlyTestData.admin()) {
            RlyProdApproval.onNewHub();
            System.assert(RlyProdApproval.isOn(), 'On for a new hub');
            RlyProdApproval.save('Off');
            RlyProdApproval.onNewHub();
            System.assert(!RlyProdApproval.isOn(), 'An admin\'s choice stays');
            System.assert(!RlyProdApproval.isProduction(null), 'No release');
            System.assertEquals(null, RlyProdApproval.noteFor(null), 'No note');
        }
    }

    @IsTest
    static void deployNowAnywayNeedsTheAddOn() {
        System.runAs(RlyTestData.admin()) {
            System.assert(!RlyWindowGate.mayBypass(), 'Admin alone no longer bypasses the window');
            String refused;
            try {
                RlyWindowGate.deployNow(null, 'Production incident');
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assertEquals(RlyWindowGate.BYPASS_NEEDED, refused, 'Needs the add-on');
            System.assert(!RlyWindowGate.noticeFor(null).canDeployNow, 'No button');
        }
    }

    @IsTest
    static void theDeploymentTeamMovesData() {
        User team = userWith('RLY_Deploy_Team');
        System.runAs(team) {
            System.assert(RlyDataRules.mayMoveDown(), 'Copy down and refill');
            System.assert(RlyDataRules.mayLoadUp(), 'Load data sent up');
            RlyDataRules.requireLoader(new RLY_Data_Run__c(Direction__c = 'Down'));
            RlyDataRules.requireLoader(new RLY_Data_Run__c(Direction__c = 'Up', Requested_By__c = RlyTestData.admin().Id));
            System.assert(!RlyRoles.isReadOnly(), 'A role with actions');
        }
        User nobody = RlyTestData.plainUser();
        System.runAs(nobody) {
            String refused;
            try {
                RlyDataRules.requireLoader(new RLY_Data_Run__c(Direction__c = 'Down'));
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('deployment team'), 'Refused: ' + refused);
        }
    }

    @IsTest
    static void theAuditorReadsOnly() {
        User auditor = userWith(RlyRoles.AUDITOR_SET);
        Boolean auditorSetExists = ![SELECT Id FROM PermissionSet WHERE Name = :RlyRoles.AUDITOR_SET LIMIT 1].isEmpty();
        System.runAs(auditor) {
            System.assertEquals(auditorSetExists, RlyRoles.isAuditor(), 'Holds RLY_Auditor');
            System.assert(RlyRoles.isReadOnly(), 'No role permission, not a developer');
            System.assert(!RlyRoles.hasRolePermission(), 'No custom permission');
            System.assertEquals(auditorSetExists, RlyArchiveService.readArchive().canView, 'Auditors read the Archive tab');
            String refused;
            try {
                RlyWorkItemsController.syncRecent();
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null, 'No Sync now for the Auditor');
            System.assert(!RlyReleaseAccess.isApprover(), 'Can\'t approve');
            System.assert(!RlyRollback.mayRollBack(), 'Can\'t roll back');
            System.assert(!RlyReleaseAccess.mayRerunChecks(new RLY_Release__c()), 'Can\'t run checks again');
        }
        System.runAs(RlyTestData.admin()) {
            Set<Id> holders = RlyRoles.holdersOf(RlyProdApproval.PERMISSION, new Set<Id>{ auditor.Id });
            System.assert(holders.isEmpty(), 'The Auditor doesn\'t approve production');
            System.assert(!RlyRoles.userHolds(RlyProdApproval.PERMISSION, null), 'Nobody');
            System.assert(!RlyRoles.userHolds('RLY_Admin', auditor.Id), 'Not an admin');
            System.assert(RlyRoles.userHolds('RLY_Admin', UserInfo.getUserId()), 'The test user is');
        }
    }
}
