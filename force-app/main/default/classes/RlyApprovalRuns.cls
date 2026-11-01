/**
 * @description The pipeline runs an approval starts: the merge (and deploy), or the checks again when the target
 * branch moved after they passed (the validation's mergedWith isn't the target's latest commit any more). A target
 * org approved in the Git provider starts its merge as soon as its checks pass; the provider's reviewers approve it.
 * Each run gets a new token (RlyPipelineRun.inputs). A release with only manual steps has no run: its deploy is its
 * manual steps (RlyManualOnly.startDeploy). Callouts only: callers save the release afterwards.
 */
public with sharing class RlyApprovalRuns {

    /**
     * @description Starts the merge and deploy (for a back promote: the sync run) and records the approval.
     * @param rel the release
     * @param git the Git provider
     * @param who who approved, and where
     */
    public static void startMerge(RLY_Release__c rel, RlyGit git, RlyApprover who) {
        dispatchMerge(rel, git);
        recordApproval(rel, who);
    }

    /**
     * @description Starts the merge and deploy (for a back promote: the sync run) of an approved release, without
     * recording an approval (the approval was recorded while it waited for manual steps).
     * @param rel the release
     * @param git the Git provider
     */
    public static void dispatchMerge(RLY_Release__c rel, RlyGit git) {
        if (RlyManualOnly.isManualOnly(rel)) {
            RlyManualOnly.startDeploy(rel); // nothing to merge: Deploying until its manual steps are done
            return;
        }
        if (RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE) {
            RlyBackPromoteRun.dispatch(rel, git);
        } else {
            git.startPipeline(RlyPipelineRun.inputs(rel, 'merge', rel.Source_Branch__c));
            rel.Pending_Run__c = 'merge';
        }
        rel.Status__c = 'Deploying';
        rel.Deploy_Status__c = 'Deploying';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    /**
     * @description Records the approval on the release (the status is left as it is).
     * @param rel the release
     * @param who who approved, and where
     */
    public static void recordApproval(RLY_Release__c rel, RlyApprover who) {
        rel.Approval_Status__c = 'Approved';
        rel.Approved_By__c = who.userId;
        rel.Approved_Via__c = who.via;
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = who.comment == null ? null : who.comment.left(2000);
    }

    /**
     * @description Runs the code scan and validation again (mode check).
     * @param rel the release
     * @param conn the Git connection
     * @param pendingRun check, or RlyPipelineRun.RECHECK when the target moved after the checks passed
     */
    public static void startChecks(RLY_Release__c rel, RLY_Git_Connection__c conn, String pendingRun) {
        RlyGit.forConnection(conn).startPipeline(RlyPipelineRun.inputs(rel, 'check', rel.Source_Branch__c));
        rel.Status__c = 'Validating';
        rel.Pending_Run__c = pendingRun;
        rel.Checks_Requested__c = System.now();
        rel.Scan_Status__c = RlyScanRule.statusFor(conn, RlyScanRule.targetOf(rel));
        rel.Validation_Status__c = String.isBlank(rel.Target_Environment__c) ? 'Not configured' : 'Pending';
        rel.Scan_Bypassed_By__c = null;
        rel.Scan_Bypass_Reason__c = null;
        rel.Error_Message__c = null;
    }

    /**
     * @description Whether the target branch has new commits since the validation (mergedWith) ran.
     * @param rel the release, with Validation_Result__c
     * @param git the Git provider
     * @return true when the target's latest commit isn't the one the release was validated with
     */
    public static Boolean targetMoved(RLY_Release__c rel, RlyGit git) {
        String validatedWith = mergedWith(rel.Validation_Result__c);
        if (String.isBlank(validatedWith)) {
            return false;
        }
        String head = git.branchHead(rel.Target_Branch__c);
        return head != null && !head.equalsIgnoreCase(validatedWith);
    }

    /**
     * @description The target commit a validation result was merged with.
     * @param resultJson Validation_Result__c
     * @return the SHA, or null (older results, or no merged validation)
     */
    public static String mergedWith(String resultJson) {
        if (String.isBlank(resultJson)) {
            return null;
        }
        try {
            Object sha = ((Map<String, Object>) JSON.deserializeUntyped(resultJson)).get('mergedWith');
            return sha == null ? null : String.valueOf(sha);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Whether the deploy into the release's target org also waits for the Git provider's reviewers.
     * @param rel the release, with its target org's approval fields
     * @return true when Git review is required
     */
    public static Boolean approvedInGit(RLY_Release__c rel) {
        return RlyApprover.gitReview(rel.Target_Org__r);
    }

    /**
     * @description Starts the deploy of an approved release when the deployment team finished its manual steps before
     * deploy (RlyManualStepCheck), as the approval would have: the merge (or the queued sync run, or for a release with
     * only manual steps its manual steps in the target), or the checks again when the target moved since they passed (the
     * approval is then cleared: the release is approved again after the checks). A failure to start is kept on the release.
     * @param rel the release
     */
    public static void startAfterSteps(RLY_Release__c rel) {
        try {
            RLY_Git_Connection__c conn = RlyReleaseStore.git();
            RlyGit git = RlyGit.forConnection(conn);
            if (RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE && rel.Status__c == RlyPromotion.QUEUED) {
                RlyBackPromoteRun.dispatch(rel, git);
            } else if (targetMoved(rel, git)) {
                startChecks(rel, conn, RlyPipelineRun.RECHECK);
                rel.Approval_Status__c = 'Pending';
                rel.Approved_By__c = null;
                rel.Approved_On__c = null;
                rel.Second_Approved_By__c = null;
                rel.Second_Approved_On__c = null;
            } else {
                dispatchMerge(rel, git);
            }
        } catch (Exception e) {
            rel.Error_Message__c = ('The manual steps are done, but the deploy couldn\'t start: ' + e.getMessage()).left(2000);
        }
    }
}
