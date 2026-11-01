/**
 * @description Keeps a sandbox copy of the hub from acting as the hub. The hub is the org whose Id is on the RLY_Org__c
 * record with Role__c 'Hub' (Org_Id__c, saved by its sign-in check). Before that record has an Org Id (first-time
 * setup) every org counts as the hub. A sandbox made from production carries the records, so its own Org Id differs:
 * actions that call out or change a release (raise, approve, reject, check again, resolve, promote, sync, check off a
 * manual step, sign-in checks, pipeline dispatch, Slack, pipeline files, branches) are refused there, and the status
 * reader only reads. Pages still load. The answer is kept for the transaction.
 */
public with sharing class RlyHubGuard {

    /** @description Why an action is refused in a copy. */
    public static final String COPY_MESSAGE = 'This is a copy of the Release Relay hub (sandbox), not production. '
        + 'Releases can\'t be raised, approved or deployed here.';

    @TestVisible
    private static Boolean known;

    /** @description What the pages show: a copy of the hub, and why actions are off. */
    public class HubStatus {
        /** @description True in a copy of the hub (a sandbox made from it). */
        @AuraEnabled public Boolean isHubCopy;
        /** @description The banner text, or null on the hub. */
        @AuraEnabled public String message;
    }

    /**
     * @description Whether this org is the hub (or no hub Org Id is known yet).
     * @return true on the hub
     */
    public static Boolean isHub() {
        if (known == null) {
            String hubOrgId = new SystemAccess().hubOrgId();
            known = String.isBlank(hubOrgId) || sameOrg(hubOrgId, UserInfo.getOrganizationId());
        }
        return known;
    }

    /**
     * @description Refuses the action in a copy of the hub.
     */
    public static void requireHub() {
        if (!isHub()) {
            AuraHandledException e = new AuraHandledException(COPY_MESSAGE);
            e.setMessage(COPY_MESSAGE);
            throw e;
        }
    }

    /**
     * @description For every tab: whether this is a copy of the hub, and the banner text.
     * @return the status
     */
    @AuraEnabled(cacheable=true)
    public static HubStatus getHubStatus() {
        HubStatus s = new HubStatus();
        s.isHubCopy = !isHub();
        s.message = s.isHubCopy ? COPY_MESSAGE : null;
        return s;
    }

    // 15- and 18-character Ids of the same org match (the first 15 characters are case-sensitive).
    private static Boolean sameOrg(String saved, String current) {
        String a = saved.trim();
        return a.length() >= 15 && current.length() >= 15 && a.left(15).equals(current.left(15));
    }

    /** @description The hub record is a shared hub record: read in system mode. */
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
    }
}
