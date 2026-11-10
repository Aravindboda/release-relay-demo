/**
 * @description Reads and writes for the pipeline runs (RLY_Pipeline_Run__c): the inbound endpoint's lookup and upsert by
 * Run_Id__c, the Pipeline Monitor's Git connections and the nightly archive's removal of old runs. The monitor's run
 * lists are in RlyRunMonitorQueries and the releases in RlyRunMonitorReleases. Runs, releases and connections are shared
 * hub records: read and written in system mode in the private inner without sharing class.
 */
public with sharing class RlyRunMonitorStore {

    /** @description Statuses of a run that is still going. */
    public static final Set<String> ACTIVE = new Set<String>{ 'Queued', 'In progress' };


    /**
     * @description A run by its key.
     * @param runKey the GitHub run id and attempt
     * @return the run, or null
     */
    public static RLY_Pipeline_Run__c byRunKey(String runKey) {
        return String.isBlank(runKey) ? null : new SystemAccess().byRunKey(runKey);
    }

    /**
     * @description Saves a run, matching an existing row by Run_Id__c.
     * @param row the run (Run_Id__c set)
     * @return the saved row's Id
     */
    public static Id save(RLY_Pipeline_Run__c row) {
        return new SystemAccess().save(row);
    }

    /**
     * @description The finished-green attempts of a GitHub run (its key starts with the run id).
     * @param githubRunId the GitHub run id (digits)
     * @return the runs
     */
    public static List<RLY_Pipeline_Run__c> succeededAttempts(String githubRunId) {
        return String.isBlank(githubRunId) || !githubRunId.isNumeric() ? new List<RLY_Pipeline_Run__c>()
            : new SystemAccess().succeededAttempts(githubRunId + '-%');
    }

    /**
     * @description Saves runs that already exist (by Id).
     * @param rows the runs
     */
    public static void updateAll(List<RLY_Pipeline_Run__c> rows) {
        if (!rows.isEmpty()) {
            new SystemAccess().updateAll(rows);
        }
    }

    /**
     * @description The hub's Git connections, oldest first.
     * @return the connections
     */
    public static List<RLY_Git_Connection__c> connections() {
        return new SystemAccess().connections();
    }

    /**
     * @description Deletes runs started before a moment (the nightly archive), at most max per call, and empties the
     * Recycle Bin for them.
     * @param cutoff the moment (now minus the Retention days)
     * @param max how many at most
     * @return how many were deleted
     */
    public static Integer removeOlderThan(Datetime cutoff, Integer max) {
        return cutoff == null ? 0 : new SystemAccess().removeOlderThan(cutoff, max);
    }

    /** @description Runs, releases and connections are shared hub records: read and written in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description A run by its key.
         * @param runKey the key
         * @return the run, or null
         */
        public RLY_Pipeline_Run__c byRunKey(String runKey) {
            List<RLY_Pipeline_Run__c> rows = [SELECT Id, Run_Id__c, Status__c, Started__c, Finished__c, Duration_Seconds__c
                                              FROM RLY_Pipeline_Run__c WHERE Run_Id__c = :runKey WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Upserts a run by Run_Id__c.
         * @param row the run
         * @return its Id
         */
        public Id save(RLY_Pipeline_Run__c row) {
            Database.UpsertResult r = Database.upsert(row, RLY_Pipeline_Run__c.Run_Id__c, true, AccessLevel.SYSTEM_MODE);
            return r.getId();
        }

        /**
         * @description Succeeded runs whose key matches a pattern.
         * @param keyPattern the run id and a wildcard
         * @return the runs
         */
        public List<RLY_Pipeline_Run__c> succeededAttempts(String keyPattern) {
            return [SELECT Id, Run_Id__c, Status__c, Failure_Message__c FROM RLY_Pipeline_Run__c
                    WHERE Run_Id__c LIKE :keyPattern AND Status__c = 'Succeeded' WITH SYSTEM_MODE LIMIT 20];
        }

        /**
         * @description Updates runs.
         * @param rows the runs
         */
        public void updateAll(List<RLY_Pipeline_Run__c> rows) {
            Database.update(rows, true, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description The Git connections.
         * @return the connections, oldest first
         */
        public List<RLY_Git_Connection__c> connections() {
            return [SELECT Id, Provider__c, Repository__c FROM RLY_Git_Connection__c WITH SYSTEM_MODE
                    ORDER BY CreatedDate ASC LIMIT 20];
        }

        /**
         * @description Deletes runs started before a moment and empties the Recycle Bin for them.
         * @param cutoff the moment
         * @param max how many at most
         * @return how many were deleted
         */
        public Integer removeOlderThan(Datetime cutoff, Integer max) {
            List<RLY_Pipeline_Run__c> rows = [SELECT Id FROM RLY_Pipeline_Run__c WHERE Started__c < :cutoff
                                              WITH SYSTEM_MODE ORDER BY Started__c ASC LIMIT :max];
            if (rows.isEmpty()) {
                return 0;
            }
            Database.delete(rows, true, AccessLevel.SYSTEM_MODE);
            Database.emptyRecycleBin(rows);
            return rows.size();
        }
    }
}
