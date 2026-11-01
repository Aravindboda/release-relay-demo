/**
 * @description Promotions: a release record (Release_Type__c Promotion) from a stage org to its next stop on the route,
 * carrying the merge commits of releases already deployed to that stage (Carried_Releases__c, oldest deploy first;
 * each carried release points back with Promoted_In__c), with the carried releases' manual step runs for the next stop
 * (RlyManualStepRuns.forPromotion). It is saved queued (Status Submitted) and started on the next
 * read of its page (pipeline mode promote, branch promote/rel-xxxxx), because the run is named after the record and
 * a callout can't follow the insert in one transaction. From there it is checked, approved, merged and deployed like
 * any release.
 */
public with sharing class RlyPromotion {

    /** @description Release_Type__c of a release raised from a developer org (blank means this too). */
    public static final String TYPE_RELEASE = 'Release';
    /** @description Release_Type__c of a promotion. */
    public static final String TYPE_PROMOTION = 'Promotion';
    /** @description Release_Type__c of a back promote (sync). */
    public static final String TYPE_BACK_PROMOTE = 'Back_Promote';
    /** @description Status of a promotion or sync saved but not started yet. */
    public static final String QUEUED = 'Submitted';
    /** @description The pipeline mode (and Pending_Run__c) of a promotion's first run. */
    public static final String MODE = 'promote';

    /** @description What the Promote tab sends. */
    public class Request {
        /** @description The stage the releases are deployed to. */
        public Id stageId;
        /** @description The releases to promote. */
        public List<Id> releaseIds;
        /** @description The promotion's title. */
        public String title;
    }

    /**
     * @description A release's type.
     * @param rel the release, with Release_Type__c
     * @return Release, Promotion or Back_Promote (blank is Release)
     */
    public static String typeOf(RLY_Release__c rel) {
        return rel == null || String.isBlank(rel.Release_Type__c) ? TYPE_RELEASE : rel.Release_Type__c;
    }

    /**
     * @description Whether a release is a promotion.
     * @param rel the release
     * @return true for promotions
     */
    public static Boolean isPromotion(RLY_Release__c rel) {
        return typeOf(rel) == TYPE_PROMOTION;
    }

    /**
     * @description Checks the request and saves the promotion, queued, with the carried releases marked. No callouts.
     * @param req the request
     * @return the promotion's Id
     */
    public static Id create(Request req) {
        String title = checkedTitle(req);
        RLY_Org__c stage = RlyReleaseStore.org(req.stageId);
        if (stage == null || stage.Role__c != 'Stage') {
            throw new RlyReleaseException('Pick a stage to promote from.');
        }
        RLY_Org__c nextOrg = nextOrgOf(stage);
        RLY_Git_Connection__c conn = connectedGit();
        List<RLY_Release__c> carried = picked(req, stage);
        RLY_Release__c promotion = build(stage, nextOrg, conn);
        promotion.Title__c = title;
        fill(promotion, carried);
        List<RLY_Release_Item__c> items = RlyCarried.items(carried);
        List<String> deletions = RlyCarried.deletions(carried);
        promotion.Component_Count__c = RlyCarried.addedCount(items);
        promotion.Deletion_Count__c = deletions.size();
        promotion.Deletions__c = deletions.isEmpty() ? null : String.join(deletions, ',').left(RlyDeletions.MAX_LENGTH);
        RlyPromoteStore.insertPromotion(promotion, items, new Map<Id, RLY_Release__c>(carried).keySet());
        RlyManualStepRuns.forPromotion(promotion, nextOrg);
        return promotion.Id;
    }

    private static RLY_Org__c nextOrgOf(RLY_Org__c stage) {
        RLY_Org__c nextOrg = RlyHotfix.nextStop(stage.Id, RlyReleaseStore.routeOrgs());
        if (nextOrg == null) {
            throw new RlyReleaseException(stage.Name + ' has no next stop on the route to promote to.');
        }
        if (String.isBlank(nextOrg.Branch__c)) {
            throw new RlyReleaseException(nextOrg.Name + ' has no branch: set it on the Pipeline tab.');
        }
        return nextOrg;
    }

    private static RLY_Git_Connection__c connectedGit() {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null || conn.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        return conn;
    }

    private static String checkedTitle(Request req) {
        if (req == null || req.releaseIds == null || req.releaseIds.isEmpty()) {
            throw new RlyReleaseException('Pick at least one release to promote.');
        }
        if (String.isBlank(req.title) || req.title.trim().length() > 200) {
            throw new RlyReleaseException('Give the promotion a title (up to 200 characters).');
        }
        return req.title.trim();
    }

    // The picked releases, each still waiting in the stage, oldest deploy first.
    private static List<RLY_Release__c> picked(Request req, RLY_Org__c stage) {
        Map<Id, RLY_Release__c> ready = new Map<Id, RLY_Release__c>(RlyPromoteStore.readyIn(new Set<Id>{ stage.Id }));
        Set<Id> ids = new Set<Id>(req.releaseIds);
        if (!ready.keySet().containsAll(ids)) {
            throw new RlyReleaseException('Some of these releases aren\'t waiting in ' + stage.Name + ' any more. Reload the list.');
        }
        return RlyPromoteStore.byIds(ids);
    }

    private static RLY_Release__c build(RLY_Org__c stage, RLY_Org__c nextOrg, RLY_Git_Connection__c conn) {
        return new RLY_Release__c(Release_Type__c = TYPE_PROMOTION, Mode__c = 'Existing branch', Request_Type__c = 'Changes',
            Status__c = QUEUED, Source_Org__c = stage.Id, Target_Org__c = nextOrg.Id, Org_Label__c = stage.Name.left(40),
            Target_Branch__c = nextOrg.Branch__c.trim(), Source_Environment__c = stage.Git_Environment__c,
            Target_Environment__c = nextOrg.Git_Environment__c, Deletion_Count__c = 0,
            Scan_Status__c = conn.Code_Scan__c ? 'Pending' : 'Not configured',
            Validation_Status__c = String.isBlank(nextOrg.Git_Environment__c) ? 'Not configured' : 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Last_Synced__c = System.now());
    }

    // Tests (union), hotfix flag and reasons, carried Ids and names.
    private static void fill(RLY_Release__c promotion, List<RLY_Release__c> carried) {
        Set<String> tests = new Set<String>();
        List<String> reasons = new List<String>();
        List<String> ids = new List<String>();
        List<String> names = new List<String>();
        promotion.Is_Hotfix__c = false;
        for (RLY_Release__c r : carried) {
            tests.addAll(RlyReleasePhase.tests(r));
            ids.add(r.Id);
            names.add(r.Name);
            if (r.Is_Hotfix__c == true) {
                promotion.Is_Hotfix__c = true;
                reasons.add(String.isBlank(r.Hotfix_Reason__c) ? r.Name : r.Hotfix_Reason__c.trim());
            }
        }
        promotion.Test_Classes__c = String.join(new List<String>(tests), ',');
        promotion.Hotfix_Reason__c = reasons.isEmpty() ? null : String.join(reasons, '; ').left(RlyHotfix.REASON_LENGTH);
        promotion.Carried_Releases__c = String.join(ids, ',');
        promotion.Description__c = ('Promotes ' + String.join(names, ', ')).left(5000);
    }

    /**
     * @description Starts a queued promotion's first run (mode promote): the pipeline makes the branch from the next
     * stop's branch and picks the carried merge commits onto it. Callouts only: the caller saves the release.
     * @param rel the promotion (Submitted)
     * @param git the Git provider
     */
    public static void dispatch(RLY_Release__c rel, RlyGit git) {
        String branch = RlyPipelineRun.branchName(rel);
        git.startPipeline(RlyPipelineRun.inputs(rel, MODE, branch));
        rel.Source_Branch__c = branch;
        rel.Status__c = 'Workflow running';
        rel.Pending_Run__c = MODE;
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }
}
