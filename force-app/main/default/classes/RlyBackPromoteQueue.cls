/**
 * @description Queues back promote syncs (RlyBackPromote): Sync now for one org, or after a deploy to the hub for every
 * After_Deploy org. A sync is a release record from the hub org to the back promote org, saved waiting for approval
 * (Back_Promote_Approval__c) or queued (Status Submitted) to start on the next read (RlyBackPromoteRun), with the
 * manual step runs it needs (RlyBackPromoteSteps.forSyncs). DML only.
 */
public with sharing class RlyBackPromoteQueue {

    private static final Set<String> OPEN_SYNC = new Set<String>{ 'Submitted', 'Ready for approval', 'Deploying' };

    /**
     * @description Sync now (admins): saves a sync of the hub's changes to the org, waiting for approval when the org asks
     * for it, otherwise queued to start on the next read.
     * @param orgId the back promote org
     * @return the sync release's Id
     */
    public static Id queueSync(Id orgId) {
        RlyBackPromote.requireAdmin();
        if (!RlyBackPromote.isOn(RlyReleaseStore.git())) {
            throw RlyBackPromote.problem('Turn on Back promote first.');
        }
        RLY_Org__c o = RlyBackPromote.findOrg(orgId);
        if (hasOpenSync(o.Id, RlyPromoteStore.latestSyncs())) {
            throw RlyBackPromote.problem('A sync to ' + o.Name + ' is already waiting or running.');
        }
        RLY_Release__c sync = newSync(requireHub(), o);
        RlyPromoteStore.insertSyncs(new List<RLY_Release__c>{ sync });
        RlyBackPromoteSteps.forSyncs(new List<RLY_Release__c>{ sync }, new List<RLY_Org__c>{ o });
        return sync.Id;
    }

    /**
     * @description After a release is deployed to the hub with back promote on: a sync for every After_Deploy org that
     * has none waiting or running. DML only (the caller's callouts are done).
     * @param rel the release just deployed
     */
    public static void afterDeploy(RLY_Release__c rel) {
        if (!isHubDeploy(rel) || !RlyBackPromote.isOn(RlyReleaseStore.git())) {
            return;
        }
        RLY_Org__c hub = RlyPromoteStore.hub();
        List<RLY_Release__c> latest = RlyPromoteStore.latestSyncs();
        List<RLY_Release__c> syncs = new List<RLY_Release__c>();
        List<RLY_Org__c> orgs = RlyPromoteStore.backPromoteOrgs();
        for (RLY_Org__c o : orgs) {
            if (RlyBackPromote.whenOf(o) == RlyBackPromote.WHEN_AFTER_DEPLOY && !hasOpenSync(o.Id, latest) && isUsable(hub) && isUsable(o)) {
                syncs.add(newSync(hub, o));
            }
        }
        RlyPromoteStore.insertSyncs(syncs);
        RlyBackPromoteSteps.forSyncs(syncs, orgs);
    }

    /**
     * @description Whether a release went to the hub (and isn't a sync itself).
     * @param rel the release, with Target_Org__r.Role__c
     * @return true for a release into the hub
     */
    public static Boolean isHubDeploy(RLY_Release__c rel) {
        return rel.Target_Org__r != null && rel.Target_Org__r.Role__c == 'Hub'
            && RlyPromotion.typeOf(rel) != RlyPromotion.TYPE_BACK_PROMOTE;
    }

    private static Boolean hasOpenSync(Id orgId, List<RLY_Release__c> latest) {
        for (RLY_Release__c r : latest) {
            if (r.Target_Org__c == orgId && OPEN_SYNC.contains(r.Status__c)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isUsable(RLY_Org__c o) {
        return o != null && String.isNotBlank(o.Branch__c) && String.isNotBlank(o.Git_Environment__c);
    }

    // A sync release from the hub to the org: waiting for approval, or queued.
    private static RLY_Release__c newSync(RLY_Org__c hub, RLY_Org__c o) {
        if (!isUsable(o)) {
            throw RlyBackPromote.problem(o.Name + ' needs its branch and Git environment (Pipeline tab) before it can sync.');
        }
        return new RLY_Release__c(Release_Type__c = RlyPromotion.TYPE_BACK_PROMOTE, Mode__c = 'Existing branch',
            Request_Type__c = 'Changes', Title__c = ('Back promote ' + hub.Name + ' to ' + o.Name).left(200),
            Description__c = hub.Name + '\'s changes, metadata only.',
            Status__c = o.Back_Promote_Approval__c == true ? 'Ready for approval' : RlyPromotion.QUEUED,
            Source_Org__c = hub.Id, Target_Org__c = o.Id, Org_Label__c = hub.Name.left(40),
            Source_Branch__c = hub.Branch__c.trim(), Target_Branch__c = o.Branch__c.trim(),
            Source_Environment__c = hub.Git_Environment__c, Target_Environment__c = o.Git_Environment__c,
            Component_Count__c = 0, Deletion_Count__c = 0, Scan_Status__c = 'Not configured', Validation_Status__c = 'Not configured',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Last_Synced__c = System.now());
    }

    private static RLY_Org__c requireHub() {
        RLY_Org__c hub = RlyPromoteStore.hub();
        if (!isUsable(hub)) {
            throw RlyBackPromote.problem('Register this hub with the role Hub, its branch and Git environment first.');
        }
        return hub;
    }
}
