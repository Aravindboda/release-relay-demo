/**
 * @description Data set runs (Sync status tab, Data). A run is a dry run first (the pipeline reads the source records and
 * the target org, works out inserts, updates and unchanged records, and stops on duplicates or records without a key),
 * then a load of exactly those records once a person allows it:
 *   start          a source with a GitHub sign-in: the pipeline exports and dry-runs (mode data); a developer org source
 *                  (no sign-in): the page sends its records in parts first (RlyDataExport.send, then runExported)
 *   (RlyDataExport) one page of one object's records from a developer org, committed to the results branch
 *                  (data-inbox/DAT-…/) as the pipeline's export job would
 *   runExported    once every part is sent: the dry run from those records
 *   load           the load of the dry run's records (the same export): Up needs an approver who didn't start it,
 *                  Down and Refill an admin
 * Callouts always come before the run's save in one request. Mode data: request_id DAT-…, environment = the source's
 * Git environment (blank when the hub sent the records), target_environment = the target's, options {attempt, dryRun,
 * sourceInbox, mask, direction, sourceValuesEnv, dataSet}.
 */
public with sharing class RlyDataRuns {

    /** @description Up: send up (an approver loads). */
    public static final String UP = 'Up';
    /** @description Down: copy down (admins). */
    public static final String DOWN = 'Down';
    /** @description Refill: copy down into an org refreshed since its last load (admins). */
    public static final String REFILL = 'Refill';
    /** @description Where a developer org's records wait for the pipeline. */
    public static final String INBOX = 'data-inbox/';
    /** @description Most records exported from one object. */
    public static final Integer MAX_RECORDS = 10000;
    // What a dispatch does: the dry run reading the source, the dry run from the saved records, the load.
    private static final String FROM_SOURCE = 'source';
    private static final String FROM_INBOX = 'inbox';
    private static final String LOAD = 'load';

    /** @description What the page asks for. */
    public class Request {
        /** @description The data set. */
        public Id dataSetId;
        /** @description Where the records come from. */
        public Id sourceOrgId;
        /** @description Where they go. */
        public Id targetOrgId;
        /** @description Up, Down or Refill. */
        public String direction;
        /** @description Mask personal data (copy down). */
        public Boolean mask;
        /** @description Optional: the release this data goes with (REL-…). */
        public String releaseName;
    }

    /** @description A started run. */
    public class Started {
        /** @description The run id. */
        @AuraEnabled public String runId;
        /** @description export: the page sends the records (RlyDataExport.send for each object); dryRun: the pipeline started. */
        @AuraEnabled public String next;
        /** @description The export queries, one per object, in order (export only). */
        @AuraEnabled public List<String> queries = new List<String>();
    }

    /**
     * @description Starts a run's dry run, or its export when the source is a developer org.
     * @param req the request
     * @return the run
     */
    public static Started start(Request req) {
        checkRequest(req);
        RlyDataRules.Checked c = RlyDataRules.checkStart(req);
        RLY_Data_Run__c run = new RLY_Data_Run__c(Run_Id__c = newId(), Data_Set__c = c.dataSet.Id, Direction__c = req.direction,
            Source_Org__c = c.source.Id, Target_Org__c = c.target.Id, Target_Org_Id__c = c.target.Org_Id__c, Mask__c = c.mask,
            Release__c = c.releaseId, Token__c = RlyPipelineRun.newToken(), Requested_By__c = UserInfo.getUserId(),
            Checked_At__c = System.now());
        Started s = new Started();
        s.runId = run.Run_Id__c;
        if (RlyDataRules.hasSignIn(c.source)) {
            dispatch(run, c, FROM_SOURCE);
            run.Status__c = RlyDataStore.DRY_RUN;
            s.next = 'dryRun';
        } else {
            run.Status__c = RlyDataStore.EXPORTING;
            s.next = 'export';
            for (RlyDataSet.Item i : c.definition.objects) {
                s.queries.add(RlyDataSet.queryOf(i));
            }
        }
        run.Run_Title__c = runTitle(run.Run_Id__c);
        RlyDataStore.saveRun(run);
        return s;
    }

    /**
     * @description Starts the dry run once a developer org's records are on the results branch.
     * @param runId the run
     * @return the run's title
     */
    public static String runExported(String runId) {
        RLY_Data_Run__c run = RlyDataRules.requireStatus(runId, RlyDataStore.EXPORTING);
        RlyDataRules.requireRequester(run);
        RlyDataRules.Checked c = RlyDataRules.forRun(run);
        dispatch(run, c, FROM_INBOX);
        RlyDataStore.saveRun(new RLY_Data_Run__c(Run_Id__c = runId, Status__c = RlyDataStore.DRY_RUN));
        return run.Run_Title__c;
    }

    /**
     * @description Loads the dry run's records into the target (a person allows it: see RlyDataRules.requireLoader).
     * @param runId the run
     * @return the run's title
     */
    public static String load(String runId) {
        RLY_Data_Run__c run = RlyDataRules.requireStatus(runId, RlyDataStore.READY);
        RlyDataRules.requireLoader(run);
        RlyDataRules.Checked c = RlyDataRules.forRun(run);
        run.Token__c = RlyPipelineRun.newToken();
        dispatch(run, c, LOAD);
        RlyDataStore.saveRun(new RLY_Data_Run__c(Run_Id__c = runId, Status__c = RlyDataStore.LOADING, Token__c = run.Token__c,
            Approved_By__c = UserInfo.getUserId(), Approved_On__c = System.now(), Message__c = null));
        return run.Run_Title__c;
    }

    /**
     * @description The run's title on GitHub.
     * @param runId the run id
     * @return Release Relay DAT-… (data)
     */
    public static String runTitle(String runId) {
        return 'Release Relay ' + runId + ' (data)';
    }

    // Mode data: the export job signs in to the source (unless the records are already on the results branch), the load
    // job to the target; dryRun stops before any change.
    private static void dispatch(RLY_Data_Run__c run, RlyDataRules.Checked c, String kind) {
        Boolean dryRun = kind != LOAD;
        Boolean fromInbox = kind != FROM_SOURCE;
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'attempt' => run.Token__c, 'dryRun' => dryRun,
            'sourceInbox' => fromInbox, 'mask' => c.mask, 'direction' => run.Direction__c, 'label' => c.target.Name.left(40),
            'sourceLabel' => c.source.Name.left(40), 'sourceValuesEnv' => String.isBlank(c.source.Git_Environment__c) ? '' : c.source.Git_Environment__c,
            'dataSet' => new Map<String, Object>{ 'title' => c.dataSet.Title__c, 'objects' => c.definition.objects, 'bypass' => c.definition.bypass } };
        String body = JSON.serialize(options);
        if (body.length() > 60000) {
            throw new RlyReleaseException('The data set is too large to send to the pipeline: split it.');
        }
        RlyComparePipelineInput.gitHub().startPipeline(new Map<String, String>{
            'request_id' => run.Run_Id__c, 'mode' => 'data',
            'environment' => fromInbox ? '' : c.source.Git_Environment__c, 'target_environment' => c.target.Git_Environment__c,
            'branch' => '', 'target' => String.isBlank(c.target.Branch__c) ? 'main' : c.target.Branch__c.trim(),
            'title' => ((dryRun ? 'Data dry run: ' : 'Data load: ') + c.dataSet.Title__c + ' ' + c.source.Name + ' → ' + c.target.Name).left(200),
            'components' => '', 'deletions' => '', 'options' => body
        });
    }

    // A data set, two different orgs, a direction; copying down is for admins.
    private static void checkRequest(Request req) {
        if (!isComplete(req) || req.sourceOrgId == req.targetOrgId) {
            throw new RlyReleaseException('Pick a data set, a source org and a different target org.');
        }
        if (!new Set<String>{ UP, DOWN, REFILL }.contains(req.direction)) {
            throw new RlyReleaseException('Pick Send up or Copy down.');
        }
        if (req.direction != UP && !RlyOrgController.isAdmin()) {
            throw new RlyReleaseException('Copying data down is for Release Relay admins.');
        }
    }

    private static Boolean isComplete(Request req) {
        return req != null && req.dataSetId != null && req.sourceOrgId != null && req.targetOrgId != null;
    }

    private static String newId() {
        return 'DAT-' + String.valueOf(System.now().getTime()).leftPad(13, '0');
    }
}
