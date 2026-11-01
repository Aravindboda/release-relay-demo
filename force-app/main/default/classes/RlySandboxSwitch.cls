/**
 * @description Admin override "Turn Release Relay on in this sandbox". Release Relay runs only in production; in a sandbox
 * an admin can turn it on for 1 to 90 days (30 by default). The override is saved on the Slack settings record
 * (Sandbox_Allowed_Org_Id__c, Sandbox_Allowed_By__c, Sandbox_Allowed_Until__c) and RlyHubGuard counts it only for this
 * org's Id and until the end date, so a refresh resets it. Turning it on first does what the post-copy class
 * RlySandboxCopy does (Slack off, Git connection not checked), in case that class wasn't picked during the refresh;
 * Slack and Git stay off until an admin reconnects them. Refused in production and for users without RLY_Admin.
 */
public with sharing class RlySandboxSwitch {

    private static final Integer DEFAULT_DAYS = 30;
    private static final Integer MAX_DAYS = 90;
    private static final String ONLY_SANDBOX = 'Only needed in a sandbox.';
    private static final String ONLY_ADMINS = 'Only Release Relay admins can turn Release Relay on or off in a sandbox.';
    private static final String DAYS_RANGE = 'Pick 1 to 90 days.';

    /**
     * @description Turns Release Relay on in this sandbox for a number of days, after switching Slack and Git off.
     * @param days 1 to 90; blank means 30
     * @return the org's status afterwards
     */
    @AuraEnabled
    public static RlyHubGuard.HubStatus allowInSandbox(Integer days) {
        requireSandboxAdmin();
        Integer span = days == null ? DEFAULT_DAYS : days;
        if (span < 1 || span > MAX_DAYS) {
            throw RlySlackController.auraError(DAYS_RANGE);
        }
        RlySandboxCopy.quietCopy();
        RLY_Notification__c saved = RlySlack.settings();
        RLY_Notification__c row = saved == null
            ? new RLY_Notification__c(Name = RlySlack.CHANNEL, Channel__c = RlySlack.CHANNEL, Enabled__c = false)
            : new RLY_Notification__c(Id = saved.Id);
        row.Sandbox_Allowed_Org_Id__c = UserInfo.getOrganizationId();
        row.Sandbox_Allowed_By__c = UserInfo.getUserId();
        row.Sandbox_Allowed_Until__c = System.now().addDays(span);
        new SystemAccess().save(row);
        RlyHubGuard.forget();
        return RlyHubGuard.getHubStatus();
    }

    /**
     * @description Turns the override off: this sandbox shows only the notice and the Guide's Set up again.
     * @return the org's status afterwards
     */
    @AuraEnabled
    public static RlyHubGuard.HubStatus endSandboxAllowance() {
        requireSandboxAdmin();
        RLY_Notification__c saved = RlySlack.settings();
        if (saved != null) {
            new SystemAccess().save(new RLY_Notification__c(Id = saved.Id, Sandbox_Allowed_Org_Id__c = null,
                Sandbox_Allowed_By__c = null, Sandbox_Allowed_Until__c = null));
        }
        RlyHubGuard.forget();
        return RlyHubGuard.getHubStatus();
    }

    private static void requireSandboxAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw RlySlackController.auraError(ONLY_ADMINS);
        }
        if (!RlyHubGuard.isSandbox()) {
            throw RlySlackController.auraError(ONLY_SANDBOX);
        }
    }

    /** @description The Slack settings record is hub configuration: written in system mode after the admin check. */
    private without sharing class SystemAccess {

        /**
         * @description Inserts or updates the settings record.
         * @param row the fields to save
         */
        public void save(RLY_Notification__c row) {
            upsert as system row;
        }
    }
}
