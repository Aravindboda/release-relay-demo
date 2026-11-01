/**
 * @description Tests for RlyHubGuard's modes (the hub, production not set up yet, a sandbox with no hub, a sandbox copy
 * of the hub), the status reader only reading in a copy, actions refused there, and the post-copy script RlySandboxCopy
 * (Slack off, Git not checked, permission sets other than RLY_Admin removed). Tests count as production unless they set
 * RlyHubGuard.sandboxForTest. Every test runs as an active System Administrator via System.runAs.
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
            System.assertEquals(RlyHubGuard.MODE_HUB, s.mode, 'The hub');
            System.assertEquals(false, s.isSandbox, 'Tests count as production');
            System.assertEquals(false, s.needsSetup, 'Set up');
            System.assertEquals(null, s.title, 'No notice title');
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
            System.assertEquals(RlyHubGuard.MODE_COPY, s.mode, 'Another org\'s Id on the hub record');
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

    @IsTest
    static void productionNotSetUpShowsSetup() {
        System.runAs(RlyTestData.admin()) {
            RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
            System.assertEquals(RlyHubGuard.MODE_SETUP, s.mode, 'No hub and no Git connection yet');
            System.assertEquals(true, s.needsSetup, 'Needs setup');
            System.assertEquals(false, s.isHubCopy, 'Actions stay on so setup can run');
            System.assertEquals(RlyHubGuard.SETUP_MESSAGE, s.message, 'Setup notice');
            System.assert(s.title.contains('set up'), s.title);
            System.assert(RlyHubGuard.isHub(), 'Production counts as the hub before setup');
        }
    }

    @IsTest
    static void sandboxWithoutHubShowsSandbox() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.known = null;
            RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
            System.assertEquals(RlyHubGuard.MODE_SANDBOX, s.mode, 'Sandbox, no hub Org Id');
            System.assertEquals(true, s.isSandbox, 'Sandbox');
            System.assertEquals(true, s.isHubCopy, 'Actions off');
            System.assertEquals(false, s.needsSetup, 'Setup is done in production, not here');
            System.assertEquals(RlyHubGuard.SANDBOX_MESSAGE, s.message, 'Sandbox notice');
            System.assertEquals(false, RlyHubGuard.isHub(), 'A sandbox is never the hub');
            String refused;
            try {
                RlyRouteController.createBranches();
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assertEquals(RlyHubGuard.SANDBOX_MESSAGE, refused, 'Refused with the sandbox notice');
        }
    }

    @IsTest
    static void sandboxWithHubOrgIdIsCopy() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Role__c = 'Hub' LIMIT 1].Id,
                Org_Id__c = String.valueOf(UserInfo.getOrganizationId()));
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.known = null;
            RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
            System.assertEquals(RlyHubGuard.MODE_COPY, s.mode, 'Refreshed from production');
            System.assertEquals(true, s.isSandbox && s.isHubCopy, 'Sandbox, actions off');
            System.assertEquals(RlyHubGuard.COPY_MESSAGE, s.message, 'Copy notice');
            System.assert(s.title.contains('sandbox copy'), s.title);
            RlyHubGuard.sandboxForTest = false;
            RlyHubGuard.known = null;
            System.assertEquals(RlyHubGuard.MODE_HUB, RlyHubGuard.getHubStatus().mode, 'The same records in production: the hub');
        }
    }

    @IsTest
    static void organizationRecordAnswersOutsideTests() {
        System.runAs(RlyTestData.admin()) {
            Boolean expected = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
            System.assertEquals(expected, RlyHubGuard.organizationSaysSandbox(), 'Read from the Organization record');
            System.assertEquals(false, RlyHubGuard.isSandbox(), 'A test counts as production unless it opts in');
        }
    }

    @IsTest
    static void postCopyScriptKeepsOnlyAdmins() {
        User dev = RlyTestData.plainUser();
        Id devSet = [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Developer' LIMIT 1].Id;
        PermissionSet own = new PermissionSet(Name = 'RLY_Deploy_User_Own', Label = 'RLY Deploy User Own');
        System.runAs(RlyTestData.admin()) {
            insert own;
        }
        System.runAs(RlyTestData.admin()) {
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = dev.Id, PermissionSetId = devSet),
                new PermissionSetAssignment(AssigneeId = dev.Id, PermissionSetId = own.Id)
            };
        }
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.startTest();
            Test.testSandboxPostCopyScript(new RlySandboxCopy(), UserInfo.getOrganizationId(), UserInfo.getOrganizationId(), 'Hub copy');
            Test.stopTest();
            System.assertEquals(0, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :dev.Id AND PermissionSetId = :devSet],
                'Developer permission set removed');
            System.assertEquals(1, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :dev.Id AND PermissionSetId = :own.Id],
                'The customer\'s own RLY_ permission set stays');
            System.assertEquals(0, [SELECT COUNT() FROM PermissionSetAssignment
                                    WHERE PermissionSet.Name = 'RLY_Approver' AND AssigneeId = :UserInfo.getUserId()], 'Approver removed');
            System.assertEquals(1, [SELECT COUNT() FROM PermissionSetAssignment
                                    WHERE PermissionSet.Name = 'RLY_Admin' AND AssigneeId = :UserInfo.getUserId()], 'Admin stays');
        }
    }

    @IsTest
    static void postCopyScriptNotesWhenSetsStay() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlySandboxCopy.refuseRemovalForTest = true;
            Test.startTest();
            Test.testSandboxPostCopyScript(new RlySandboxCopy(), UserInfo.getOrganizationId(), UserInfo.getOrganizationId(), 'Hub copy');
            Test.stopTest();
            RLY_Git_Connection__c g = [SELECT Status__c, Status_Message__c FROM RLY_Git_Connection__c LIMIT 1];
            System.assertEquals('Not checked', g.Status__c, 'Git still quiet');
            System.assertEquals(RlySandboxCopy.NOTE + RlySandboxCopy.REMOVE_BY_HAND, g.Status_Message__c, 'Asks an admin to remove the sets');
            System.assertEquals(1, [SELECT COUNT() FROM PermissionSetAssignment
                                    WHERE PermissionSet.Name = 'RLY_Approver' AND AssigneeId = :UserInfo.getUserId()], 'Approver kept');
        }
    }

    @IsTest
    static void sandboxOverrideCountsOnlyHereAndUntilItsEnd() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyReleaseTestData.slackOn('Deployed');
            makeCopy();
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.forget();
            System.assertEquals(RlyHubGuard.MODE_COPY, RlyHubGuard.getHubStatus().mode, 'A copy before the override');
            RlyHubGuard.HubStatus allowed = RlySandboxSwitch.allowInSandbox(null);
            System.assertEquals(RlyHubGuard.MODE_HUB, allowed.mode, 'Acts as the hub while allowed');
            System.assertEquals(true, allowed.sandboxOverride, 'Override on');
            System.assertEquals(false, allowed.isHubCopy, 'Actions on');
            System.assert(allowed.overrideNote.contains('until') && allowed.overrideNote.contains('Slack and Git stay off'), allowed.overrideNote);
            System.assert(RlyHubGuard.isHub(), 'The hub while allowed');
            RLY_Notification__c rec = [SELECT Enabled__c, Sandbox_Allowed_Until__c, Sandbox_Allowed_By__c FROM RLY_Notification__c LIMIT 1];
            System.assertEquals(false, rec.Enabled__c, 'Slack switched off first');
            System.assertEquals(UserInfo.getUserId(), rec.Sandbox_Allowed_By__c, 'Who turned it on');
            System.assert(rec.Sandbox_Allowed_Until__c > System.now().addDays(29), '30 days by default');
            System.assertEquals('Not checked', [SELECT Status__c FROM RLY_Git_Connection__c LIMIT 1].Status__c, 'Git switched off first');

            update new RLY_Notification__c(Id = rec.Id, Sandbox_Allowed_Until__c = System.now().addHours(-1));
            RlyHubGuard.forget();
            RlyHubGuard.HubStatus expired = RlyHubGuard.getHubStatus();
            System.assertEquals(RlyHubGuard.MODE_COPY, expired.mode, 'Expired: a copy again');
            System.assertEquals(false, expired.sandboxOverride, 'Expired');

            update new RLY_Notification__c(Id = rec.Id, Sandbox_Allowed_Until__c = System.now().addDays(5),
                Sandbox_Allowed_Org_Id__c = RlyTestData.fakeId('00D', 9));
            RlyHubGuard.forget();
            System.assertEquals(false, RlyHubGuard.getHubStatus().sandboxOverride, 'Another org\'s Id (a refresh): not allowed');
            System.assertEquals(false, RlyHubGuard.isHub(), 'Not the hub');

            RlyHubGuard.HubStatus off = RlySandboxSwitch.endSandboxAllowance();
            System.assertEquals(RlyHubGuard.MODE_COPY, off.mode, 'Turned off');
            System.assertEquals(null, [SELECT Sandbox_Allowed_Org_Id__c FROM RLY_Notification__c WHERE Id = :rec.Id].Sandbox_Allowed_Org_Id__c, 'Cleared');
        }
    }

    @IsTest
    static void sandboxOverrideWithoutSlackRecordAndDays() {
        System.runAs(RlyTestData.admin()) {
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.forget();
            System.assertEquals(RlyHubGuard.MODE_SANDBOX, RlyHubGuard.getHubStatus().mode, 'A plain sandbox');
            String refused;
            try {
                RlySandboxSwitch.allowInSandbox(91);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('90'), 'Too many days: ' + refused);
            RlyHubGuard.HubStatus allowed = RlySandboxSwitch.allowInSandbox(2);
            System.assertEquals(RlyHubGuard.MODE_SETUP, allowed.mode, 'On, and not set up here yet: the setup screen');
            System.assertEquals(true, allowed.sandboxOverride, 'Override on');
            RLY_Notification__c rec = [SELECT Enabled__c, Channel__c, Sandbox_Allowed_Until__c FROM RLY_Notification__c LIMIT 1];
            System.assertEquals(false, rec.Enabled__c, 'Slack stays off');
            System.assert(rec.Sandbox_Allowed_Until__c < System.now().addDays(3), 'Two days');
        }
    }

    @IsTest
    static void sandboxOverrideRefusedInProductionAndForOthers() {
        String inProduction;
        System.runAs(RlyTestData.admin()) {
            try {
                RlySandboxSwitch.allowInSandbox(30);
            } catch (AuraHandledException e) {
                inProduction = e.getMessage();
            }
        }
        System.assertEquals('Only needed in a sandbox.', inProduction, 'Refused in production');
        String notAdmin;
        System.runAs(RlyTestData.plainUser()) {
            RlyHubGuard.sandboxForTest = true;
            try {
                RlySandboxSwitch.endSandboxAllowance();
            } catch (AuraHandledException e) {
                notAdmin = e.getMessage();
            }
        }
        System.assert(notAdmin != null && notAdmin.startsWith('Only Release Relay admins'), 'Admins only: ' + notAdmin);
    }
}
