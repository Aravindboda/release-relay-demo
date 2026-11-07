/**
 * @description Reads a data run's result from the results branch (results/DAT-…/data.json, written by the pipeline's
 * mode data) once it's from this run (its attempt is the run's token), and moves the run on: a dry run that passed is
 * Ready, one with duplicates or records without a key is Blocked, a load is Loaded; a failed run (or one that ended
 * without a result) is Failed. The result per object: insert, update, unchanged, failed, duplicate keys (records that
 * match more than one target record), records without a key, and whether the target's triggers fire. Callouts first,
 * then the run's save.
 */
public with sharing class RlyDataResult {

    /** @description A run as the page shows it. */
    public class View {
        /** @description The run id. */
        @AuraEnabled public String runId;
        /** @description The run's status. */
        @AuraEnabled public String status;
        /** @description Whether the result is there (false: ask again). */
        @AuraEnabled public Boolean done = false;
        /** @description The pipeline run. */
        @AuraEnabled public String runUrl;
        /** @description Why it's blocked or failed. */
        @AuraEnabled public String message;
        /** @description Whether this result is the dry run's (else the load's). */
        @AuraEnabled public Boolean dryRun = true;
        /** @description Per object. */
        @AuraEnabled public List<ObjectRow> objects = new List<ObjectRow>();
        /** @description Totals. */
        @AuraEnabled public Map<String, Integer> counts = new Map<String, Integer>();
    }

    /** @description One object's counts. */
    public class ObjectRow {
        /** @description The object. */
        @AuraEnabled public String objectName;
        /** @description Records to insert (or inserted). */
        @AuraEnabled public Integer inserts = 0;
        /** @description Records to update (or updated). */
        @AuraEnabled public Integer updates = 0;
        /** @description Records the same in both orgs. */
        @AuraEnabled public Integer unchanged = 0;
        /** @description Records the load couldn't save. */
        @AuraEnabled public Integer failed = 0;
        /** @description Keys that match more than one target record. */
        @AuraEnabled public List<String> duplicates = new List<String>();
        /** @description Source records without a key. */
        @AuraEnabled public Integer missingKeys = 0;
        /** @description The target's triggers on the object fire during the load (no bypass). */
        @AuraEnabled public Boolean triggers = false;
        /** @description The first errors, for a failed load. */
        @AuraEnabled public List<String> errors = new List<String>();
    }

    /**
     * @description Reads a run: its result when it's there, else the pipeline run's state.
     * @param runId the run
     * @return the view
     */
    public static View read(String runId) {
        RLY_Data_Run__c run = String.isBlank(runId) ? null : RlyDataStore.run(runId);
        if (run == null) {
            throw new RlyReleaseException('That data run isn\'t there any more.');
        }
        View v = new View();
        v.runId = runId;
        v.status = run.Status__c;
        v.message = run.Message__c;
        v.runUrl = run.Run_Url__c;
        Boolean waiting = run.Status__c == RlyDataStore.DRY_RUN || run.Status__c == RlyDataStore.LOADING;
        if (!waiting) {
            v.done = true;
            fromSummary(v, run.Summary__c);
            return v;
        }
        RlyGit git = RlyComparePipelineInput.gitHubFor(run.Target_Org__c); // build 45: the target org's repository
        Map<String, Object> result = parsed(git.getFileRaw('results/' + runId + '/data.json', RlyPipelineRun.RESULTS_BRANCH));
        if (result != null && run.Token__c != null && run.Token__c.equals(String.valueOf(result.get('attempt')))) {
            settle(v, run, result);
        } else {
            watch(v, git, run);
        }
        return v;
    }

    // The result is there: status from it, saved with the counts and the summary.
    private static void settle(View v, RLY_Data_Run__c run, Map<String, Object> result) {
        v.done = true;
        v.runUrl = result.get('runUrl') == null ? v.runUrl : String.valueOf(result.get('runUrl'));
        v.dryRun = result.get('dryRun') != false;
        Boolean ok = String.valueOf(result.get('status')) == 'Succeeded';
        Boolean blocked = result.get('blocked') == true;
        v.message = result.get('message') == null ? null : String.valueOf(result.get('message')).left(4000);
        readObjects(v, result);
        if (!ok) {
            v.status = blocked ? RlyDataStore.BLOCKED : RlyDataStore.FAILED;
        } else {
            v.status = v.dryRun ? RlyDataStore.READY : RlyDataStore.LOADED;
        }
        result.remove('records');
        String summary = JSON.serialize(result);
        String counts = JSON.serialize(v.counts);
        RlyDataStore.saveRun(new RLY_Data_Run__c(Run_Id__c = run.Run_Id__c, Status__c = v.status, Message__c = v.message,
            Run_Url__c = v.runUrl == null ? null : v.runUrl.left(255), Counts__c = counts.length() > 255 ? null : counts,
            Summary__c = summary.length() > 131072 ? null : summary));
    }

    // No result yet: the run's link; a run that ended without one fails the data run.
    private static void watch(View v, RlyGit git, RLY_Data_Run__c run) {
        RlyGit.Run ghRun = git.findRun(run.Run_Title__c);
        if (ghRun == null) {
            return;
        }
        v.runUrl = ghRun.url;
        RLY_Data_Run__c row = new RLY_Data_Run__c(Run_Id__c = run.Run_Id__c, Run_Url__c = ghRun.url == null ? null : ghRun.url.left(255));
        if (ghRun.completed()) {
            v.done = true;
            v.status = RlyDataStore.FAILED;
            v.message = 'The run ended without writing its result. Open the run for the reason.';
            row.Status__c = v.status;
            row.Message__c = v.message;
        }
        RlyDataStore.saveRun(row);
    }

    /**
     * @description The saved summary of a finished run.
     * @param v the view
     * @param summary Summary__c
     */
    public static void fromSummary(View v, String summary) {
        Map<String, Object> result = parsed(summary);
        if (result != null) {
            v.dryRun = result.get('dryRun') != false;
            readObjects(v, result);
        }
    }

    // Per object, and the totals.
    private static void readObjects(View v, Map<String, Object> result) {
        Map<String, Integer> totals = new Map<String, Integer>{ 'insert' => 0, 'update' => 0, 'unchanged' => 0, 'failed' => 0, 'duplicates' => 0 };
        for (Object o : result.get('objects') instanceof List<Object> ? (List<Object>) result.get('objects') : new List<Object>()) {
            Map<String, Object> m = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            ObjectRow r = new ObjectRow();
            r.objectName = String.valueOf(m.get('objectName'));
            r.inserts = whole(m.get('insert'));
            r.updates = whole(m.get('update'));
            r.unchanged = whole(m.get('unchanged'));
            r.failed = whole(m.get('failed'));
            r.missingKeys = whole(m.get('missingKeys'));
            r.triggers = m.get('triggers') == true;
            r.duplicates = texts(m.get('duplicates'));
            r.errors = texts(m.get('errors'));
            v.objects.add(r);
            totals.put('insert', totals.get('insert') + r.inserts);
            totals.put('update', totals.get('update') + r.updates);
            totals.put('unchanged', totals.get('unchanged') + r.unchanged);
            totals.put('failed', totals.get('failed') + r.failed);
            totals.put('duplicates', totals.get('duplicates') + r.duplicates.size());
        }
        v.counts = totals;
    }

    private static Integer whole(Object o) {
        return o instanceof Integer ? (Integer) o : (o instanceof Decimal ? ((Decimal) o).intValue() : 0);
    }

    private static List<String> texts(Object o) {
        List<String> out = new List<String>();
        for (Object x : o instanceof List<Object> ? (List<Object>) o : new List<Object>()) {
            if (out.size() < 50) {
                out.add(String.valueOf(x).left(255));
            }
        }
        return out;
    }

    private static Map<String, Object> parsed(String raw) {
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
}
