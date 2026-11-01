/**
 * @description What people do to a release once its checks are done: approve (merge and deploy), reject,
 * bypass a blocking code scan, or run the checks again. Approving, rejecting and bypassing need the
 * RLY_Approver (or RLY_Admin) custom permission; approveAs and rejectAs act for an approver the caller checked
 * (RlySlackAction checks a linked Slack user's permission sets). A hotfix into an org that needs two approvers waits for
 * a second one (RlyTwoApprovers). A deploy whose manual steps before deploy aren't done yet is approved but waits
 * (RlyManualStepGate); the deployment team's last check starts it (RlyManualStepCheck). Callouts come first (Slack too, when the new status is an event)
 * and the saves last.
 */
public with sharing class RlyApprovalService {

    /**
     * @description Whether the current user approves releases.
     * @return true for approvers and admins
     */
    public static Boolean canApprove() {
        return FeatureManagement.checkPermission('RLY_Approver') || FeatureManagement.checkPermission('RLY_Admin');
    }

    /**
     * @description Code scan blocked it: an approver accepts the findings, with a reason.
     * @param releaseId the release
     * @param reason why the findings are accepted (at least 10 characters)
     * @return the release as saved
     */
    public static RLY_Release__c acceptScanFindings(Id releaseId, String reason) {
        RlyHubGuard.requireHub();
        requireApprover();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || rel.Status__c != 'Checks failed' || (rel.Scan_Status__c != 'Failed' && rel.Scan_Status__c != 'Error')) {
            throw new RlyReleaseException('Only a release whose code scan failed can bypass it.');
        }
        if (String.isBlank(reason) || reason.trim().length() < 10) {
            throw new RlyReleaseException('Say why the findings are accepted (at least 10 characters).');
        }
        String oldStatus = rel.Status__c;
        rel.Scan_Status__c = 'Bypassed';
        rel.Scan_Bypassed_By__c = UserInfo.getUserId();
        rel.Scan_Bypass_Reason__c = reason.trim().left(2000);
        RlyCheckReader.decide(rel);
        RlyAutoApproval.afterBypass(rel, oldStatus);
        saveAndNotify(rel, oldStatus);
        return rel;
    }

    /**
     * @description Runs the code scan and validation again (after a fix on the branch, or a change in the target org).
     * @param releaseId the release
     * @return the release as saved
     */
    public static RLY_Release__c rerunChecks(Id releaseId) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || (rel.Status__c != 'Checks failed' && rel.Status__c != 'Ready for approval') || rel.PR_Number__c == null) {
            throw new RlyReleaseException('Checks can run again on an open pull request that isn\'t approved yet.');
        }
        RlyApprovalRuns.startChecks(rel, RlyReleaseStore.git(), 'check');
        RlyReleaseStore.save(rel);
        return rel;
    }

    /**
     * @description Approves the release as the current user: the pipeline merges the pull request and deploys it.
     * @param releaseId the release
     * @param comment the approver's comment, or null
     * @return the release as saved
     */
    public static RLY_Release__c approveRelease(Id releaseId, String comment) {
        requireApprover();
        RlyApprover.requireSalesforce(RlyReleaseStore.release(releaseId));
        return approveAs(releaseId, RlyApprover.currentUser(comment));
    }

    /**
     * @description Approves the release for an approver the caller has already checked (the current user, or a linked
     * Slack user). When the target branch moved after the checks passed, the checks run again instead of the merge.
     * When manual steps before deploy are still to do, the approval is recorded and the release waits for them.
     * @param releaseId the release
     * @param who who approves, and where
     * @return the release as saved
     */
    public static RLY_Release__c approveAs(Id releaseId, RlyApprover who) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || rel.Status__c != 'Ready for approval') {
            throw new RlyReleaseException('Only a release that\'s ready for approval can be approved.');
        }
        String oldStatus = rel.Status__c;
        if (RlyManualStepGate.waitsInstead(rel, who)) {
            RlyReleaseStore.save(rel); // the first of two approvals, or the deploy waits for manual steps: no event
            return rel;
        }
        RLY_Release__c prior = rel.clone(true, true, true, true);
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        RlyGit git = RlyGit.forConnection(conn);
        if (RlyApprovalRuns.targetMoved(rel, git)) {
            RlyApprovalRuns.startChecks(rel, conn, RlyPipelineRun.RECHECK);
        } else {
            RlyApprovalRuns.startMerge(rel, git, who);
            RlyTwoApprovers.keepBoth(rel, prior);
        }
        saveAndNotify(rel, oldStatus);
        return rel;
    }

    /**
     * @description Rejects the release as the current user and closes its pull request (with the comment on it).
     * @param releaseId the release
     * @param comment why it's rejected (required)
     * @return the release as saved
     */
    public static RLY_Release__c rejectRelease(Id releaseId, String comment) {
        requireApprover();
        return rejectAs(releaseId, RlyApprover.currentUser(comment));
    }

    /**
     * @description Rejects the release for an approver the caller has already checked, and closes its pull request.
     * @param releaseId the release
     * @param who who rejects, where, and why (comment required)
     * @return the release as saved
     */
    public static RLY_Release__c rejectAs(Id releaseId, RlyApprover who) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || (rel.Status__c != 'Ready for approval' && rel.Status__c != 'Checks failed')) {
            throw new RlyReleaseException('Only a release waiting for approval can be rejected.');
        }
        if (String.isBlank(who.comment)) {
            throw new RlyReleaseException('Say why it\'s rejected, so the developer knows what to change.');
        }
        String oldStatus = rel.Status__c;
        if (rel.PR_Number__c != null) {
            closePullRequest(rel, who);
        }
        rel.Status__c = 'Rejected';
        rel.Approval_Status__c = 'Rejected';
        rel.Approved_By__c = who.userId;
        rel.Approved_Via__c = who.via;
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = who.comment.left(2000);
        saveAndNotify(rel, oldStatus);
        return rel;
    }

    // A pull request that can't be commented on or closed doesn't stop the rejection; the page says so.
    private static void closePullRequest(RLY_Release__c rel, RlyApprover who) {
        List<String> problems = RlyPullRequestClose.closeWithComment(rel,
            'Rejected in ' + who.via + ' by ' + who.name + ': ' + who.comment.left(1000));
        if (!problems.isEmpty()) {
            rel.Error_Message__c = ('Rejected, but ' + String.join(problems, '; ')).left(2000);
        }
    }

    // Slack hears about a status that's an event (callout first), then the release and the Slack result are saved.
    private static void saveAndNotify(RLY_Release__c rel, String oldStatus) {
        RlySlack.notifyTransition(rel, oldStatus);
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
    }

    private static void requireApprover() {
        if (!canApprove()) {
            throw new RlyReleaseException('Only approvers can do this (permission set Release Relay Approver).');
        }
    }
}
