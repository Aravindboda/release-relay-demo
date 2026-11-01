/**
 * @description Release Relay runs only in production, which becomes the hub. The hub is the org whose Id is on the
 * RLY_Org__c record with Role__c 'Hub' (Org_Id__c, saved by its sign-in check). Before that record has an Org Id
 * (first-time setup) a production org counts as the hub. A sandbox never does: a sandbox made from production carries
 * the records (a copy of the hub), and a sandbox where the package is installed with no hub configured only shows how
 * to set up in production. Actions that call out or change a release (raise, approve, reject, check again, resolve,
 * promote, sync, check off a manual step, sign-in checks, pipeline dispatch, Slack, pipeline files, branches) are
 * refused outside the hub, and the status reader only reads. The pages ask getHubStatus which mode the org is in:
 * 'hub', 'setup' (production not set up yet), 'sandbox' or 'copy'. Answers are kept for the transaction.
 * Admin override: an admin can turn Release Relay on in a sandbox for a while (RlySandboxSwitch). It counts only while
 * the saved Org Id is this org's and the end date is in the future; a refresh changes the Org Id, so it stops counting.
 * Tests run in production and in a sandbox (the compile check): while a test runs the org counts as production unless
 * the test sets sandboxForTest.
 */
public with sharing class RlyHubGuard {

    /** @description Why an action is refused in a copy. */
    public static final String COPY_MESSAGE = 'This is a copy of the Release Relay hub (sandbox), not production. '
        + 'Releases can\'t be raised, approved or deployed here.';

    /** @description Why an action is refused in a sandbox with no hub configured. */
    public static final String SANDBOX_MESSAGE = 'Release Relay runs only in production, which becomes the hub. '
        + 'Install it there and follow Set up in the Guide: connect Git, register this sandbox as an org on the route.';

    /** @description What production shows before setup is finished. */
    public static final String SETUP_MESSAGE = 'An admin finishes Set up on the Pipeline tab first: this org as the hub, '
        + 'the Git connection, pipeline files, orgs, Slack (optional).';

    /** @description Mode of the hub itself. */
    public static final String MODE_HUB = 'hub';
    /** @description Mode of production before setup is finished. */
    public static final String MODE_SETUP = 'setup';
    /** @description Mode of a sandbox with no hub configured. */
    public static final String MODE_SANDBOX = 'sandbox';
    /** @description Mode of a sandbox copy of the hub. */
    public static final String MODE_COPY = 'copy';

    private static final String COPY_TITLE = 'This is a sandbox copy of the Release Relay hub';
    private static final String SANDBOX_TITLE = 'This org is a sandbox';
    private static final String SETUP_TITLE = 'Release Relay isn\'t set up yet';

    @TestVisible
    private static Boolean known;

    /** @description Set true by a test that runs this org as a sandbox; otherwise tests run as production. */
    @TestVisible
    private static Boolean sandboxForTest;

    private static final String SLACK_RECORD = 'Slack';

    private static Boolean sandboxKnown;
    private static String savedHubOrgId;
    private static RLY_Notification__c allowance;

    /** @description What the pages show: which mode this org is in, and why actions are off. */
    public class HubStatus {
        /** @description 'hub', 'setup', 'sandbox' or 'copy'. */
        @AuraEnabled public String mode;
        /** @description True in any sandbox. */
        @AuraEnabled public Boolean isSandbox;
        /** @description True in production before setup is finished (no hub registered or no Git connection). */
        @AuraEnabled public Boolean needsSetup;
        /** @description True when actions are off: in a copy of the hub and in any other sandbox. */
        @AuraEnabled public Boolean isHubCopy;
        /** @description The notice title, or null on the hub. */
        @AuraEnabled public String title;
        /** @description The notice text, or null on the hub. */
        @AuraEnabled public String message;
        /** @description True while an admin's override turns Release Relay on in this sandbox. */
        @AuraEnabled public Boolean sandboxOverride;
        /** @description The info line every tab shows while the override is on, or null. */
        @AuraEnabled public String overrideNote;
    }

    /**
     * @description Whether this org is the hub: production, and its Id is the hub's Org Id (or none is known yet).
     * @return true on the hub
     */
    public static Boolean isHub() {
        if (known == null) {
            SystemAccess access = new SystemAccess();
            savedHubOrgId = access.hubOrgId();
            allowance = isSandbox() ? access.readAllowance() : null;
            known = allows(allowance) || (!isSandbox()
                && (String.isBlank(savedHubOrgId) || sameOrg(savedHubOrgId, UserInfo.getOrganizationId())));
        }
        return known;
    }

    /**
     * @description Whether this org is a sandbox. While a test runs: only when the test sets sandboxForTest.
     * @return true in a sandbox
     */
    public static Boolean isSandbox() {
        if (Test.isRunningTest()) {
            return sandboxForTest == true;
        }
        if (sandboxKnown == null) {
            sandboxKnown = organizationSaysSandbox();
        }
        return sandboxKnown;
    }

    /**
     * @description Reads IsSandbox from the Organization record (what isSandbox uses outside tests).
     * @return true in a sandbox
     */
    @TestVisible
    private static Boolean organizationSaysSandbox() {
        return new SystemAccess().orgIsSandbox();
    }

    /**
     * @description Forgets the answers kept for this transaction (after the sandbox override changes).
     */
    public static void forget() {
        known = null;
        sandboxKnown = null;
    }

    /**
     * @description Refuses the action outside the hub (a copy of the hub, or another sandbox).
     */
    public static void requireHub() {
        if (!isHub()) {
            String why = noHubOrgId() ? SANDBOX_MESSAGE : COPY_MESSAGE;
            AuraHandledException e = new AuraHandledException(why);
            e.setMessage(why);
            throw e;
        }
    }

    /**
     * @description For every tab: the org's mode, and the notice title and text.
     * @return the status
     */
    // Not cacheable: the browser must not keep an old mode after setup finishes or the sandbox override changes.
    @AuraEnabled
    public static HubStatus getHubStatus() {
        HubStatus s = new HubStatus();
        s.isSandbox = isSandbox();
        s.isHubCopy = !isHub();
        s.sandboxOverride = allows(allowance);
        s.overrideNote = s.sandboxOverride ? overrideText(allowance) : null;
        s.needsSetup = !s.isHubCopy && RlySetupStatus.getSetupStatus().needsSetup;
        if (s.isHubCopy) {
            Boolean plainSandbox = noHubOrgId();
            s.mode = plainSandbox ? MODE_SANDBOX : MODE_COPY;
            s.title = plainSandbox ? SANDBOX_TITLE : COPY_TITLE;
            s.message = plainSandbox ? SANDBOX_MESSAGE : COPY_MESSAGE;
        } else if (s.needsSetup) {
            s.mode = MODE_SETUP;
            s.title = SETUP_TITLE;
            s.message = SETUP_MESSAGE;
        } else {
            s.mode = MODE_HUB;
        }
        return s;
    }

    // No hub Org Id is saved (read together with isHub, so both answers come from the same query).
    private static Boolean noHubOrgId() {
        isHub();
        return String.isBlank(savedHubOrgId);
    }

    // The override counts only for this org's Id and until its end date.
    private static Boolean allows(RLY_Notification__c row) {
        return row != null && String.isNotBlank(row.Sandbox_Allowed_Org_Id__c) && row.Sandbox_Allowed_Until__c != null
            && row.Sandbox_Allowed_Until__c > System.now() && sameOrg(row.Sandbox_Allowed_Org_Id__c, UserInfo.getOrganizationId());
    }

    private static String overrideText(RLY_Notification__c row) {
        String who = row.Sandbox_Allowed_By__r == null ? 'an admin' : row.Sandbox_Allowed_By__r.Name;
        return 'Release Relay is on in this sandbox until ' + row.Sandbox_Allowed_Until__c.format('d MMM yyyy') + ', turned on by '
            + who + '. Slack and Git stay off until an admin reconnects them.';
    }

    // 15- and 18-character Ids of the same org match (the first 15 characters are case-sensitive).
    private static Boolean sameOrg(String saved, String current) {
        String a = saved.trim();
        return a.length() >= 15 && current.length() >= 15 && a.left(15).equals(current.left(15));
    }

    /** @description The hub record and the Organization record are read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description The Org Id on the hub's record.
         * @return the Org Id, or null when there's none yet
         */
        public String hubOrgId() {
            List<RLY_Org__c> rows = [SELECT Org_Id__c FROM RLY_Org__c WHERE Role__c = 'Hub' AND Org_Id__c != null
                                     WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0].Org_Id__c;
        }

        /**
         * @description The admin override saved on the Slack settings record.
         * @return the record, or null when there's none
         */
        public RLY_Notification__c readAllowance() {
            List<RLY_Notification__c> rows = [SELECT Sandbox_Allowed_Org_Id__c, Sandbox_Allowed_Until__c, Sandbox_Allowed_By__r.Name
                                              FROM RLY_Notification__c WHERE Channel__c = :SLACK_RECORD
                                              WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Whether this org is a sandbox.
         * @return the Organization record's IsSandbox
         */
        public Boolean orgIsSandbox() {
            List<Organization> rows = [SELECT IsSandbox FROM Organization WITH SYSTEM_MODE LIMIT 1];
            return !rows.isEmpty() && rows[0].IsSandbox;
        }
    }
}
