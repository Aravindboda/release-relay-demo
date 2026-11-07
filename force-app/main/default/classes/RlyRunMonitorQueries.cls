/**
 * @description The Pipeline Monitor's run lists (RLY_Pipeline_Run__c): runs still going, finished runs page by page
 * (newest first, after a cursor), runs started since a moment (the lanes and branches) and counts of runs that ended
 * today. A repository filter keeps the runs whose GitHub address (Run_Url__c) is in that repository. Runs are shared
 * hub records: read in system mode in the private inner without sharing class, with every value passed as a bind.
 */
public with sharing class RlyRunMonitorQueries {

    private static final String FIELDS = 'Id, Run_Id__c, Workflow_Step__c, Mode__c, Branch__c, Target_Org__c, Status__c, '
        + 'Started__c, Finished__c, Duration_Seconds__c, Actor__c, Run_Url__c, Release__c, Release__r.Name, '
        + 'Release__r.Title__c, Release__r.Source_Org__c, Request_Id__c, Failure_Message__c, Steps__c';
    private static final Integer MAX_ACTIVE = 200;

    /** @description Where a page of finished runs starts: after the oldest run shown. */
    public class Cursor {
        /** @description The oldest shown run's start, or null for the newest runs. */
        public Datetime started;
        /** @description The oldest shown run's record (ties on the start), or null. */
        public Id recordId;
    }

    /**
     * @description Every queued or in progress run, newest first.
     * @param repository the repository filter, or null
     * @return the runs
     */
    public static List<RLY_Pipeline_Run__c> active(String repository) {
        Map<String, Object> binds = baseBinds(repository);
        binds.put('statuses', RlyRunMonitorStore.ACTIVE);
        binds.put('max', MAX_ACTIVE);
        return new SystemAccess().query('Status__c IN :statuses', binds);
    }

    /**
     * @description Finished runs, newest first, after a cursor (or the newest when it has no start).
     * @param repository the repository filter, or null
     * @param after the cursor, or null
     * @param max how many
     * @return the runs
     */
    public static List<RLY_Pipeline_Run__c> finished(String repository, Cursor after, Integer max) {
        Map<String, Object> binds = baseBinds(repository);
        binds.put('statuses', RlyRunMonitorStore.ACTIVE);
        binds.put('max', max);
        String condition = 'Status__c NOT IN :statuses';
        if (after != null && after.started != null) {
            binds.put('cursorStart', after.started);
            binds.put('cursorId', after.recordId);
            condition += after.recordId == null ? ' AND Started__c < :cursorStart'
                : ' AND (Started__c < :cursorStart OR (Started__c = :cursorStart AND Id < :cursorId))';
        }
        return new SystemAccess().query(condition, binds);
    }

    /**
     * @description Runs started since a moment, newest first (the lanes and the branches).
     * @param repository the repository filter, or null
     * @param since the moment
     * @param max how many at most
     * @return the runs
     */
    public static List<RLY_Pipeline_Run__c> since(String repository, Datetime since, Integer max) {
        Map<String, Object> binds = baseBinds(repository);
        binds.put('since', since);
        binds.put('max', max);
        return new SystemAccess().query('Started__c >= :since', binds);
    }

    /**
     * @description How many runs ended with a status since a moment.
     * @param repository the repository filter, or null
     * @param status Succeeded or Failed
     * @param since the moment (the start of today)
     * @return the count
     */
    public static Integer countFinished(String repository, String status, Datetime since) {
        Map<String, Object> binds = baseBinds(repository);
        binds.put('status', status);
        binds.put('since', since);
        return new SystemAccess().countWhere('Status__c = :status AND Finished__c >= :since', binds);
    }

    /**
     * @description The LIKE pattern on the run's GitHub address for a repository (owner/name), wildcards escaped.
     * @param repository the repository
     * @return the pattern, or null for blank
     */
    public static String urlPattern(String repository) {
        if (String.isBlank(repository)) {
            return null;
        }
        String repo = repository.trim().replace('\\', '').replace('%', '\\%').replace('_', '\\_');
        return '%/' + repo + '/actions/runs/%';
    }

    private static Map<String, Object> baseBinds(String repository) {
        Map<String, Object> binds = new Map<String, Object>();
        String pattern = urlPattern(repository);
        if (pattern != null) {
            binds.put('urlLike', pattern);
        }
        return binds;
    }

    /** @description Runs are shared hub records: read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description Runs matching a condition (and the repository filter), newest first.
         * @param condition the WHERE condition with binds (no input is ever put in the text)
         * @param binds the binds: max, and urlLike for the repository filter
         * @return the runs
         */
        public List<RLY_Pipeline_Run__c> query(String condition, Map<String, Object> binds) {
            String soql = 'SELECT ' + FIELDS + ' FROM RLY_Pipeline_Run__c WHERE ' + condition + repoCondition(binds)
                + ' ORDER BY Started__c DESC NULLS LAST, Id DESC LIMIT :max';
            return (List<RLY_Pipeline_Run__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description How many runs match a condition (and the repository filter).
         * @param condition the WHERE condition with binds
         * @param binds the binds
         * @return the count
         */
        public Integer countWhere(String condition, Map<String, Object> binds) {
            String soql = 'SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE ' + condition + repoCondition(binds);
            return Database.countQueryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }

        private String repoCondition(Map<String, Object> binds) {
            return binds.containsKey('urlLike') ? ' AND Run_Url__c LIKE :urlLike' : '';
        }
    }
}
