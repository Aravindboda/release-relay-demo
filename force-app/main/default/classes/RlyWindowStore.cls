/**
 * @description Reads and saves orgs' release windows (RlyReleaseWindow): the org fields Window_Days__c, Window_From__c,
 * Window_To__c, Window_Time_Zone__c and Window_Freezes__c. Orgs are shared hub records: read in system mode; saved only
 * after the caller checked the user is a Release Relay admin.
 */
public with sharing class RlyWindowStore {

    /**
     * @description An org with its window.
     * @param orgId the org
     * @return the org, or null
     */
    public static RLY_Org__c org(Id orgId) {
        return orgId == null ? null : new SystemAccess().org(orgId);
    }

    /**
     * @description The orgs releases deploy into (stages, the hub, back promote orgs), with their windows.
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> deployOrgs() {
        return new SystemAccess().deployOrgs();
    }

    /**
     * @description Saves an org's window fields.
     * @param row the org's Id and window fields
     */
    public static void save(RLY_Org__c row) {
        new SystemAccess().save(row);
    }

    /** @description Org rows in system mode. */
    private without sharing class SystemAccess {
        /**
         * @description An org with its window.
         * @param orgId the org
         * @return the org, or null
         */
        public RLY_Org__c org(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, Branch__c, Window_Days__c, Window_From__c, Window_To__c,
                                            Window_Time_Zone__c, Window_Freezes__c
                                     FROM RLY_Org__c WHERE Id = :orgId WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The orgs releases deploy into.
         * @return the orgs
         */
        public List<RLY_Org__c> deployOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Window_Days__c, Window_From__c, Window_To__c, Window_Time_Zone__c,
                           Window_Freezes__c
                    FROM RLY_Org__c WHERE Role__c IN ('Stage', 'Hub', 'Back_Promote') WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Updates the org.
         * @param row the org
         */
        public void save(RLY_Org__c row) {
            Database.update(row, true, AccessLevel.SYSTEM_MODE);
        }
    }
}
