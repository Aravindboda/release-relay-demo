/**
 * @description Sync status (RlySync*): reads and saves the checks (RLY_Sync_Check__c) and the orgs the tab shows. The
 * checks are shared hub records: read and written in system mode after the controller's permission checks.
 */
public with sharing class RlySyncStore {

    /** @description Org: an org against its own branch. */
    public static final String KIND_ORG = 'Org';
    /** @description Route: each branch against the one below it. */
    public static final String KIND_ROUTE = 'Route';
    /** @description Packages: the managed packages installed in each org. */
    public static final String KIND_PACKAGES = 'Packages';
    /** @description A check whose run is going. */
    public static final String RUNNING = 'Running';
    /** @description A check with its result. */
    public static final String SUCCEEDED = 'Succeeded';
    /** @description A check that couldn't finish. */
    public static final String FAILED = 'Failed';

    /**
     * @description The newest checks (newest first), for the cards.
     * @return up to 200 checks
     */
    public static List<RLY_Sync_Check__c> latest() {
        return new SystemAccess().latest();
    }

    /**
     * @description A check by its id.
     * @param syncId SYN- and 13 digits
     * @return the check, or null
     */
    public static RLY_Sync_Check__c bySyncId(String syncId) {
        List<RLY_Sync_Check__c> rows = new SystemAccess().bySyncId(syncId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves a check (by its Sync_Id__c).
     * @param check the check
     */
    public static void save(RLY_Sync_Check__c check) {
        new SystemAccess().save(check);
    }

    /**
     * @description The registered orgs the tab compares: developer orgs, stages and the hub, with their branches.
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> orgs() {
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        for (RLY_Org__c o : RlyReleaseStore.pipelineOrgs(new Set<String>{ 'Developer', 'Stage', 'Hub' })) {
            if (o.Branch__c != null) {
                out.add(o);
            }
        }
        return out;
    }

    /**
     * @description Removes checks started before a moment (the nightly archive's retention).
     * @param cutoff the moment
     * @param perCall the most rows in one call
     * @return how many were removed
     */
    public static Integer removeOlderThan(Datetime cutoff, Integer perCall) {
        return new SystemAccess().removeOlderThan(cutoff, perCall);
    }

    /** @description Sync checks and orgs in system mode. */
    private without sharing class SystemAccess {
        /**
         * @description The newest checks.
         * @return the checks
         */
        public List<RLY_Sync_Check__c> latest() {
            return [SELECT Id, Sync_Id__c, Kind__c, Org__c, Branch__c, Token__c, Status__c, Counts__c, Checked_At__c, Run_Url__c,
                           Run_Title__c, Message__c
                    FROM RLY_Sync_Check__c WITH SYSTEM_MODE ORDER BY Checked_At__c DESC NULLS LAST LIMIT 200];
        }

        /**
         * @description One check by its id.
         * @param syncId the id
         * @return the rows
         */
        public List<RLY_Sync_Check__c> bySyncId(String syncId) {
            return [SELECT Id, Sync_Id__c, Kind__c, Org__c, Branch__c, Token__c, Status__c, Counts__c, Checked_At__c, Run_Url__c,
                           Run_Title__c, Message__c, Summary__c
                    FROM RLY_Sync_Check__c WHERE Sync_Id__c = :syncId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Upserts a check by its id.
         * @param check the check
         */
        public void save(RLY_Sync_Check__c check) {
            Database.upsert(check, RLY_Sync_Check__c.Sync_Id__c, true, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description Deletes old checks.
         * @param cutoff the moment
         * @param perCall the most rows
         * @return how many
         */
        public Integer removeOlderThan(Datetime cutoff, Integer perCall) {
            List<RLY_Sync_Check__c> rows = [SELECT Id FROM RLY_Sync_Check__c WHERE Checked_At__c < :cutoff
                                            WITH SYSTEM_MODE ORDER BY Checked_At__c LIMIT :perCall];
            if (!rows.isEmpty()) {
                Database.delete(rows, true, AccessLevel.SYSTEM_MODE);
            }
            return rows.size();
        }
    }
}
