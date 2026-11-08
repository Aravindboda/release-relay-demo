/**
 * @description Who may change a raised release's details (build 48): its tickets (the raiser or a Release Relay admin)
 * and running its checks again (the raiser, an approver, the deployment team or an admin).
 */
public with sharing class RlyReleaseAccess {

    /**
     * @description Whether the current user may add or remove the release's tickets: who raised it, or an admin.
     * @param rel the release, with CreatedById
     * @return true when they may
     */
    public static Boolean mayEditTickets(RLY_Release__c rel) {
        return isRaiser(rel) || (rel != null && RlyOrgController.isAdmin());
    }

    /**
     * @description Whether the current user may run a release's checks again: who raised it, an approver (or admin),
     * or the deployment team.
     * @param rel the release, with CreatedById
     * @return true when they may
     */
    public static Boolean mayRerunChecks(RLY_Release__c rel) {
        return isRaiser(rel) || (rel != null && (RlyApprovalService.canApprove() || FeatureManagement.checkPermission('RLY_Deploy_Team')));
    }

    /**
     * @description Throws unless the current user may run the release's checks again.
     * @param rel the release, with Name and CreatedById
     */
    public static void requireRerun(RLY_Release__c rel) {
        if (!mayRerunChecks(rel)) {
            throw new RlyReleaseException('Only the person who raised ' + rel.Name + ', an approver, the deployment team or an admin can run its checks again.');
        }
    }

    private static Boolean isRaiser(RLY_Release__c rel) {
        return rel != null && rel.CreatedById == UserInfo.getUserId();
    }
}
