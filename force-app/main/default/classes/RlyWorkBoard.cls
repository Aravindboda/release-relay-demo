/**
 * @description Work items (build 40): the Work items tab. One row per ticket (RlyWorkBoardRow), worked out from the
 * releases that carry it, with a cell per route org (the stages by their order, then the hub) and its tracker (build
 * 47). Reads only.
 */
public with sharing class RlyWorkBoard {

    /**
     * @description The tab's rows.
     * @return the board
     */
    public static RlyWorkTypes.Board build() {
        RlyWorkTypes.Board b = new RlyWorkTypes.Board();
        b.trackerLabel = trackerLabel();
        for (RLY_Work_Tracker__c t : RlyWorkStore.trackers()) {
            b.trackers.add(t.Name);
        }
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
            withTracker(r, RlyWorkRouting.trackerOf(byTicket.get(t)[0]));
            b.tickets.add(r);
        }
        return b;
    }

    /**
     * @description The active trackers in words (build 47: a hub can have several).
     * @return for example Jira, or Claims stories, Change requests, or Tracked in Release Relay
     */
    public static String trackerLabel() {
        List<String> names = new List<String>();
        for (RLY_Work_Tracker__c t : RlyWorkRouting.active()) {
            if (t.Type__c != RlyWorkTracker.NONE) {
                names.add(t.Name);
            }
        }
        return names.isEmpty() ? 'Tracked in Release Relay' : String.join(names, ', ');
    }

    // The ticket's tracker (from its newest row): name, kind, link, and searchable by the tracker's name.
    private static void withTracker(RlyWorkTypes.TicketRow r, RLY_Work_Tracker__c t) {
        r.link = RlyWorkLinks.linkOf(r.ticket, t);
        if (t == null) {
            return;
        }
        r.tracker = t.Name;
        r.trackerType = RlyWorkRouting.kindLabel(t.Type__c);
        r.searchText = r.searchText + ' ' + t.Name.toLowerCase();
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
