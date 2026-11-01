/**
 * @description Rolls a deployed release back in one org: the pipeline (mode rollback) deploys the snapshot it took just
 * before that deploy, and removes what the deploy added. Git is not changed (a follow-up release fixes the branch) and
 * the release keeps its status; the rollback lives in the release's rollback fields (RlyRollbackState). start
 * dispatches the run and marks the rollback Running; advance reads results/<request>/rollback.json like every other
 * result (its attempt must be the rollback's token) and records Rolled back or Failed, with a history event and the
 * Slack card's line (RlyRollbackRun). Only the hub does this, for Release Relay admins and the deployment team. Callouts come first
 * (the run, the result, the Slack card) and the saves last; no async Apex.
 */
public with sharing class RlyRollback {

    /** @description Tests choice: the release's own tests (RunSpecifiedTests). */
    public static final String TESTS_RELEASE = 'release';
    /** @description Tests choice: every local test (the pipeline's RunLocalTests when Apex is in a production rollback). */
    public static final String TESTS_ALL = 'all';

    /** @description The pipeline mode of a rollback run. */
    public static final String MODE = 'rollback';
    private static final Integer REASON_MAX = 255;

    /** @description What the confirm dialog sends. */
    public class Request {
        /** @description The org to roll back. */
        public Id orgId;
        /** @description Why (required, up to 255 characters). */
        public String reason;
        /** @description release (the release's tests, the default) or all (all local tests); production only. */
        public String tests;
    }

    /**
     * @description Whether the current user may roll releases back: Release Relay admins and the deployment team.
     * @return true for them
     */
    public static Boolean mayRollBack() {
        return FeatureManagement.checkPermission('RLY_Admin') || FeatureManagement.checkPermission('RLY_Deploy_Team');
    }

    /**
     * @description Starts a rollback: dispatches the pipeline run (mode rollback), then marks the rollback Running.
     * @param releaseId the release
     * @param req the org, the reason and the tests choice
     */
    public static void start(Id releaseId, Request req) {
        String reason = checked(releaseId, req);
        RlyRollbackPlan.OrgChoice org = RlyRollbackPlan.choiceFor(releaseId, req.orgId);
        if (org.hasSnapshot != true) {
            throw new RlyReleaseException(org.orgName + ' can\'t be rolled back: ' + org.why + '.');
        }
        Boolean apex = snapshotHasApex(releaseId, org);
        String testsChoice = isAllLocal(org, req.tests) ? TESTS_ALL : (apex ? TESTS_RELEASE : 'none');
        List<String> tests = testsChoice == TESTS_RELEASE ? org.tests : new List<String>();
        String token = RlyPipelineRun.newToken();
        RlyGit.forConnection(RlyReleaseStore.git()).startPipeline(inputs(org, token, tests)); // the callout, before any DML
        RLY_Release__c row = new RLY_Release__c(Id = releaseId, Rollback_Status__c = RlyRollbackState.RUNNING, Rollback_Org__c = org.orgId,
            Rollback_By__c = UserInfo.getUserId(), Rollback_On__c = System.now(), Rollback_Reason__c = reason.left(REASON_MAX),
            Rollback_Token__c = token, Rollback_Result__c = JSON.serialize(new Map<String, Object>{ 'request' => org.ownerName,
                'snapshot' => org.snapshotPath, 'environment' => org.environment, 'branch' => org.branch,
                'production' => org.production, 'byPromotion' => org.byPromotion, 'tests' => tests,
                'testsChoice' => testsChoice }));
        row.Rollback_Org__r = new RLY_Org__c(Id = org.orgId, Name = org.orgName);
        RlyRollbackRun.record(row, null);
    }

    // The hub, the permission, an org and a reason, and no rollback running. Returns the reason.
    private static String checked(Id releaseId, Request req) {
        RlyHubGuard.requireHub();
        if (!mayRollBack()) {
            throw new RlyReleaseException('Only Release Relay admins and the deployment team can roll a release back.');
        }
        String reason = req == null ? null : req.reason;
        if (String.isBlank(reason) || req.orgId == null) {
            throw new RlyReleaseException('Pick the org to roll back and say why.');
        }
        if (RlyRollbackState.isRunning(releaseId)) {
            throw new RlyReleaseException('A rollback of this release is running. Wait for it to finish.');
        }
        return reason.trim();
    }

    // All local tests only when chosen in production (only production shows the choice; the pipeline then runs
    // RunLocalTests). Otherwise the release's tests (the snapshot owner's) run whenever Apex is in the snapshot, in any
    // org, so a rollback never runs every org test unasked; without Apex none run.
    private static Boolean isAllLocal(RlyRollbackPlan.OrgChoice org, String choice) {
        return org.production == true && choice == TESTS_ALL;
    }

    // Whether Apex is in the snapshot (its manifest, a callout before any DML). A manifest that can't be read counts as
    // Apex, so the release's tests are sent rather than none.
    private static Boolean snapshotHasApex(Id releaseId, RlyRollbackPlan.OrgChoice org) {
        try {
            return RlyRollbackPreview.preview(releaseId, org.orgId).apex == true;
        } catch (Exception e) {
            return !org.tests.isEmpty();
        }
    }

    // Same as a deploy dispatch with mode rollback: branch, target and title are required by the pipeline but unused.
    private static Map<String, String> inputs(RlyRollbackPlan.OrgChoice org, String token, List<String> tests) {
        Map<String, Object> options = new Map<String, Object>{ 'snapshotPath' => org.snapshotPath, 'attempt' => token };
        if (!tests.isEmpty()) {
            options.put('tests', tests);
        }
        String branch = String.isBlank(org.branch) ? org.environment : org.branch;
        return new Map<String, String>{
            'request_id' => org.ownerName, 'mode' => MODE, 'environment' => 'release-relay',
            'target_environment' => org.environment, 'branch' => branch, 'target' => branch,
            'title' => (org.ownerName + ': roll back ' + org.orgName).left(200), 'components' => '', 'deletions' => '',
            'options' => JSON.serialize(options)
        };
    }
}
