/**
 * @description Cancel release on the release page (build 54): the person who raised a release, or a Release Relay admin,
 * withdraws it while it is open (any status but Deployed, Rejected, Cancelled or Closed), with a reason. Reject is
 * different: an approver turns a release down. The release becomes Cancelled with "Cancelled by <user>: <reason>", a
 * Cancelled History event is added, its pull or merge request gets the comment "Cancelled in Release Relay by <user>:
 * <reason>" and is closed (best effort), and its Slack card is edited as for a rejection (RlyMigrationCancel.cancelOne).
 * A cancelled promotion frees the releases it carried (RlyReleaseEffects). A pipeline run still going isn't stopped.
 * Callouts first, the saves after.
 */
public with sharing class RlyReleaseCancel {

    /**
     * @description Whether the current user may cancel the release now: it is open, and they raised it or are an admin.
     * @param rel the release, with Status__c and CreatedById
     * @return true when they may
     */
    public static Boolean mayCancel(RLY_Release__c rel) {
        return rel != null && !RlyGitConnections.ENDED.contains(rel.Status__c) && RlyReleaseAccess.mayEditTickets(rel);
    }

    /**
     * @description The release page's Cancel release: cancels it and returns the page's view of it.
     * @param releaseId the release
     * @param reason why it is cancelled (required)
     * @return the release, as the page shows it
     */
    @AuraEnabled
    public static RlyReleasesController.Detail cancelFromPage(Id releaseId, String reason) {
        try {
            cancelRelease(releaseId, reason);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
        return RlyReleasesController.getRelease(releaseId);
    }

    /**
     * @description Cancels the release as the current user.
     * @param releaseId the release
     * @param reason why it is cancelled (required)
     * @return the release as saved
     */
    public static RLY_Release__c cancelRelease(Id releaseId, String reason) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        requireCancellable(rel, reason);
        String text = UserInfo.getName() + ': ' + reason.trim().left(1000);
        RlyMigrationCancel.Words w = new RlyMigrationCancel.Words();
        w.reason = 'Cancelled by ' + text;
        w.prComment = 'Cancelled in Release Relay by ' + text;
        Boolean closing = rel.PR_Number__c != null && String.isBlank(rel.Merge_Commit__c);
        List<String> problems = RlyMigrationCancel.cancelOne(rel, w); // callouts: the pull request and the Slack card
        RlyReleaseLog.add(rel, RlyMigrationCancel.EVENT, 'Cancelled by ' + text).inOrg(rel.Target_Org__c)
            .byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(rel.PR_URL__c);
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        RlyCredentialPrAccess.afterClose(rel, closing ? problems : null); // the Credentials page's Git token row, as a rejection does
        return rel;
    }

    // Open, the raiser or an admin, and a reason.
    private static void requireCancellable(RLY_Release__c rel, String reason) {
        if (rel == null || RlyGitConnections.ENDED.contains(rel.Status__c)) {
            throw new RlyReleaseException('Only an open release can be cancelled' + (rel == null ? '.' : ': ' + rel.Name + ' is ' + rel.Status__c + '.'));
        }
        if (!RlyReleaseAccess.mayEditTickets(rel)) {
            throw new RlyReleaseException('Only the person who raised ' + rel.Name + ' or an admin can cancel it. An approver can reject it.');
        }
        if (String.isBlank(reason)) {
            throw new RlyReleaseException('Say why it\'s cancelled.');
        }
    }
}
