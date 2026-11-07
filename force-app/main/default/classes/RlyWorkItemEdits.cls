/**
 * @description Work items (build 40; Add tickets in build 47): a raised release's tickets changed on the release page,
 * until it is deployed, rejected or closed. Tickets already on the release keep their tracker; new ones are matched to
 * a tracker (RlyWorkRouting). The tickets added and removed get a line in the release's history (RlyWorkHistory); an
 * added ticket's first post is the release's current moment, not Raised (RlyWorkSync posts what it hasn't had).
 */
public with sharing class RlyWorkItemEdits {

    /**
     * @description Replaces a release's tickets.
     * @param releaseId the release
     * @param tickets the tickets
     * @return the release's tickets as saved
     */
    public static List<String> replace(Id releaseId, List<String> tickets) {
        RLY_Release__c rel = openRelease(releaseId);
        List<RLY_Work_Item__c> existing = RlyWorkStore.forRelease(releaseId);
        List<String> wanted = RlyWorkFormat.ticketsChecked(tickets, RlyWorkStore.trackingSettings(), ticketsOf(existing));
        Set<String> keep = new Set<String>(wanted);
        List<RLY_Work_Item__c> gone = new List<RLY_Work_Item__c>();
        List<String> removed = new List<String>();
        for (RLY_Work_Item__c w : existing) {
            if (!keep.contains(w.Ticket__c)) {
                gone.add(w);
                removed.add(w.Ticket__c);
            }
        }
        List<RLY_Work_Item__c> added = RlyWorkItems.rows(releaseId, wanted, existing);
        rel.Work_Items__c = wanted.isEmpty() ? null : RlyWorkItems.joined(wanted);
        RlyWorkStore.save(added, gone, rel);
        RlyWorkHistory.changed(rel, added, removed);
        return wanted;
    }

    /**
     * @description Adds tickets to a raised release (Add tickets); the tickets already on it stay.
     * @param releaseId the release
     * @param tickets the tickets to add
     * @return the release's tickets as saved
     */
    public static List<String> add(Id releaseId, List<String> tickets) {
        List<String> all = new List<String>(ticketsOf(RlyWorkStore.forRelease(releaseId)));
        Integer before = all.size();
        for (String t : tickets == null ? new List<String>() : tickets) {
            String ticket = String.isBlank(t) ? null : t.trim().toUpperCase();
            if (ticket != null && !all.contains(ticket)) {
                all.add(ticket);
            }
        }
        if (all.size() == before) {
            throw new RlyReleaseException('Type a ticket that isn\'t on the release yet, then Add.');
        }
        return replace(releaseId, all);
    }

    // The release, while its tickets can still change.
    private static RLY_Release__c openRelease(Id releaseId) {
        RLY_Release__c rel = RlyWorkStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        if (RlyWorkItems.CLOSED.contains(rel.Status__c)) {
            throw new RlyReleaseException('The release is ' + rel.Status__c.toLowerCase() + ': its tickets stay as they are.');
        }
        return rel;
    }

    private static Set<String> ticketsOf(List<RLY_Work_Item__c> rows) {
        Set<String> out = new Set<String>();
        for (RLY_Work_Item__c w : rows) {
            out.add(w.Ticket__c);
        }
        return out;
    }
}
