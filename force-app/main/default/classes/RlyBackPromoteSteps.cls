/**
 * @description The manual steps a back promote sync takes (RlyManualSteps): the steps marked Back_Promote__c of every
 * release deployed to the hub that the org hasn't received yet (those since its last successful sync; a never synced
 * org: since it was registered), in deploy order, each once (RlyManualStepRuns). DML only.
 */
public with sharing class RlyBackPromoteSteps {

    /**
     * @description The hub deploys an org hasn't received: those since its last successful sync (a never synced org: since
     * it was registered).
     * @param o the back promote org, with Synced_On__c and CreatedDate
     * @param deployed the releases deployed to the hub, oldest first (RlyPromoteStore.hubDeployed)
     * @return the releases, oldest first
     */
    public static List<RLY_Release__c> behind(RLY_Org__c o, List<RLY_Release__c> deployed) {
        List<RLY_Release__c> out = new List<RLY_Release__c>();
        Datetime since = o.Synced_On__c == null ? o.CreatedDate : o.Synced_On__c;
        for (RLY_Release__c r : deployed) {
            if (r.Last_Synced__c != null && (since == null || r.Last_Synced__c > since)) {
                out.add(r);
            }
        }
        return out;
    }

    /**
     * @description The runs of back promote syncs just saved: the Back_Promote__c steps of every release deployed to the
     * hub since each org's last sync (the releases behind finds), in deploy order.
     * @param syncs the syncs, saved
     * @param orgs their back promote orgs, with Synced_On__c and CreatedDate
     */
    public static void forSyncs(List<RLY_Release__c> syncs, List<RLY_Org__c> orgs) {
        RLY_Org__c hub = syncs.isEmpty() ? null : RlyPromoteStore.hub();
        if (hub == null) {
            return;
        }
        List<RLY_Release__c> deployed = RlyPromoteStore.hubDeployed(hub.Id);
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>(orgs);
        List<RlyManualStepRuns.Plan> plans = new List<RlyManualStepRuns.Plan>();
        for (RLY_Release__c sync : syncs) {
            RLY_Org__c o = byId.get(sync.Target_Org__c);
            if (o != null) {
                RlyManualStepRuns.Plan p = new RlyManualStepRuns.Plan();
                p.releaseId = sync.Id;
                p.orgId = o.Id;
                p.orgName = o.Name;
                p.backPromoteOnly = true;
                for (RLY_Release__c r : behind(o, deployed)) {
                    p.definers.addAll(RlyManualStepRuns.definersOf(r));
                }
                plans.add(p);
            }
        }
        RlyManualStepRuns.create(plans);
    }
}
