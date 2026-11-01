/**
 * @description Runs after a sandbox is created or refreshed from the hub (Setup > Sandboxes > Apex Class: RlySandboxCopy).
 * The copy must not post to the team's Slack or push to the team's Git repository: it switches Slack off
 * (RLY_Notification__c Enabled__c false) and sets the Git connection's status to 'Not checked', with a note saying
 * why. It also removes everyone's assignments of Release Relay's own permission sets (RLY_Developer, RLY_Approver,
 * RLY_Deploy_Team, RLY_Slack_Site, by exact name) and keeps RLY_Admin, so only admins see the copy. RlyHubGuard
 * refuses releases in the copy as well, and its tabs only show the Guide's Set up.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier') // global is required: Salesforce calls SandboxPostCopy classes from outside the namespace.
global with sharing class RlySandboxCopy implements SandboxPostCopy {

    /** @description The note left on the Git connection and the Slack settings. */
    global static final String NOTE = 'Sandbox copy of the Release Relay hub: Slack is off, the Git connection is not checked '
        + 'and only Release Relay admins keep their permission set. Releases are raised, approved and deployed from production.';

    /** @description Added to the note when the permission sets couldn't be removed automatically. */
    global static final String REMOVE_BY_HAND = ' The permission sets RLY_Developer, RLY_Approver, RLY_Deploy_Team and RLY_Slack_Site '
        + 'could not be removed automatically: remove their assignments in Setup > Permission Sets > Manage Assignments.';

    // Release Relay's own permission sets, by exact name (RLY_Admin stays). Other sets that start with RLY_ are left alone.
    private static final Set<String> RELAY_SETS = new Set<String>{ 'RLY_Developer', 'RLY_Approver', 'RLY_Deploy_Team', 'RLY_Slack_Site' };

    /** @description Set by a test to act as if Salesforce refused the permission set DML (tests may mix DML in runAs). */
    @TestVisible
    private static Boolean refuseRemovalForTest;

    /**
     * @description Switches Slack off, marks the Git connection not checked and removes the assignments of Release
     * Relay's own permission sets except RLY_Admin in the new sandbox.
     * @param context the sandbox details from Salesforce
     */
    global void runApexClass(SandboxContext context) {
        quietCopy();
        SystemAccess access = new SystemAccess();
        try {
            access.removeAccess();
        } catch (DmlException e) {
            // Salesforce may refuse setup DML (permission set assignments) after the Slack and Git updates in one
            // transaction (MIXED_DML_OPERATION). Slack and Git stay quiet; the note asks an admin to remove the sets.
            access.noteManualRemoval();
        }
    }

    /**
     * @description Switches Slack off and marks the Git connection not checked, with the note. Also run when an admin
     * turns Release Relay on in a sandbox (RlySandboxSwitch), in case this class wasn't picked during the refresh.
     */
    public static void quietCopy() {
        new SystemAccess().quiet();
    }

    /** @description Setup records of the hub: changed in system mode, by the platform's post-copy run. */
    private without sharing class SystemAccess {

        /**
         * @description Slack off, Git connection not checked.
         */
        public void quiet() {
            List<RLY_Notification__c> slack = [SELECT Id FROM RLY_Notification__c WITH SYSTEM_MODE LIMIT 50];
            for (RLY_Notification__c s : slack) {
                s.Enabled__c = false;
                s.Last_Result__c = NOTE.left(255);
            }
            List<RLY_Git_Connection__c> gits = [SELECT Id FROM RLY_Git_Connection__c WITH SYSTEM_MODE LIMIT 50];
            for (RLY_Git_Connection__c g : gits) {
                g.Status__c = 'Not checked';
                g.Status_Message__c = NOTE;
            }
            update as system slack;
            update as system gits;
        }

        /**
         * @description Removes everyone's assignments of Release Relay's own permission sets except RLY_Admin.
         */
        public void removeAccess() {
            if (refuseRemovalForTest == true) {
                throw new DmlException('MIXED_DML_OPERATION');
            }
            List<PermissionSetAssignment> rows = [SELECT Id FROM PermissionSetAssignment
                                                  WHERE PermissionSet.Name IN :RELAY_SETS
                                                  WITH SYSTEM_MODE LIMIT 10000];
            if (!rows.isEmpty()) {
                delete as system rows;
            }
        }

        /**
         * @description Leaves a note on the Git connection that the permission sets must be removed by hand.
         */
        public void noteManualRemoval() {
            List<RLY_Git_Connection__c> gits = [SELECT Id FROM RLY_Git_Connection__c WITH SYSTEM_MODE LIMIT 50];
            for (RLY_Git_Connection__c g : gits) {
                g.Status_Message__c = NOTE + REMOVE_BY_HAND;
            }
            update as system gits;
        }
    }
}
