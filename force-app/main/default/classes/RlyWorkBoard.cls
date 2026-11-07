/**
 * @description Work items (build 40): the Work items tab. One row per ticket (RlyWorkBoardRow), worked out from the
 * releases that carry it, with a cell per route org (the stages by their order, then the hub). Reads only.
 */
public with sharing class RlyWorkBoard {

    /**
     * @description The tab's rows.
     * @return the board
     */
    public static RlyWorkTypes.Board build() {
        RlyWorkTypes.Board b = new RlyWorkTypes.Board();
        RLY_Work_Tracking__c s = RlyWorkStore.trackingSettings();
        b.trackerLabel = trackerLabel(s);
        for (RLY_Org__c o : routeInOrder()) {
            b.orgs.add(o.Name);
        }
        List<RLY_Work_Item__c> rows = RlyWorkStore.recent();
        b.truncated = rows.size() >= RlyWorkStore.MAX_ROWS;
        Map<String, List<RLY_Work_Item__c>> byTicket = new Map<String, List<RLY_Work_Item__c>>();
        for (RLY_Work_Item__c w : rows) {
            if (!byTicket.containsKey(w.Ticket__c)) {
                byTicket.put(w.Ticket__c, new List<RLY_Work_Item__c>());
            }
            byTicket.get(w.Ticket__c).add(w);
        }
        for (String t : byTicket.keySet()) {
            RlyWorkTypes.TicketRow r = RlyWorkBoardRow.rowOf(t, byTicket.get(t), b.orgs);
            r.link = RlyWorkLinks.linkOf(t, s);
            b.tickets.add(r);
        }
        return b;
    }

    /**
     * @description The tracker in words.
     * @param s the settings, or null
     * @return for example Jira, or Tracked in Release Relay
     */
    public static String trackerLabel(RLY_Work_Tracking__c s) {
        if (s == null || s.Tracker__c == null || s.Tracker__c == RlyWorkTracker.NONE) {
            return 'Tracked in Release Relay';
        }
        return s.Tracker__c == RlyWorkTracker.AZURE ? 'Azure Boards' : s.Tracker__c;
    }

    // The stages (by their order) then the hub.
    private static List<RLY_Org__c> routeInOrder() {
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        List<RLY_Org__c> hubs = new List<RLY_Org__c>();
        for (RLY_Org__c o : RlyReleaseStore.routeOrgs()) {
            if (o.Role__c == 'Hub') {
                hubs.add(o);
            } else {
                stages.add(o);
            }
        }
        List<RLY_Org__c> sorted = new List<RLY_Org__c>();
        while (!stages.isEmpty()) {
            Integer best = 0;
            for (Integer i = 1; i < stages.size(); i++) {
                if (orderOf(stages[i]) < orderOf(stages[best])) {
                    best = i;
                }
            }
            sorted.add(stages.remove(best));
        }
        sorted.addAll(hubs);
        return sorted;
    }

    private static Decimal orderOf(RLY_Org__c o) {
        return o.Stage_Order__c == null ? 9999 : o.Stage_Order__c;
    }
}
