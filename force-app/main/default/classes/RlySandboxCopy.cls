/**
 * @description Runs after a sandbox is created or refreshed from the hub (Setup > Sandboxes > Apex Class: RlySandboxCopy).
 * The copy must not post to the team's Slack or push to the team's Git repository: it switches Slack off
 * (RLY_Notification__c Enabled__c false) and sets the Git connection's status to 'Not checked', with a note saying
 * why. RlyHubGuard refuses releases in the copy as well.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier') // global is required: Salesforce calls SandboxPostCopy classes from outside the namespace.
global with sharing class RlySandboxCopy implements SandboxPostCopy {

    /** @description The note left on the Git connection and the Slack settings. */
    global static final String NOTE = 'Sandbox copy of the Release Relay hub: Slack is off and the Git connection is not checked. '
        + 'Releases are raised, approved and deployed from production.';

    /**
     * @description Switches Slack off and marks the Git connection not checked in the new sandbox.
     * @param context the sandbox details from Salesforce
     */
    global void runApexClass(SandboxContext context) {
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
    }
}
