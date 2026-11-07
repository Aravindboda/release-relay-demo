/**
 * @description Work items (build 40; several trackers in build 47): the work tracking settings between the records and
 * the Pipeline tab card. The global switches (tickets required, an approved ServiceNow change before production and
 * the change format) stay in RLY_Work_Tracking__c; each tracker is an RLY_Work_Tracker__c record, checked by
 * RlyWorkTrackerCheck. Also makes the first tracker from the build 40 setting for clients who set one up before.
 */
public with sharing class RlyWorkSettings {

    /**
     * @description The settings for the pages: the switches and every tracker in routing order.
     * @param r the settings record, or null
     * @return the settings
     */
    public static RlyWorkTypes.Settings viewOf(RLY_Work_Tracking__c r) {
        RlyWorkTypes.Settings v = new RlyWorkTypes.Settings();
        v.isAdmin = RlyOrgController.isAdmin();
        v.trackerLabel = RlyWorkBoard.trackerLabel();
        v.tracker = RlyWorkTracker.NONE;
        Integer position = 0;
        for (RLY_Work_Tracker__c t : RlyWorkStore.trackers()) {
            position++;
            v.trackers.add(trackerView(t, position));
        }
        List<RLY_Work_Tracker__c> active = RlyWorkRouting.active();
        if (!active.isEmpty()) {
            firstTracker(v, active[0]);
        }
        v.ticketPattern = joinedPatterns(active);
        if (r != null) {
            v.required = r.Required__c == true;
            v.requireChange = r.Require_Change__c == true;
            v.changePattern = r.Change_Pattern__c;
        }
        return v;
    }

    /**
     * @description A tracker for the pages.
     * @param t the tracker
     * @param position its place in the routing order (1 first)
     * @return the view
     */
    public static RlyWorkTypes.TrackerView trackerView(RLY_Work_Tracker__c t, Integer position) {
        RlyWorkTypes.TrackerView x = new RlyWorkTypes.TrackerView();
        x.id = t.Id;
        x.name = t.Name;
        x.kind = String.isBlank(t.Type__c) ? RlyWorkTracker.NONE : t.Type__c;
        x.kindLabel = RlyWorkRouting.kindLabel(x.kind);
        x.ticketPattern = t.Ticket_Pattern__c;
        x.linkPattern = t.Link_Pattern__c;
        x.namedCredential = t.Named_Credential__c;
        x.postUpdates = t.Post_Updates__c == true;
        x.stateMap = t.State_Map__c;
        x.serviceNowTable = t.ServiceNow_Table__c;
        x.active = t.Active__c == true;
        x.position = position;
        return x;
    }

    /**
     * @description The switches as a record, after checking them: the change gate needs an active ServiceNow tracker
     * with its Named Credential.
     * @param v the settings from the page
     * @return the record to save (only the switches: the build 40 tracker fields stay as they were)
     */
    public static RLY_Work_Tracking__c checked(RlyWorkTypes.Settings v) {
        String changePattern = String.isBlank(v.changePattern) ? null : v.changePattern.trim();
        RlyWorkTrackerFields.checkPatterns(changePattern, 'change format');
        if (changePattern != null && changePattern.length() > 80) {
            throw new RlyReleaseException('The change format is up to 80 characters.');
        }
        Boolean gate = v.requireChange == true;
        if (gate && !hasChangeTracker()) {
            throw new RlyReleaseException('An approved change before production needs an active ServiceNow tracker with its Named Credential: '
                + 'the change is read there.');
        }
        return new RLY_Work_Tracking__c(Required__c = v.required == true, Require_Change__c = gate, Change_Pattern__c = changePattern);
    }

    /**
     * @description The tracker made from the build 40 setting (unsaved), or null when that setting names no tracker.
     * @param s the setting, or null
     * @return the tracker
     */
    public static RLY_Work_Tracker__c fromLegacy(RLY_Work_Tracking__c s) {
        if (s == null || String.isBlank(s.Tracker__c) || !RlyWorkTracker.TRACKERS.contains(s.Tracker__c)) {
            return null;
        }
        return new RLY_Work_Tracker__c(Name = RlyWorkRouting.kindLabel(s.Tracker__c), Type__c = s.Tracker__c, Ticket_Pattern__c = s.Ticket_Pattern__c,
            Link_Pattern__c = s.Link_Pattern__c, Named_Credential__c = s.Named_Credential__c, Post_Updates__c = s.Post_Updates__c == true,
            State_Map__c = s.State_Map__c, ServiceNow_Table__c = s.ServiceNow_Table__c, Active__c = true, Sort_Order__c = 1);
    }

    /**
     * @description Whether an active ServiceNow tracker with a Named Credential exists (the change gate reads there).
     * @return true when one exists
     */
    public static Boolean hasChangeTracker() {
        for (RLY_Work_Tracker__c t : RlyWorkRouting.active()) {
            if (t.Type__c == RlyWorkTracker.SERVICENOW && String.isNotBlank(t.Named_Credential__c)) {
                return true;
            }
        }
        return false;
    }

    // The build 40 single-tracker fields, from the first active tracker (older pages read them).
    private static void firstTracker(RlyWorkTypes.Settings v, RLY_Work_Tracker__c t) {
        v.tracker = String.isBlank(t.Type__c) ? RlyWorkTracker.NONE : t.Type__c;
        v.linkPattern = t.Link_Pattern__c;
        v.namedCredential = t.Named_Credential__c;
        v.postUpdates = t.Post_Updates__c == true;
        v.stateMap = t.State_Map__c;
        v.serviceNowTable = t.ServiceNow_Table__c;
    }

    private static String joinedPatterns(List<RLY_Work_Tracker__c> active) {
        List<String> out = new List<String>();
        for (RLY_Work_Tracker__c t : active) {
            if (String.isBlank(t.Ticket_Pattern__c)) {
                return null; // a tracker without a pattern takes any ticket
            }
            out.add(t.Ticket_Pattern__c.trim());
        }
        return out.isEmpty() ? null : String.join(out, ' ');
    }
}
