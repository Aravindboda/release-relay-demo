/**
 * @description Runs and reads back promote syncs (RlyBackPromote): starts a queued sync (pipeline mode sync: the hub's
 * branch merged into the org's branch and the delta deployed to the org), reads results/<REL>/sync.json (Deployed or
 * Nothing to deploy are a success; Conflict and Failed fail it) and keeps the org's Sync_Status__c / Synced_On__c.
 */
public with sharing class RlyBackPromoteRun {

    /** @description The pipeline mode (and Pending_Run__c) of a sync. */
    public static final String MODE = 'sync';

    private static final Set<String> SUCCESS = new Set<String>{ 'Deployed', 'Nothing to deploy' };

    /**
     * @description Moves an open sync along: starts it when queued (unless manual steps before deploy are still to do in
     * its org), else reads its result. Callouts only.
     * @param rel the sync (Submitted or Deploying)
     * @param git the Git provider
     */
    public static void advanceSync(RLY_Release__c rel, RlyGit git) {
        if (rel.Status__c == RlyPromotion.QUEUED) {
            startUnlessHeld(rel, git);
        } else {
            readSync(rel, git);
        }
    }

    // A queued sync waits while manual steps before deploy are still to do in its org (RlyManualStepGate).
    private static void startUnlessHeld(RLY_Release__c rel, RlyGit git) {
        if (!RlyManualStepGate.blocks(rel)) {
            dispatch(rel, git);
        }
    }

    /**
     * @description Starts the sync run (also after its approval). Callouts only: the caller saves the release.
     * @param rel the sync
     * @param git the Git provider
     */
    public static void dispatch(RLY_Release__c rel, RlyGit git) {
        git.startPipeline(RlyPipelineRun.inputs(rel, MODE, rel.Source_Branch__c));
        rel.Status__c = 'Deploying';
        rel.Deploy_Status__c = 'Deploying';
        rel.Pending_Run__c = MODE;
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    /**
     * @description Reads the sync result and the run.
     * @param rel the sync (Deploying)
     * @param git the Git provider
     */
    public static void readSync(RLY_Release__c rel, RlyGit git) {
        RlyGit.Run run = RlyPipelineRun.findRun(git, rel);
        Map<String, Object> r = RlyPipelineRun.result(git, rel, MODE);
        if (r != null) {
            finish(rel, r);
        } else if (run != null && run.failed()) {
            rel.Status__c = 'Failed';
            rel.Deploy_Status__c = 'Failed';
            rel.Error_Message__c = 'The pipeline run failed before it wrote a result. Open the run.';
        }
    }

    private static void finish(RLY_Release__c rel, Map<String, Object> r) {
        String status = String.valueOf(r.get('status'));
        Boolean ok = SUCCESS.contains(status);
        rel.Status__c = ok ? 'Deployed' : 'Failed';
        rel.Deploy_Status__c = ok ? 'Deployed' : 'Failed';
        rel.Deploy_Result__c = JSON.serialize(r).left(131072);
        if (r.get('sha') != null && String.isNotBlank(String.valueOf(r.get('sha')))) {
            rel.Merge_Commit__c = String.valueOf(r.get('sha')).left(40);
        }
        rel.Error_Message__c = ok ? null : failure(rel, status, r).left(2000);
    }

    private static String failure(RLY_Release__c rel, String status, Map<String, Object> r) {
        if (status == 'Conflict') {
            List<Object> files = r.get('conflicts') instanceof List<Object> ? (List<Object>) r.get('conflicts') : new List<Object>();
            List<String> names = new List<String>();
            for (Object f : files) {
                names.add(f instanceof Map<String, Object> ? String.valueOf(((Map<String, Object>) f).get('file')) : String.valueOf(f));
            }
            return rel.Target_Branch__c + ' couldn\'t take ' + rel.Source_Branch__c + ' automatically'
                + (names.isEmpty() ? '' : ': conflicts in ' + String.join(names, ', ')) + '. Nothing was deployed.';
        }
        return r.get('message') == null ? 'The sync failed. Open the run.' : String.valueOf(r.get('message'));
    }

    /**
     * @description Starts the queued syncs and reads the running ones (up to five), then saves them: callouts first,
     * the saves last. The hub release's page and the Pipeline tab call it.
     */
    public static void catchUp() {
        if (!RlyHubGuard.isHub()) {
            return; // a sandbox copy of the hub never starts or reads syncs
        }
        List<Id> ids = RlyPromoteStore.openSyncIds();
        RLY_Git_Connection__c conn = ids.isEmpty() ? null : RlyReleaseStore.git();
        if (conn == null) {
            return;
        }
        RlyGit git = RlyGit.forConnection(conn);
        List<RLY_Release__c> rels = new List<RLY_Release__c>();
        for (Id relId : ids) {
            RLY_Release__c rel = RlyReleaseStore.release(relId);
            String oldStatus = rel.Status__c;
            try {
                advanceSync(rel, git);
            } catch (Exception e) {
                rel.Error_Message__c = ('Couldn\'t read the latest status: ' + e.getMessage()).left(2000);
            }
            RlyFlowActivation.afterRead(rel, oldStatus);
            rel.Last_Synced__c = System.now();
            RlySlack.notifyTransition(rel, oldStatus);
            rels.add(rel);
        }
        RlyReleaseStore.saveAll(rels);
        RlySlack.saveResults();
    }

    /**
     * @description The org fields a saved sync changes: Running while queued or running, Deployed (with Synced_On__c, the
     * sync's start) or Failed / Conflict when it ends.
     * @param rel the sync, as saved
     * @return the org row to save, or null when nothing changes
     */
    public static RLY_Org__c orgResult(RLY_Release__c rel) {
        if (rel.Target_Org__c == null) {
            return null;
        }
        if (rel.Status__c == RlyPromotion.QUEUED || rel.Status__c == 'Deploying') {
            return new RLY_Org__c(Id = rel.Target_Org__c, Sync_Status__c = 'Running');
        }
        if (rel.Status__c == 'Deployed') {
            return new RLY_Org__c(Id = rel.Target_Org__c, Sync_Status__c = 'Deployed',
                Synced_On__c = rel.Checks_Requested__c == null ? System.now() : rel.Checks_Requested__c);
        }
        if (rel.Status__c == 'Failed' || rel.Status__c == 'Deploy failed') {
            Boolean conflict = String.isNotBlank(rel.Deploy_Result__c) && rel.Deploy_Result__c.contains('"status":"Conflict"');
            return new RLY_Org__c(Id = rel.Target_Org__c, Sync_Status__c = conflict ? 'Conflict' : 'Failed');
        }
        return null;
    }
}
