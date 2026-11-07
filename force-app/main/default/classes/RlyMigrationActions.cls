/**
 * @description The Migration tab's run and setup actions (build 46): the dry run (or the importer's verify) and the run
 * in the current pipeline, reading them while they go (then the open pull or merge requests that stay), Update pipeline
 * files and Check on the new connection. Callouts first, one save at the end; each
 * action is logged with who and when. The controller checks the admin.
 */
public with sharing class RlyMigrationActions {

    /**
     * @description Starts the dry run (or the importer's verify) or the run, in the current pipeline.
     * @param m the migration
     * @param kind dry or run
     */
    public static void dispatch(RLY_Migration__c m, String kind) {
        RlyMigrationGuard.requireOpen(m);
        requireRunnable(m, kind);
        String safeKind = kind == RlyMigrationRun.RUN ? RlyMigrationRun.RUN : RlyMigrationRun.DRY;
        RlyMigrationRun.start(m, safeKind, RlyMigrationViews.namedBranches(RlyGitConnections.byId(m.Current_Connection__c),
            RlyMigrationStore.orgs()));
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        m.Step__c = safeKind == RlyMigrationRun.RUN ? 4 : 3;
        state.log(safeKind == RlyMigrationRun.RUN ? 'Run' : 'Dry run', 'Started ' + m.Run_Id__c);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Reads the latest run; once the run (or the verify) is done, the open pull or merge requests that stay.
     * @param m the migration
     */
    public static void readRun(RLY_Migration__c m) {
        String before = m.Run_Status__c;
        Boolean changed = RlyMigrationRun.read(m);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        Boolean ended = before != m.Run_Status__c && !RlyMigrationRun.isRunning(m.Run_Status__c);
        if (ended && (m.Run_Kind__c == RlyMigrationRun.RUN || m.Method__c == RlyMigrationMethods.IMPORTER)) {
            try {
                state.requests = RlyMigrationRepo.openRequests(RlyGit.forConnection(RlyGitConnections.byId(m.Current_Connection__c)));
            } catch (Exception e) {
                state.requests = new List<RlyMigrationRepo.OpenRequest>();
            }
        }
        if (ended) {
            state.log(m.Run_Kind__c == RlyMigrationRun.RUN ? 'Run' : 'Dry run', m.Run_Id__c + ': ' + m.Run_Status__c);
        }
        if (changed || ended) {
            RlyMigrationGuard.save(m, state);
        }
    }

    /**
     * @description Update pipeline files on the new connection (after the copy, so the empty check held).
     * @param m the migration
     */
    public static void pushPipelineFiles(RLY_Migration__c m) {
        RLY_Git_Connection__c target = RlyMigrationGuard.requireTarget(m);
        Boolean copied = m.Method__c == RlyMigrationMethods.IMPORTER ? m.Result__c != null : m.Run_Status__c == RlyMigrationRun.SUCCEEDED;
        if (!copied) {
            throw new RlyReleaseException('Copy or verify the repository first: the pipeline files would make the new repository non-empty.');
        }
        RlyPipelineFiles.UpdateResult r = RlyPipelineFiles.updateRepositoryFor(target, RlyPipelineFiles.VIA_COMMIT);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        if (r.ok == true) {
            state.mark('new.files', RlyMigrationState.DONE);
        }
        state.log('New setup', r.ok == true ? 'Pipeline files updated' + (String.isBlank(r.url) ? '' : ': ' + r.url)
            : 'Pipeline files not updated: ' + r.message);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Checks the new connection (repository, pipeline files, every org's branch) and saves its status.
     * @param m the migration
     */
    public static void checkConnection(RLY_Migration__c m) {
        RLY_Git_Connection__c checked = RlyGitCheck.run(RlyMigrationGuard.requireTarget(m), RlyMigrationStore.orgs());
        RlyMigrationStore.saveConnection(checked);
        RlyGitConnections.forget();
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.mark('new.check', checked.Status__c == 'Connected' ? RlyMigrationState.DONE : RlyMigrationState.NOT_DONE);
        state.log('New setup', 'Checked the new connection: ' + checked.Status__c + '. ' + checked.Status_Message__c);
        RlyMigrationGuard.save(m, state);
    }


    // A method is picked, no run is going, and the run itself follows a ready dry run (the importer has no run).
    private static void requireRunnable(RLY_Migration__c m, String kind) {
        if (String.isBlank(m.Method__c)) {
            throw new RlyReleaseException('Pick how first.');
        }
        if (RlyMigrationRun.isRunning(m.Run_Status__c)) {
            throw new RlyReleaseException('A run is still going: wait for it.');
        }
        if (kind == RlyMigrationRun.RUN) {
            requireReadyDryRun(m);
        }
    }

    private static void requireReadyDryRun(RLY_Migration__c m) {
        if (m.Method__c == RlyMigrationMethods.IMPORTER) {
            throw new RlyReleaseException('The importer\'s copy is verified by the dry run.');
        }
        Map<String, Object> dry = RlyMigrationRun.parsed(m.Dry_Run__c);
        if (dry == null || dry.get('ready') != true) {
            throw new RlyReleaseException('Run the dry run first: the run starts once it says ready.');
        }
    }
}
