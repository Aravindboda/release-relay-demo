/**
 * @description Reads and saves data sets (RLY_Data_Set__c) and their runs (RLY_Data_Run__c), and the orgs a run can use.
 * Release Relay's own records: read and written in system mode (the controller decides who may do what).
 */
public with sharing class RlyDataStore {

    /** @description Run Status__c: the hub is sending a developer org's records to Git. */
    public static final String EXPORTING = 'Exporting';
    /** @description Run Status__c: the pipeline is reading both orgs (no change). */
    public static final String DRY_RUN = 'Dry run';
    /** @description Run Status__c: the dry run passed; the load waits for a person. */
    public static final String READY = 'Ready';
    /** @description Run Status__c: the dry run found duplicates or records without a key. */
    public static final String BLOCKED = 'Blocked';
    /** @description Run Status__c: the pipeline is loading. */
    public static final String LOADING = 'Loading';
    /** @description Run Status__c: loaded. */
    public static final String LOADED = 'Loaded';
    /** @description Run Status__c: failed. */
    public static final String FAILED = 'Failed';

    /**
     * @description The data sets, by title.
     * @return the sets
     */
    public static List<RLY_Data_Set__c> sets() {
        return new SystemAccess().sets();
    }

    /**
     * @description One data set.
     * @param setId the set
     * @return the set, or null
     */
    public static RLY_Data_Set__c setById(Id setId) {
        List<RLY_Data_Set__c> rows = new SystemAccess().setById(setId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves a data set (insert or update).
     * @param row the set
     * @return its Id
     */
    public static Id saveSet(RLY_Data_Set__c row) {
        return new SystemAccess().saveSet(row);
    }

    /**
     * @description Deletes a data set (its runs keep their counts; the lookup is cleared).
     * @param setId the set
     */
    public static void deleteSet(Id setId) {
        new SystemAccess().deleteSet(setId);
    }

    /**
     * @description The latest runs, newest first.
     * @param max how many
     * @return the runs
     */
    public static List<RLY_Data_Run__c> runs(Integer max) {
        return new SystemAccess().runs(max);
    }

    /**
     * @description One run by its id (DAT-…).
     * @param runId the run id
     * @return the run, or null
     */
    public static RLY_Data_Run__c run(String runId) {
        List<RLY_Data_Run__c> rows = new SystemAccess().runByKey(runId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves a run by its id (upsert on Run_Id__c).
     * @param row the run (only the fields set are written)
     */
    public static void saveRun(RLY_Data_Run__c row) {
        new SystemAccess().saveRun(row);
    }

    /**
     * @description Removes runs started before a moment (retention).
     * @param cutoff the moment
     * @param perCall the most rows
     * @return how many were removed
     */
    public static Integer removeOlderThan(Datetime cutoff, Integer perCall) {
        return new SystemAccess().removeOlderThan(cutoff, perCall);
    }

    /**
     * @description The registered orgs a run can use (with a branch or the hub), by name.
     * @return the orgs
     */
    public static List<RLY_Org__c> orgs() {
        return new SystemAccess().orgs();
    }

    /** @description Release Relay's own records in system mode. */
    private without sharing class SystemAccess {
        /**
         * @description The sets.
         * @return the sets
         */
        public List<RLY_Data_Set__c> sets() {
            return [SELECT Id, Name, Title__c, Description__c, Definition__c, LastModifiedDate FROM RLY_Data_Set__c
                    WITH SYSTEM_MODE ORDER BY Title__c LIMIT 200];
        }

        /**
         * @description One set.
         * @param setId the set
         * @return the rows
         */
        public List<RLY_Data_Set__c> setById(Id setId) {
            return [SELECT Id, Name, Title__c, Description__c, Definition__c FROM RLY_Data_Set__c WHERE Id = :setId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Saves a set.
         * @param row the set
         * @return its Id
         */
        public Id saveSet(RLY_Data_Set__c row) {
            Database.upsert(row, true, AccessLevel.SYSTEM_MODE);
            return row.Id;
        }

        /**
         * @description Deletes a set.
         * @param setId the set
         */
        public void deleteSet(Id setId) {
            Database.delete(new RLY_Data_Set__c(Id = setId), true, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description The latest runs.
         * @param max how many
         * @return the runs
         */
        public List<RLY_Data_Run__c> runs(Integer max) {
            return [SELECT Id, Name, Run_Id__c, Data_Set__c, Data_Set__r.Title__c, Direction__c, Source_Org__c, Source_Org__r.Name,
                           Target_Org__c, Target_Org__r.Name, Target_Org_Id__c, Release__c, Release__r.Name, Status__c, Token__c, Mask__c,
                           Requested_By__c, Requested_By__r.Name, Approved_By__r.Name, Approved_On__c, Checked_At__c, Counts__c,
                           Message__c, Run_Url__c, Run_Title__c
                    FROM RLY_Data_Run__c WITH SYSTEM_MODE ORDER BY Checked_At__c DESC LIMIT :max];
        }

        /**
         * @description One run.
         * @param runId the run id
         * @return the rows
         */
        public List<RLY_Data_Run__c> runByKey(String runId) {
            return [SELECT Id, Name, Run_Id__c, Data_Set__c, Data_Set__r.Title__c, Data_Set__r.Definition__c, Direction__c,
                           Source_Org__c, Target_Org__c, Target_Org_Id__c, Release__c, Status__c, Token__c, Mask__c, Requested_By__c,
                           Approved_By__c, Checked_At__c, Counts__c, Summary__c, Message__c, Run_Url__c, Run_Title__c
                    FROM RLY_Data_Run__c WHERE Run_Id__c = :runId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Upserts a run by Run_Id__c.
         * @param row the run
         */
        public void saveRun(RLY_Data_Run__c row) {
            Database.upsert(row, RLY_Data_Run__c.Run_Id__c, true, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description Deletes old runs.
         * @param cutoff the moment
         * @param perCall the most rows
         * @return how many
         */
        public Integer removeOlderThan(Datetime cutoff, Integer perCall) {
            List<RLY_Data_Run__c> rows = [SELECT Id FROM RLY_Data_Run__c WHERE Checked_At__c < :cutoff
                                          WITH SYSTEM_MODE ORDER BY Checked_At__c LIMIT :perCall];
            if (!rows.isEmpty()) {
                Database.delete(rows, true, AccessLevel.SYSTEM_MODE);
            }
            return rows.size();
        }

        /**
         * @description The orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Git_Environment__c, Stage_Order__c, Status__c, Org_Id__c
                    FROM RLY_Org__c WHERE Role__c IN ('Developer', 'Stage', 'Hub') WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }
    }
}
