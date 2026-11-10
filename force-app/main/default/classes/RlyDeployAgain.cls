/**
 * @description Deploy again (build 58.1, D32): an approved release whose deploy failed for a reason that passes (for
 * example the target org was out of daily API calls) starts the same merge-and-deploy run again. The pipeline sees the
 * pull request already merged and deploys the approved head; the approval stays. An approver, the deployment team or
 * an admin can do it. Logged in History as "Deploy started again", with the error it follows.
 */
public with sharing class RlyDeployAgain {

    /** @description History event of a deploy started again. */
    public static final String EVENT = 'Deploy_Again';
    private static final String DEPLOY_FAILED = 'Deploy failed';

    /**
     * @description Whether the current user may deploy this release again.
     * @param rel the release, with Status__c and Approval_Status__c
     * @return true for an approved release whose deploy failed, for an approver or the deployment team
     */
    public static Boolean mayDeployAgain(RLY_Release__c rel) {
        return rel != null && rel.Status__c == DEPLOY_FAILED && rel.Approval_Status__c == 'Approved'
            && (RlyReleaseAccess.isApprover() || RlyReleaseAccess.isDeployTeam());
    }

    /**
     * @description Starts the deploy again (callouts only; the caller saves the release).
     * @param rel the release
     */
    public static void start(RLY_Release__c rel) {
        if (!mayDeployAgain(rel)) {
            throw new RlyReleaseException('Only an approved release whose deploy failed can be deployed again, by an approver or the deployment team.');
        }
        String failed = rel.Error_Message__c;
        RlyApprovalRuns.dispatchMerge(rel, RlyGit.forConnection(RlyReleaseStore.gitFor(rel)));
        RlyReleaseLog.add(rel, EVENT, ('Deploy started again by ' + UserInfo.getName()
            + (String.isBlank(failed) ? '' : ' after: ' + failed)).left(2000));
    }

    /**
     * @description Deploys a release again, for its page.
     * @param releaseId the release
     * @return the release's page data afterwards
     */
    @AuraEnabled
    public static RlyReleasesController.Detail deployAgain(Id releaseId) {
        try {
            RlyHubGuard.requireHub();
            RLY_Release__c rel = RlyReleaseStore.release(releaseId);
            RLY_Release__c before = RlySlackCardState.snapshot(rel);
            start(rel);
            RlySlackCardSync.notifyChange(before, rel); // the Slack card follows (callouts before any DML)
            RlyReleaseStore.save(rel);
            RlySlack.saveResults();
            RlyReleaseLog.flush();
            return RlyReleasesController.detail(releaseId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
