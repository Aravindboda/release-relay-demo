/**
 * @description The archive's summary rows (RLY_Archive_Run__c): one per run, updated after each pass and never removed
 * by the archive. Starts a run, reads the one Running run (a Running row with no pass for 15 minutes is stopped as
 * Failed so it never blocks), records a pass, finishes or cancels a run, and turns rows into RlyArchiveViews.Run. Runs
 * are shared hub records: read and written in system mode in the private inner without sharing class.
 */
public with sharing class RlyArchiveRuns {

    /** @description A run going now. */
    public static final String RUNNING = 'Running';
    /** @description A run that removed everything eligible (or found nothing). */
    public static final String SUCCEEDED = 'Succeeded';
    /** @description A run stopped by a failed pass. */
    public static final String FAILED = 'Failed';
    /** @description A run stopped at the pass limit. */
    public static final String PARTIAL = 'Partial';
    /** @description A Run now cancelled between passes. */
    public static final String CANCELLED = 'Cancelled';
    /** @description How__c of a run from the Git pipeline's scheduled job. */
    public static final String NIGHTLY = 'Nightly';
    /** @description How__c of a run from the Archive tab. */
    public static final String RUN_NOW = 'Run_Now';
    /** @description What a dead run's message says. */
    public static final String DEAD_MESSAGE = 'Stopped: no pass for 15 minutes';
    /** @description What a nightly run shows as who ran it. */
    public static final String PIPELINE_JOB = 'Git pipeline job';

    /** @description Minutes without a pass after which a Running row counts as dead (tests can change it). */
    @TestVisible
    private static Integer deadMinutes = 15;
    private static final Integer KB_PER_RECORD = 2;

    /**
     * @description Starts a run: a Running row with no passes yet.
     * @param how NIGHTLY or RUN_NOW
     * @param days the Retention days (releases finished before now minus these are eligible)
     * @param pipelineUrl the GitHub Actions run (nightly), or null
     * @return the row, inserted
     */
    public static RLY_Archive_Run__c start(String how, Integer days, String pipelineUrl) {
        RLY_Archive_Run__c run = new RLY_Archive_Run__c(Started__c = RlyArchiveService.now(), How__c = how,
            Run_By__c = UserInfo.getUserId(), Retention_Days__c = days, Cutoff__c = RlyArchiveService.cutoff(days),
            Passes__c = 0, Releases_Removed__c = 0, Records_Removed__c = 0, Storage_Freed_KB__c = 0, Status__c = RUNNING,
            Pipeline_Run_Url__c = pipelineUrl);
        new Data().write(run);
        return run;
    }

    /**
     * @description Records a run that found nothing to remove (a nightly call with nothing eligible).
     * @param days the Retention days
     * @param cutoff the cutoff
     * @param pipelineUrl the GitHub Actions run, or null
     * @return the row, inserted
     */
    public static RLY_Archive_Run__c nothingToRemove(Integer days, Datetime cutoff, String pipelineUrl) {
        RLY_Archive_Run__c run = new RLY_Archive_Run__c(Started__c = RlyArchiveService.now(), Finished__c = RlyArchiveService.now(),
            How__c = NIGHTLY, Run_By__c = UserInfo.getUserId(), Retention_Days__c = days, Cutoff__c = cutoff, Passes__c = 0,
            Releases_Removed__c = 0, Records_Removed__c = 0, Storage_Freed_KB__c = 0, Status__c = SUCCEEDED,
            Message__c = 'Nothing to remove', Pipeline_Run_Url__c = pipelineUrl);
        new Data().write(run);
        return run;
    }

    /**
     * @description A run by its Id.
     * @param runId the run
     * @return the row, or null
     */
    public static RLY_Archive_Run__c find(Id runId) {
        List<RLY_Archive_Run__c> rows = runId == null ? new List<RLY_Archive_Run__c>() : new Data().byId(runId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description The run going now. Running rows with no pass for 15 minutes are stopped as Failed first.
     * @return the row, or null
     */
    public static RLY_Archive_Run__c running() {
        Data data = new Data();
        Datetime deadBefore = System.now().addMinutes(-deadMinutes);
        RLY_Archive_Run__c alive;
        List<RLY_Archive_Run__c> dead = new List<RLY_Archive_Run__c>();
        for (RLY_Archive_Run__c r : data.runningRows()) {
            if (r.LastModifiedDate < deadBefore) {
                dead.add(new RLY_Archive_Run__c(Id = r.Id, Status__c = FAILED, Finished__c = r.LastModifiedDate, Message__c = DEAD_MESSAGE));
            } else if (alive == null) {
                alive = r;
            }
        }
        if (!dead.isEmpty()) {
            data.write(dead);
        }
        return alive;
    }

    /**
     * @description Adds a pass's numbers to the run (not saved).
     * @param run the run
     * @param o what the pass removed
     */
    public static void addPass(RLY_Archive_Run__c run, RlyArchivePass.Outcome o) {
        run.Passes__c = whole(run.Passes__c) + 1;
        run.Releases_Removed__c = whole(run.Releases_Removed__c) + o.releases;
        run.Records_Removed__c = whole(run.Records_Removed__c) + o.records;
        run.Storage_Freed_KB__c = whole(run.Records_Removed__c) * KB_PER_RECORD;
        if (o.oldest != null && (run.Oldest_Removed__c == null || o.oldest < run.Oldest_Removed__c)) {
            run.Oldest_Removed__c = o.oldest;
        }
        if (o.newest != null && (run.Newest_Removed__c == null || o.newest > run.Newest_Removed__c)) {
            run.Newest_Removed__c = o.newest;
        }
    }

    /**
     * @description Ends the run (not saved).
     * @param run the run
     * @param status SUCCEEDED, FAILED, PARTIAL or CANCELLED
     * @param message what happened
     */
    public static void finish(RLY_Archive_Run__c run, String status, String message) {
        run.Status__c = status;
        run.Finished__c = RlyArchiveService.now();
        run.Message__c = message == null ? null : message.left(255);
    }

    /**
     * @description Saves the run.
     * @param run the run
     */
    public static void save(RLY_Archive_Run__c run) {
        new Data().write(run);
    }

    /**
     * @description Cancels a Running run between passes ("Cancelled after pass N"); a finished run stays as it is.
     * @param run the run
     */
    public static void cancel(RLY_Archive_Run__c run) {
        if (run.Status__c != RUNNING) {
            return;
        }
        finish(run, CANCELLED, 'Cancelled after pass ' + whole(run.Passes__c));
        save(run);
    }

    /**
     * @description Every run, newest first.
     * @param max the most to read
     * @return the rows
     */
    public static List<RLY_Archive_Run__c> newest(Integer max) {
        return new Data().newest(max);
    }

    /**
     * @description A row as the page shows it.
     * @param r the row (with Run_By__r.Name), or null
     * @return the run, or null
     */
    public static RlyArchiveViews.Run view(RLY_Archive_Run__c r) {
        if (r == null) {
            return null;
        }
        RlyArchiveViews.Run v = new RlyArchiveViews.Run();
        v.id = r.Id;
        v.name = r.Name;
        v.started = r.Started__c;
        v.finished = r.Finished__c;
        v.how = r.How__c == NIGHTLY ? 'Nightly' : 'Run now';
        v.runBy = r.How__c == NIGHTLY ? PIPELINE_JOB : (r.Run_By__r == null ? null : r.Run_By__r.Name);
        v.days = toInt(r.Retention_Days__c);
        v.passes = whole(r.Passes__c);
        v.releases = whole(r.Releases_Removed__c);
        v.records = whole(r.Records_Removed__c);
        v.freedKB = whole(r.Storage_Freed_KB__c);
        v.oldest = r.Oldest_Removed__c;
        v.newest = r.Newest_Removed__c;
        v.status = r.Status__c;
        v.message = r.Message__c;
        v.pipelineUrl = r.Pipeline_Run_Url__c;
        return v;
    }

    /**
     * @description A number field as a whole number (blank is 0).
     * @param d the value
     * @return the number
     */
    public static Integer whole(Decimal d) {
        return d == null ? 0 : d.intValue();
    }

    private static Integer toInt(Decimal d) {
        return d == null ? null : d.intValue();
    }

    /** @description Runs are shared hub records: read and written in system mode. */
    private without sharing class Data {

        /**
         * @description A run by its Id.
         * @param runId the run
         * @return the row, or none
         */
        public List<RLY_Archive_Run__c> byId(Id runId) {
            return [SELECT Id, Name, Started__c, Finished__c, How__c, Run_By__c, Run_By__r.Name, Retention_Days__c, Cutoff__c,
                        Passes__c, Releases_Removed__c, Records_Removed__c, Storage_Freed_KB__c, Oldest_Removed__c, Newest_Removed__c,
                        Status__c, Message__c, Pipeline_Run_Url__c, LastModifiedDate
                    FROM RLY_Archive_Run__c WHERE Id = :runId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Every Running row, newest first.
         * @return the rows
         */
        public List<RLY_Archive_Run__c> runningRows() {
            return [SELECT Id, Name, Started__c, Finished__c, How__c, Run_By__c, Run_By__r.Name, Retention_Days__c, Cutoff__c,
                        Passes__c, Releases_Removed__c, Records_Removed__c, Storage_Freed_KB__c, Oldest_Removed__c, Newest_Removed__c,
                        Status__c, Message__c, Pipeline_Run_Url__c, LastModifiedDate
                    FROM RLY_Archive_Run__c WHERE Status__c = :RUNNING WITH SYSTEM_MODE ORDER BY Started__c DESC LIMIT 50];
        }

        /**
         * @description Every run, newest first.
         * @param max the most to read
         * @return the rows
         */
        public List<RLY_Archive_Run__c> newest(Integer max) {
            return [SELECT Id, Name, Started__c, Finished__c, How__c, Run_By__c, Run_By__r.Name, Retention_Days__c, Cutoff__c,
                        Passes__c, Releases_Removed__c, Records_Removed__c, Storage_Freed_KB__c, Oldest_Removed__c, Newest_Removed__c,
                        Status__c, Message__c, Pipeline_Run_Url__c, LastModifiedDate
                    FROM RLY_Archive_Run__c WITH SYSTEM_MODE ORDER BY Started__c DESC, Name DESC LIMIT :max];
        }

        /**
         * @description Inserts or updates a run.
         * @param run the row
         */
        public void write(RLY_Archive_Run__c run) {
            if (run.Id == null) {
                Database.insert(run, true, AccessLevel.SYSTEM_MODE);
            } else {
                Database.update(run, true, AccessLevel.SYSTEM_MODE);
            }
        }

        /**
         * @description Updates runs.
         * @param runs the rows
         */
        public void write(List<RLY_Archive_Run__c> runs) {
            Database.update(runs, true, AccessLevel.SYSTEM_MODE);
        }
    }
}
