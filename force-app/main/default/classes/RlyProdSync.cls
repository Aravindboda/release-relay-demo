/**
 * @description Several Git connections (build 45): after a deploy to production, the prod branch of every OTHER active
 * connection's repository is brought up to date, so the repositories never drift apart. The hub's branch exists in
 * every repository. Best effort: the state is shown on the deployed release and never blocks it.
 *
 * For each other connection the hub raises an automatic release (Release_Type__c Prod_Sync) from the hub org into that
 * repository's prod branch, with the deployed release's components retrieved from the hub org, as a normal raise
 * retrieves from a developer org (RlyProdSyncRun). It has no target environment, so its run (mode hub) only converts,
 * opens the pull or merge request and scans: no validation, no deploy. When its checks pass the hub starts mode merge,
 * again without a target environment: a merge only (the pipeline's deploy job runs only with a target environment),
 * and the merge result marks it Deployed (RlyDeployReader).
 *
 * The save after the deploy only queues it (RLY_Release__c.Prod_Sync__c, one entry per connection): reads of the
 * deployed release's page move it on, one step per read (callouts first, the saves last): the raise, then the automatic
 * release's own reads (RlyStatusReader).
 */
public with sharing class RlyProdSync {

    /** @description Release_Type__c of the automatic release. */
    public static final String TYPE_PROD_SYNC = 'Prod_Sync';
    /** @description An entry saved, its release not raised yet. */
    public static final String QUEUED = 'Queued';
    /** @description Its release is raised: its own status tells the rest. */
    public static final String STARTED = 'Started';
    /** @description It couldn't be raised. */
    public static final String FAILED = 'Failed';
    /** @description What the page shows when the prod branch is in step. */
    public static final String SYNCED = 'Synced';
    /** @description What the page shows while it runs. */
    public static final String RUNNING = 'Running';

    /** @description One other repository's prod branch, as saved on the deployed release. */
    public class Entry {
        /** @description The connection. */
        public Id connectionId;
        /** @description Its provider's name, for example GitHub. */
        public String provider;
        /** @description Its repository. */
        public String repository;
        /** @description The branch brought up to date (the hub's). */
        public String branch;
        /** @description Queued, Started or Failed. */
        public String status;
        /** @description Why it failed, or null. */
        public String message;
        /** @description The automatic release, once raised. */
        public Id releaseId;
    }

    /** @description What the deployed release's page shows for one other repository. */
    public class View {
        /** @description The connection. */
        @AuraEnabled public Id connectionId;
        /** @description Its provider's name. */
        @AuraEnabled public String provider;
        /** @description Its repository. */
        @AuraEnabled public String repository;
        /** @description The branch. */
        @AuraEnabled public String branch;
        /** @description Synced, Running or Failed. */
        @AuraEnabled public String state;
        /** @description What happened. */
        @AuraEnabled public String message;
        /** @description The automatic release, or null. */
        @AuraEnabled public Id releaseId;
        /** @description Its number, or null. */
        @AuraEnabled public String releaseName;
    }

    /**
     * @description Whether a release is an automatic prod sync release.
     * @param rel the release, with Release_Type__c
     * @return true for Prod_Sync
     */
    public static Boolean isProdSync(RLY_Release__c rel) {
        return RlyPromotion.typeOf(rel) == TYPE_PROD_SYNC;
    }

    /**
     * @description After a deploy to production (DML only; the caller's callouts are done): one queued entry for every
     * other active connection. A release that isn't a deploy to the hub, or a hub with one connection, queues nothing.
     * @param rel the release just deployed (with Target_Org__r.Role__c)
     */
    public static void queue(RLY_Release__c rel) {
        if (rel == null || rel.Id == null || !RlyBackPromoteQueue.isHubDeploy(rel)) {
            return;
        }
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        if (conns.size() < 2) {
            return;
        }
        List<Entry> entries = RlyProdSyncEntries.othersThan(conns, RlyReleaseStore.gitFor(rel));
        if (!entries.isEmpty()) {
            RlyProdSyncStore.saveEntries(rel.Id, JSON.serialize(entries), QUEUED);
        }
    }

    /**
     * @description One step for a deployed release whose page reads it with nothing else running: raises the first queued
     * entry's release, or reads the first running one (callouts first, then the saves). Nothing else may call out after.
     * @param releaseId the deployed release
     * @return true when it did a step (the caller does nothing else in this request)
     */
    public static Boolean step(Id releaseId) {
        RLY_Release__c rel = RlyProdSyncStore.deployed(releaseId);
        List<Entry> entries = entriesOf(rel == null ? null : rel.Prod_Sync__c);
        for (Entry e : entries) {
            if (e.status == QUEUED) {
                RlyProdSyncRun.Raised r = RlyProdSyncRun.raise(e, rel); // callouts: the retrieve in the hub org
                RlyProdSyncRun.save(r, e);
                RlyProdSyncStore.saveEntries(rel.Id, JSON.serialize(entries), RlyProdSyncEntries.stateOf(entries));
                return true;
            }
        }
        Map<Id, RLY_Release__c> raised = RlyProdSyncStore.raised(RlyProdSyncEntries.releaseIdsOf(entries));
        for (Entry e : entries) {
            RLY_Release__c sync = raised.get(e.releaseId);
            if (e.status == STARTED && sync != null && RlyStatusReader.OPEN_STATUSES.contains(sync.Status__c)) {
                RlyStatusReader.advance(sync.Id);
                return true;
            }
        }
        return false;
    }

    /**
     * @description When an automatic release's checks pass: starts its merge (mode merge, no target environment: a merge
     * only, no deploy), without an approver: production's own deploy was approved. Callouts only; the caller saves.
     * @param rel the release as this read moved it
     * @param git the Git provider (its repository)
     */
    public static void afterChecks(RLY_Release__c rel, RlyGit git) {
        if (!isProdSync(rel) || rel.Status__c != 'Ready for approval') {
            return;
        }
        git.startPipeline(RlyPipelineRun.inputs(rel, 'merge', rel.Source_Branch__c));
        rel.Pending_Run__c = 'merge';
        rel.Status__c = 'Deploying';
        rel.Deploy_Status__c = 'Deploying';
        rel.Approval_Status__c = 'Approved';
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = 'Production was deployed: the hub keeps the other repositories\' prod branches in step.';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    /**
     * @description What the deployed release's page shows: one line per other repository.
     * @param raw Prod_Sync__c
     * @return the lines (empty when there are none)
     */
    public static List<View> views(String raw) {
        List<Entry> entries = entriesOf(raw);
        Map<Id, RLY_Release__c> raised = RlyProdSyncStore.raised(RlyProdSyncEntries.releaseIdsOf(entries));
        List<View> out = new List<View>();
        for (Entry e : entries) {
            out.add(RlyProdSyncEntries.viewOf(e, raised.get(e.releaseId)));
        }
        return out;
    }

    /**
     * @description Try again: the entry is queued again, so the next read raises a new automatic release. Approvers and
     * admins.
     * @param releaseId the deployed release
     * @param connectionId the other connection
     */
    @AuraEnabled
    public static void retry(Id releaseId, Id connectionId) {
        if (!RlyApprovalService.canApprove() && !RlyOrgController.isAdmin()) {
            throw new AuraHandledException('Only approvers and admins can try it again.');
        }
        RLY_Release__c rel = RlyProdSyncStore.deployed(releaseId);
        List<Entry> entries = entriesOf(rel == null ? null : rel.Prod_Sync__c);
        for (Entry e : entries) {
            if (e.connectionId == connectionId) {
                e.status = QUEUED;
                e.message = null;
                e.releaseId = null;
            }
        }
        RlyProdSyncStore.saveEntries(releaseId, JSON.serialize(entries), RlyProdSyncEntries.stateOf(entries));
    }

    /**
     * @description A release's entries, as saved.
     * @param raw Prod_Sync__c
     * @return the entries (empty when there are none or they can't be read)
     */
    public static List<Entry> entriesOf(String raw) {
        if (String.isBlank(raw)) {
            return new List<Entry>();
        }
        try {
            return (List<Entry>) JSON.deserialize(raw, List<Entry>.class);
        } catch (Exception e) {
            return new List<Entry>();
        }
    }
}
