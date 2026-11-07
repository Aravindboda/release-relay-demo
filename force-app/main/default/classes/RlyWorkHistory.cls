/**
 * @description Work items (build 47): the release history of tickets added to or removed from a raised release
 * (release page): "Tickets added: BILL-81 (Billing stories), at Ready for approval in SIT", by the person, via
 * Salesforce. Saved now (RlyReleaseLog.flush): the callers make no callout afterwards.
 */
public with sharing class RlyWorkHistory {

    /** @description The history event type the lines use. */
    public static final String EVENT_TYPE = 'Comment';

    /**
     * @description Records the tickets added and removed.
     * @param rel the release (with its status and orgs, as RlyWorkStore.release reads it)
     * @param added the new ticket rows (with their tracker)
     * @param removed the tickets taken off
     */
    public static void changed(RLY_Release__c rel, List<RLY_Work_Item__c> added, List<String> removed) {
        if (!added.isEmpty()) {
            String moment = RlyWorkSync.momentOf(rel);
            line(rel, 'Tickets added: ' + named(added) + (moment == null ? '' : ', at ' + moment));
        }
        if (!removed.isEmpty()) {
            line(rel, 'Tickets removed: ' + String.join(removed, ', '));
        }
        RlyReleaseLog.flush();
    }

    private static void line(RLY_Release__c rel, String detail) {
        RlyReleaseLog.add(rel, EVENT_TYPE, detail).inOrg(rel.Target_Org__c).byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE);
    }

    // BILL-81 (Billing stories), CHG0012345 (Change requests); a ticket without a tracker by itself.
    private static String named(List<RLY_Work_Item__c> rows) {
        List<String> out = new List<String>();
        for (RLY_Work_Item__c w : rows) {
            RLY_Work_Tracker__c t = RlyWorkRouting.trackerOf(w);
            out.add(t == null ? w.Ticket__c : w.Ticket__c + ' (' + t.Name + ')');
        }
        return String.join(out, ', ');
    }
}
