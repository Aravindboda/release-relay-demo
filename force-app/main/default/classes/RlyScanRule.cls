/**
 * @description Whether a release runs the code scan. The Git connection's switch (Code_Scan__c) is the default; each
 * target org can follow it (RLY_Org__c.Code_Scan__c Follow, the default), always scan (On) or not scan (Off), so orgs
 * that don't need a scan move faster. Admins set it on the Pipeline tab (org card, Approval section).
 */
public with sharing class RlyScanRule {

    /** @description The org follows the Git connection's switch (the default). */
    public static final String FOLLOW = 'Follow';
    /** @description Releases into the org are always scanned. */
    public static final String ALWAYS_SCAN = 'On';
    /** @description Releases into the org are never scanned. */
    public static final String NO_SCAN = 'Off';
    /** @description Every choice, in the order the page shows them. */
    public static final List<String> CHOICES = new List<String>{ FOLLOW, ALWAYS_SCAN, NO_SCAN };

    private static final String PENDING = 'Pending';
    private static final String NOT_CONFIGURED = 'Not configured';
    private static final String FIELD = 'Code_Scan__c';
    private static final String TARGET_RELATION = 'Target_Org__r';
    private static final String TARGET_FIELD = 'Target_Org__c';

    /**
     * @description Whether releases into the target org are scanned.
     * @param conn the Git connection, or null
     * @param target the release's target org, or null (then the connection decides)
     * @return true when the scan runs
     */
    public static Boolean isOn(RLY_Git_Connection__c conn, RLY_Org__c target) {
        String choice = choiceOf(target);
        if (choice == ALWAYS_SCAN) {
            return true;
        }
        if (choice == NO_SCAN) {
            return false;
        }
        return conn != null && conn.Code_Scan__c == true;
    }

    /**
     * @description The scan status a release starts its checks with.
     * @param conn the Git connection, or null
     * @param target the release's target org, or null
     * @return Pending when the scan runs, otherwise Not configured
     */
    public static String statusFor(RLY_Git_Connection__c conn, RLY_Org__c target) {
        return isOn(conn, target) ? PENDING : NOT_CONFIGURED;
    }

    /**
     * @description The org's choice: Follow, On or Off. A record read without the field, or without a value, follows.
     * @param target the org, or null
     * @return the choice
     */
    public static String choiceOf(RLY_Org__c target) {
        Object value = target == null ? null : target.getPopulatedFieldsAsMap().get(FIELD);
        String choice = value == null ? null : String.valueOf(value);
        return CHOICES.contains(choice) ? choice : FOLLOW;
    }

    /**
     * @description A release's target org with its choice: the related record when the release was read with it,
     * otherwise the org read again (a release built in memory, or read without Target_Org__r.Code_Scan__c).
     * @param rel the release
     * @return the target org, or null when the release has none
     */
    public static RLY_Org__c targetOf(RLY_Release__c rel) {
        Map<String, Object> fields = rel == null ? new Map<String, Object>() : rel.getPopulatedFieldsAsMap();
        RLY_Org__c related = (RLY_Org__c) fields.get(TARGET_RELATION);
        if (related != null && related.getPopulatedFieldsAsMap().containsKey(FIELD)) {
            return related;
        }
        Id targetId = (Id) fields.get(TARGET_FIELD);
        return targetId == null ? related : RlyReleaseStore.org(targetId);
    }
}
