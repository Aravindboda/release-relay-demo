/**
 * @description What people do to a release once its checks are done: approve (merge and deploy), reject,
 * bypass a blocking code scan, or run the checks again. Approving, rejecting and bypassing need the
 * RLY_Approver (or RLY_Admin) custom permission; approveAs and rejectAs act for an approver the caller checked
 * (RlySlackAction checks a linked Slack user's permission sets). A hotfix into an org that needs two approvers waits for
 * a second one (RlyTwoApprovers). A deploy whose manual steps before deploy aren't done yet is approved but waits
 * (RlyManualStepGate); the deployment team's last check starts it (RlyManualStepCheck). A release with only manual steps
 * has nothing to merge: approving it starts its manual steps in the target (RlyManualOnly). Callouts come first (Slack
 * too: the release's card is edited on every change, a first approval or a deploy waiting for manual steps included, and
 * the selected events add their messages) and the saves last. A Slack failure never stops the change.
 */
public with sharing class RlyApprovalService {

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
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        rel.Scan_Status__c = 'Bypassed';
        rel.Scan_Bypassed_By__c = UserInfo.getUserId();
        rel.Scan_Bypass_Reason__c = reason.trim().left(2000);
        RlyCheckReader.decide(rel);
        RlyAutoApproval.afterBypass(rel, oldStatus);
        saveAndNotify(before, rel);
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
        RlyReleaseAccess.requireRerun(rel); // build 48: the raiser, an approver, the deployment team or an admin
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        RlyApprovalRuns.startChecks(rel, RlyReleaseStore.gitFor(rel), 'check');
        saveAndNotify(before, rel);
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
        RlyProdApproval.require(rel, who); // build 49: production needs the Production Approver add-on when the hub says so
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        if (RlyManualStepGate.waitsInstead(rel, who)) {
            saveAndNotify(before, rel); // the first of two approvals, or the deploy waits for manual steps: the card says so
            return rel;
        }
        RLY_Release__c prior = RlySlackCardState.snapshot(rel);
        RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
        RlyGit git = RlyGit.forConnection(conn);
        if (RlyApprovalRuns.targetMoved(rel, git)) {
            RlyApprovalRuns.startChecks(rel, conn, RlyPipelineRun.RECHECK);
        } else {
            RlyApprovalRuns.startMerge(rel, git, who);
            RlyTwoApprovers.keepBoth(rel, prior);
        }
        saveAndNotify(before, rel);
        if (rel.Status__c == 'Deployed') {
            RlyBackPromoteQueue.afterDeploy(rel); // manual steps only, nothing left to do: deployed on approval
        }
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
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        List<String> prProblems = rel.PR_Number__c == null ? null : closePullRequest(rel, who);
        rel.Status__c = 'Rejected';
        rel.Approval_Status__c = 'Rejected';
        rel.Approved_By__c = who.userId;
        rel.Approved_Via__c = who.via;
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = who.comment.left(2000);
        saveAndNotify(before, rel);
        RlyCredentialPrAccess.afterClose(rel, prProblems); // the Credentials page's Git token row (build 52)
        return rel;
    }

    // A pull request that can't be commented on or closed doesn't stop the rejection; the page says so.
    private static List<String> closePullRequest(RLY_Release__c rel, RlyApprover who) {
        List<String> problems = RlyPullRequestClose.closeWithComment(rel,
            'Rejected in ' + who.via + ' by ' + who.name + ': ' + who.comment.left(1000));
        if (!problems.isEmpty()) {
            rel.Error_Message__c = ('Rejected, but ' + String.join(problems, '; ')).left(2000);
        }
        return problems;
    }

    // Slack hears about the change (callouts first: the card is edited, a selected event adds its messages), then the
    // release and the Slack result are saved.
    private static void saveAndNotify(RLY_Release__c before, RLY_Release__c rel) {
        RlySlackCardSync.notifyChange(before, rel);
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
    }

    private static void requireApprover() {
        if (!RlyReleaseAccess.isApprover()) {
            throw new RlyReleaseException('Only approvers can do this (permission set Release Relay Approver).');
        }
    }
}
