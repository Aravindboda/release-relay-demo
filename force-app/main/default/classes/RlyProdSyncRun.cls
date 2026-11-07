/**
 * @description Several Git connections (build 45): raises the automatic release that keeps another repository's prod
 * branch in step after a deploy to production (RlyProdSync), and says how it went. The release goes from the hub org into
 * the hub's branch of that connection's repository with no target environment (so no validation and no deploy), with
 * the deployed release's components retrieved from the hub org and its deletions. raise makes the callout (the
 * retrieve); save inserts the release afterwards.
 */
public with sharing class RlyProdSyncRun {

    /** @description An automatic release ready to insert, or why there is none. */
    public class Raised {
        /** @description The release, or null. */
        public RLY_Release__c rel;
        /** @description Its components. */
        public List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        /** @description Why it couldn't be raised, or null. */
        public String problem;
    }

    /**
     * @description Builds the automatic release for one entry and starts its retrieve in the hub org. Callouts only.
     * @param e the entry (its connection)
     * @param deployed the release deployed to production (Id, Name, Title__c, Deletions__c, Deletion_Count__c)
     * @return the release to insert, or the problem
     */
    public static Raised raise(RlyProdSync.Entry e, RLY_Release__c deployed) {
        Raised r = new Raised();
        try {
            RLY_Git_Connection__c conn = RlyConnectionStore.byId(e.connectionId);
            RLY_Org__c hubRow = RlyPromoteStore.hub();
            RLY_Org__c hub = hubRow == null ? null : RlyReleaseStore.org(hubRow.Id);
            r.problem = problemOf(conn, hub);
            if (r.problem != null) {
                return r;
            }
            Map<String, Set<String>> byType = new Map<String, Set<String>>();
            for (RLY_Release_Item__c i : RlyReleaseStore.items(deployed.Id)) {
                r.items.add(new RLY_Release_Item__c(Metadata_Type__c = i.Metadata_Type__c, Component_Name__c = i.Component_Name__c,
                    Change_Type__c = 'Modified', Source__c = 'Detected', Is_Deletion__c = i.Is_Deletion__c == true));
                if (i.Is_Deletion__c != true) {
                    if (!byType.containsKey(i.Metadata_Type__c)) {
                        byType.put(i.Metadata_Type__c, new Set<String>());
                    }
                    byType.get(i.Metadata_Type__c).add(i.Component_Name__c);
                }
            }
            if (r.items.isEmpty()) {
                r.problem = 'The release has no components to bring over.';
                return r;
            }
            r.rel = build(deployed, hub, conn);
            r.rel.Component_Count__c = Math.max(r.items.size() - RlyDeletions.of(deployed).size(), 0);
            r.rel.Retrieve_Id__c = byType.isEmpty() ? null : RlyRetrieve.start(hub, byType);
        } catch (Exception ex) {
            r.rel = null;
            r.problem = ('Couldn\'t raise it: ' + ex.getMessage()).left(500);
        }
        return r;
    }

    /**
     * @description Inserts the raised release and records it on the entry (Started), or records the problem (Failed).
     * @param r what raise built
     * @param e the entry
     */
    public static void save(Raised r, RlyProdSync.Entry e) {
        if (r == null || r.rel == null) {
            e.status = RlyProdSync.FAILED;
            e.message = r == null ? 'Couldn\'t raise it.' : r.problem;
            return;
        }
        RlyReleaseStore.insertRelease(r.rel, r.items);
        e.status = RlyProdSync.STARTED;
        e.message = null;
        e.releaseId = r.rel.Id;
    }

    private static String problemOf(RLY_Git_Connection__c conn, RLY_Org__c hub) {
        if (conn == null || conn.Active__c != true) {
            return 'That Git connection isn\'t there or isn\'t active any more.';
        }
        if (conn.Status__c != 'Connected') {
            return 'The ' + conn.Provider__c + ' connection isn\'t checked yet (Pipeline tab).';
        }
        if (hub == null || String.isBlank(hub.Branch__c) || String.isBlank(hub.Git_Environment__c)) {
            return 'The hub needs its branch and Git environment (Pipeline tab).';
        }
        return null;
    }

    // From the hub into the hub's branch of the other repository; no target environment: no validation, no deploy.
    private static RLY_Release__c build(RLY_Release__c deployed, RLY_Org__c hub, RLY_Git_Connection__c conn) {
        List<String> deletions = RlyDeletions.of(deployed);
        return new RLY_Release__c(Title__c = ('Keep ' + hub.Branch__c.trim() + ' in step: ' + deployed.Name + ' ' + deployed.Title__c).left(200),
            Description__c = (deployed.Name + ' was deployed to ' + hub.Name + '. This brings ' + hub.Branch__c.trim() + ' in '
                + conn.Repository__c + ' up to date with it.').left(5000),
            Mode__c = 'Org changes', Request_Type__c = 'Changes', Release_Type__c = RlyProdSync.TYPE_PROD_SYNC, Status__c = 'Retrieving',
            Source_Org__c = hub.Id, Target_Org__c = hub.Id, Org_Label__c = hub.Name.left(40), Target_Branch__c = hub.Branch__c.trim(),
            Source_Environment__c = hub.Git_Environment__c, Target_Environment__c = null,
            Deletions__c = deletions.isEmpty() ? null : String.join(deletions, ',').left(RlyDeletions.MAX_LENGTH),
            Deletion_Count__c = deletions.size(),
            Scan_Status__c = RlyScanRule.statusFor(conn, hub), Validation_Status__c = 'Not configured',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Last_Synced__c = System.now(), Git_Connection__c = conn.Id);
    }
}
