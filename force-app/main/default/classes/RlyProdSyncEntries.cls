/**
 * @description Several Git connections (build 45): the entries that keep the other repositories' prod branches in step
 * after a deploy to production (RlyProdSync): which ones to queue, their state, and the line the deployed release's
 * page shows for each.
 */
public with sharing class RlyProdSyncEntries {

    /**
     * @description One line for the deployed release's page.
     * @param e the entry
     * @param sync its automatic release, or null
     * @return the line: Synced ("prod kept in step in GitLab"), Running or Failed (Try again)
     */
    public static RlyProdSync.View viewOf(RlyProdSync.Entry e, RLY_Release__c sync) {
        RlyProdSync.View v = new RlyProdSync.View();
        v.connectionId = e.connectionId;
        v.provider = e.provider;
        v.repository = e.repository;
        v.branch = e.branch;
        v.releaseId = e.releaseId;
        v.releaseName = sync == null ? null : sync.Name;
        if (e.status == RlyProdSync.QUEUED || (sync != null && RlyStatusReader.OPEN_STATUSES.contains(sync.Status__c))) {
            v.state = RlyProdSync.RUNNING;
            v.message = sync == null ? 'Waiting to start.' : sync.Name + ': ' + sync.Status__c + '.';
        } else if (sync != null && sync.Status__c == 'Deployed') {
            v.state = RlyProdSync.SYNCED;
            v.message = e.branch + ' kept in step in ' + e.provider + '.';
        } else {
            v.state = RlyProdSync.FAILED;
            v.message = failure(e, sync);
        }
        return v;
    }

    private static String failure(RlyProdSync.Entry e, RLY_Release__c sync) {
        if (sync == null) {
            return String.isBlank(e.message) ? 'It couldn\'t be raised.' : e.message;
        }
        return sync.Name + ': ' + sync.Status__c + (String.isBlank(sync.Error_Message__c) ? '.' : ': ' + sync.Error_Message__c.left(300));
    }

    /**
     * @description Prod_Sync_State__c for the entries: Queued while one still waits to be raised, else Failed when one
     * couldn't be raised, else Started.
     * @param entries the entries
     * @return the state
     */
    public static String stateOf(List<RlyProdSync.Entry> entries) {
        String state = RlyProdSync.STARTED;
        for (RlyProdSync.Entry e : entries) {
            if (e.status == RlyProdSync.QUEUED) {
                return RlyProdSync.QUEUED;
            }
            if (e.status == RlyProdSync.FAILED) {
                state = RlyProdSync.FAILED;
            }
        }
        return state;
    }

    /**
     * @description The automatic releases the entries raised.
     * @param entries the entries
     * @return their Ids
     */
    public static Set<Id> releaseIdsOf(List<RlyProdSync.Entry> entries) {
        Set<Id> ids = new Set<Id>();
        for (RlyProdSync.Entry e : entries) {
            if (e.releaseId != null) {
                ids.add(e.releaseId);
            }
        }
        return ids;
    }

    /**
     * @description One queued entry for every active connection but the release's own.
     * @param conns the connections
     * @param own the release's own connection
     * @return the entries
     */
    public static List<RlyProdSync.Entry> othersThan(List<RLY_Git_Connection__c> conns, RLY_Git_Connection__c own) {
        RLY_Org__c hub = RlyPromoteStore.hub();
        List<RlyProdSync.Entry> entries = new List<RlyProdSync.Entry>();
        for (RLY_Git_Connection__c c : conns) {
            if (c.Active__c == true && (own == null || c.Id != own.Id)) {
                RlyProdSync.Entry e = new RlyProdSync.Entry();
                e.connectionId = c.Id;
                e.provider = RlyGitName.labelFor(c) == null ? c.Provider__c : RlyGitName.labelFor(c);
                e.repository = c.Repository__c;
                e.branch = hub == null || String.isBlank(hub.Branch__c) ? 'prod' : hub.Branch__c.trim();
                e.status = RlyProdSync.QUEUED;
                entries.add(e);
            }
        }
        return entries;
    }
}
