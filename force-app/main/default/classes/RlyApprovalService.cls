/**
 * @description What people do to a release once its checks are done: approve (merge and deploy), reject,
 * bypass a blocking code scan, or run the checks again. Approving, rejecting and bypassing need the
 * RLY_Approver (or RLY_Admin) custom permission. Callouts come first and the one save last.
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
        requireApprover();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || rel.Status__c != 'Checks failed' || (rel.Scan_Status__c != 'Failed' && rel.Scan_Status__c != 'Error')) {
            throw new RlyReleaseException('Only a release whose code scan failed can bypass it.');
        }
        if (String.isBlank(reason) || reason.trim().length() < 10) {
            throw new RlyReleaseException('Say why the findings are accepted (at least 10 characters).');
        }
        rel.Scan_Status__c = 'Bypassed';
        rel.Scan_Bypassed_By__c = UserInfo.getUserId();
        rel.Scan_Bypass_Reason__c = reason.trim().left(2000);
        RlyCheckReader.decide(rel);
        RlyReleaseStore.save(rel);
        return rel;
    }

    /**
     * @description Runs the code scan and validation again (after a fix on the branch, or a change in the target org).
     * @param releaseId the release
     * @return the release as saved
     */
    public static RLY_Release__c rerunChecks(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || (rel.Status__c != 'Checks failed' && rel.Status__c != 'Ready for approval') || rel.PR_Number__c == null) {
            throw new RlyReleaseException('Checks can run again on an open pull request that isn\'t approved yet.');
        }
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        RlyGit.forConnection(conn).startPipeline(RlyPipelineRun.inputs(rel, 'check', rel.Source_Branch__c));
        rel.Status__c = 'Validating';
        rel.Pending_Run__c = 'check';
        rel.Checks_Requested__c = System.now();
        rel.Scan_Status__c = conn.Code_Scan__c ? 'Pending' : 'Not configured';
        rel.Validation_Status__c = String.isBlank(rel.Target_Environment__c) ? 'Not configured' : 'Pending';
        rel.Scan_Bypassed_By__c = null;
        rel.Scan_Bypass_Reason__c = null;
        rel.Error_Message__c = null;
        RlyReleaseStore.save(rel);
        return rel;
    }

    /**
     * @description Approves the release: the pipeline merges the pull request and deploys it to the target org.
     * @param releaseId the release
     * @param comment the approver's comment, or null
     * @return the release as saved
     */
    public static RLY_Release__c approveRelease(Id releaseId, String comment) {
        requireApprover();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || rel.Status__c != 'Ready for approval') {
            throw new RlyReleaseException('Only a release that\'s ready for approval can be approved.');
        }
        RlyGit.forConnection(RlyReleaseStore.git()).startPipeline(RlyPipelineRun.inputs(rel, 'merge', rel.Source_Branch__c));
        rel.Status__c = 'Deploying';
        rel.Approval_Status__c = 'Approved';
        rel.Approved_By__c = UserInfo.getUserId();
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = comment == null ? null : comment.left(2000);
        rel.Deploy_Status__c = 'Deploying';
        rel.Pending_Run__c = 'merge';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
        RlyReleaseStore.save(rel);
        return rel;
    }

    /**
     * @description Rejects the release with a comment and closes its pull request (with the comment on it).
     * @param releaseId the release
     * @param comment why it's rejected (required)
     * @return the release as saved
     */
    public static RLY_Release__c rejectRelease(Id releaseId, String comment) {
        requireApprover();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null || (rel.Status__c != 'Ready for approval' && rel.Status__c != 'Checks failed')) {
            throw new RlyReleaseException('Only a release waiting for approval can be rejected.');
        }
        if (String.isBlank(comment)) {
            throw new RlyReleaseException('Say why it\'s rejected, so the developer knows what to change.');
        }
        if (rel.PR_Number__c != null) {
            closePullRequest(rel, comment);
        }
        rel.Status__c = 'Rejected';
        rel.Approval_Status__c = 'Rejected';
        rel.Approved_By__c = UserInfo.getUserId();
        rel.Approved_On__c = System.now();
        rel.Approval_Comment__c = comment.left(2000);
        RlyReleaseStore.save(rel);
        return rel;
    }

    // A pull request that can't be closed doesn't stop the rejection; the page says so.
    private static void closePullRequest(RLY_Release__c rel, String comment) {
        try {
            RlyGit.forConnection(RlyReleaseStore.git()).closePullRequest(rel.PR_Number__c.intValue(),
                'Rejected in Release Relay by ' + UserInfo.getName() + ': ' + comment.left(1000));
        } catch (Exception e) {
            rel.Error_Message__c = ('Rejected, but the pull request couldn\'t be closed: ' + e.getMessage()).left(2000);
        }
    }

    private static void requireApprover() {
        if (!canApprove()) {
            throw new RlyReleaseException('Only approvers can do this (permission set Release Relay Approver).');
        }
    }
}
