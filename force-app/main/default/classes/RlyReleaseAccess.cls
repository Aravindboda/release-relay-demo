/**
 * @description Who may do what: the one place the current user's Release Relay permissions are checked (custom
 * permissions through FeatureManagement). Roles: admin, approver (an admin approves too), deployment team (an admin
 * deploys too); the add-ons (hotfix, release window bypass, production approver) are checked with holds. RlyRoles
 * answers the permission set questions (auditor, developer, other users) and asks this class for the current user.
 * Also who may change a raised release's details (build 48): its tickets (the raiser or an admin) and running its
 * checks again (the raiser, an approver, the deployment team or an admin).
 */
public with sharing class RlyReleaseAccess {

    /** @description The Admin custom permission. */
    public static final String ADMIN = 'RLY_Admin';
    /** @description The Approver custom permission. */
    public static final String APPROVER = 'RLY_Approver';
    /** @description The Deploy Team custom permission. */
    public static final String DEPLOY_TEAM = 'RLY_Deploy_Team';

    /**
     * @description Whether the current user holds a custom permission (a role or an add-on).
     * @param customPermission the custom permission's API name
     * @return true when held
     */
    public static Boolean holds(String customPermission) {
        return FeatureManagement.checkPermission(customPermission);
    }

    /**
     * @description Whether the current user is a Release Relay admin.
     * @return true for admins
     */
    public static Boolean isAdmin() {
        return holds(ADMIN);
    }

    /**
     * @description Whether the current user approves: an approver or an admin.
     * @return true when they may approve
     */
    public static Boolean isApprover() {
        return holds(APPROVER) || isAdmin();
    }

    /**
     * @description Whether the current user deploys: the deployment team or an admin.
     * @return true when they may deploy
     */
    public static Boolean isDeployTeam() {
        return holds(DEPLOY_TEAM) || isAdmin();
    }

    /**
     * @description Throws, with the sentence the page shows, unless the current user is an admin.
     * @param why the sentence (what needs the admin permission)
     */
    public static void requireAdmin(String why) {
        if (!isAdmin()) {
            throw RlyReleaseException.toAura(why);
        }
    }

    /**
     * @description Whether the current user may add or remove the release's tickets: who raised it, or an admin.
     * @param rel the release, with CreatedById
     * @return true when they may
     */
    public static Boolean mayEditTickets(RLY_Release__c rel) {
        return isRaiser(rel) || (rel != null && isAdmin());
    }

    /**
     * @description Whether the current user may run a release's checks again: who raised it, an approver (or admin),
     * or the deployment team.
     * @param rel the release, with CreatedById
     * @return true when they may
     */
    public static Boolean mayRerunChecks(RLY_Release__c rel) {
        return isRaiser(rel) || (rel != null && (isApprover() || isDeployTeam()));
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
