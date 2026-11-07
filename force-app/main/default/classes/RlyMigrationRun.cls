/**
 * @description The migrate job (pipeline files v26), started in the CURRENT connection's pipeline (build 46): a dry run
 * (options.dryRun, or Verify for a copy made by the provider's importer) and the run (lift and shift or fresh start).
 * Each start has its own request id (MIG- and 13 digits) and token; the result is results/<id>/migrate.json on the
 * current repository's results branch, read while the page is open, compacted and kept on the migration.
 * Callouts only: the caller saves the migration afterwards.
 */
public with sharing class RlyMigrationRun {

    /** @description A dry run (or a verify). */
    public static final String DRY = 'dry';
    /** @description The run itself. */
    public static final String RUN = 'run';
    /** @description Started, no result yet. */
    public static final String STARTED = 'Started';
    /** @description The result says the run is going. */
    public static final String GOING = 'In progress';
    /** @description A dry run that found nothing in the way. */
    public static final String READY = 'Ready';
    /** @description A dry run that found problems. */
    public static final String NOT_READY = 'Not ready';
    /** @description A run that copied everything. */
    public static final String SUCCEEDED = 'Succeeded';
    /** @description A run that failed, or ended without a result. */
    public static final String FAILED = 'Failed';

    private static final Integer KEEP_CHARS = 120000;

    /**
     * @description Starts a dry run or the run. Sets the run's fields on the migration (the caller saves them).
     * @param m the migration (Method__c set)
     * @param kind dry or run
     * @param branches the Release Relay branches (pipeline branch, each org's, results, snapshots)
     */
    public static void start(RLY_Migration__c m, String kind, List<String> branches) {
        RLY_Git_Connection__c current = RlyGitConnections.byId(m.Current_Connection__c);
        RLY_Git_Connection__c target = RlyGitConnections.byId(m.New_Connection__c);
        if (current == null || target == null) {
            throw new RlyReleaseException('The current or the new Git connection isn\'t there any more.');
        }
        RlyGit targetGit = RlyGit.forConnection(target);
        m.Run_Id__c = 'MIG-' + String.valueOf(System.now().getTime()).leftPad(13, '0');
        m.Run_Token__c = RlyPipelineRun.newToken();
        m.Run_Kind__c = kind;
        m.Run_Status__c = STARTED;
        m.Run_Url__c = null;
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'attempt' => m.Run_Token__c,
            'method' => RlyMigrationMethods.jobMethod(m.Method__c), 'dryRun' => kind == DRY,
            'targetUrl' => RlyMigrationRepo.pushUrl(targetGit), 'targetProvider' => RlyMigrationRepo.providerKey(target.Provider__c),
            'branches' => branches };
        RlyGit.forConnection(current).startPipeline(new Map<String, String>{
            'request_id' => m.Run_Id__c, 'mode' => 'migrate', 'environment' => '', 'target_environment' => '', 'branch' => '',
            'target' => '', 'components' => '', 'deletions' => '', 'options' => JSON.serialize(options),
            'title' => (m.Run_Id__c + ': ' + (kind == DRY ? 'dry run ' : 'move ') + RlyMigrationMethods.labelOf(current.Provider__c) + ' → '
                + RlyMigrationMethods.labelOf(target.Provider__c)).left(200)
        });
    }

    /**
     * @description Reads the latest run: its result once there (progress while it goes), else its run's link; a run
     * that ended without a result fails. Sets the fields on the migration (the caller saves them).
     * @param m the migration
     * @return true when something changed
     */
    public static Boolean read(RLY_Migration__c m) {
        if (String.isBlank(m.Run_Id__c) || !isRunning(m.Run_Status__c)) {
            return false;
        }
        RlyGit git = RlyGit.forConnection(RlyGitConnections.byId(m.Current_Connection__c));
        Map<String, Object> result = RlyResultSignature.lenient(git.getFileRaw('results/' + m.Run_Id__c + '/migrate.json', RlyPipelineRun.RESULTS_BRANCH),
            m.Run_Id__c, 'migrate');
        Boolean fromThisRun = result != null && m.Run_Token__c != null && m.Run_Token__c.equals(String.valueOf(result.get('attempt')));
        if (fromThisRun) {
            settle(m, result);
            if (m.Run_Status__c != GOING) {
                return true;
            }
        }
        Boolean watched = watch(m, git);
        return watched || fromThisRun;
    }

    // No final result yet: the run's link; a run that ended without one fails.
    private static Boolean watch(RLY_Migration__c m, RlyGit git) {
        RlyGit.Run run = git.findRun('Release Relay ' + m.Run_Id__c + ' (migrate)');
        if (run == null) {
            return false;
        }
        m.Run_Url__c = run.url == null ? null : run.url.left(255);
        if (run.completed()) {
            m.Run_Status__c = FAILED;
            putResult(m, JSON.serialize(new Map<String, Object>{ 'status' => FAILED,
                'message' => 'The run ended without writing its final result. Open the run for the reason (is RELAY_MIGRATE_TOKEN set?).' }));
        }
        return true;
    }

    /**
     * @description Whether a run status means it's still going.
     * @param status Run_Status__c
     * @return true for Started and In progress
     */
    public static Boolean isRunning(String status) {
        return status == STARTED || status == GOING;
    }

    /**
     * @description A kept result.
     * @param raw Dry_Run__c or Result__c
     * @return the map, or null
     */
    public static Map<String, Object> parsed(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            Object o = JSON.deserializeUntyped(raw);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
        } catch (JSONException e) {
            return null;
        }
    }

    // The result: progress while it goes, else the outcome; Verify's (the importer's) dry run is also What moved.
    private static void settle(RLY_Migration__c m, Map<String, Object> result) {
        String status = String.valueOf(result.get('status'));
        m.Run_Url__c = result.get('runUrl') == null ? m.Run_Url__c : RlyRunMonitorInput.url(result.get('runUrl'));
        m.Run_Status__c = statusOf(m.Run_Kind__c, result);
        String kept = compact(result);
        putResult(m, kept);
        if (m.Run_Kind__c == DRY && m.Method__c == RlyMigrationMethods.IMPORTER && status != GOING) {
            m.Result__c = kept;
        }
    }

    // In progress while it goes; a dry run is Ready or Not ready; the run Succeeded or Failed.
    private static String statusOf(String kind, Map<String, Object> result) {
        String status = String.valueOf(result.get('status'));
        if (status == GOING) {
            return GOING;
        }
        if (status != SUCCEEDED) {
            return FAILED;
        }
        return kind != DRY ? SUCCEEDED : (result.get('ready') == true ? READY : NOT_READY);
    }

    private static void putResult(RLY_Migration__c m, String kept) {
        if (m.Run_Kind__c == DRY) {
            m.Dry_Run__c = kept;
        } else {
            m.Result__c = kept;
        }
    }

    // Drops refs from the end until it fits a long text field (the counts always cover all of them).
    private static String compact(Map<String, Object> result) {
        result.remove('branchNames');
        List<Object> refs = result.get('refs') instanceof List<Object> ? (List<Object>) result.get('refs') : new List<Object>();
        String out = JSON.serialize(result);
        while (out.length() > KEEP_CHARS && !refs.isEmpty()) {
            Integer cut = Math.max(1, refs.size() / 4);
            for (Integer i = 0; i < cut; i++) {
                refs.remove(refs.size() - 1);
            }
            result.put('refs', refs);
            result.put('refsKept', refs.size());
            out = JSON.serialize(result);
        }
        return out.left(131072);
    }
}
