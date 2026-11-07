/**
 * @description Work items (build 47): which tracker a ticket goes to. The active trackers are tried in their order and
 * the first whose ticket pattern matches takes the ticket; then a tracker with no pattern takes what is left. With no
 * match the ticket is refused ("No tracker matches …", naming the patterns). With no active tracker at all, any ticket
 * is taken and tracked in Release Relay (as before build 47). A ticket saved with its tracker keeps it; tickets saved
 * before build 47 are matched by pattern when read. Reads the trackers once per transaction (RlyWorkStore).
 */
public with sharing class RlyWorkRouting {

    /**
     * @description The tracker a ticket goes to, or null (no active tracker, or no match).
     * @param ticket the ticket
     * @return the tracker
     */
    public static RLY_Work_Tracker__c route(String ticket) {
        List<RLY_Work_Tracker__c> onTrackers = active();
        for (RLY_Work_Tracker__c t : onTrackers) {
            if (String.isNotBlank(t.Ticket_Pattern__c) && matches(ticket, t.Ticket_Pattern__c)) {
                return t;
            }
        }
        for (RLY_Work_Tracker__c t : onTrackers) {
            if (String.isBlank(t.Ticket_Pattern__c)) {
                return t;
            }
        }
        return null;
    }

    /**
     * @description For links in lists and messages: the tracker a ticket goes to, else an inactive tracker whose
     * pattern matches it (its tickets keep their links).
     * @param ticket the ticket
     * @return the tracker, or null
     */
    public static RLY_Work_Tracker__c routeForLink(String ticket) {
        RLY_Work_Tracker__c t = route(ticket);
        if (t != null) {
            return t;
        }
        for (RLY_Work_Tracker__c other : RlyWorkStore.trackers()) {
            if (matches(ticket, other.Ticket_Pattern__c)) {
                return other;
            }
        }
        return null;
    }

    /**
     * @description The tracker a ticket goes to; refused when active trackers exist and none takes it.
     * @param ticket the ticket (upper-cased)
     * @return the tracker, or null when there is no active tracker
     */
    public static RLY_Work_Tracker__c routeChecked(String ticket) {
        RLY_Work_Tracker__c t = route(ticket);
        if (t == null && !active().isEmpty()) {
            throw new RlyReleaseException('No tracker matches "' + ticket.left(RlyWorkItems.MAX_LENGTH) + '". Expected one of: ' + patternList() + '.');
        }
        return t;
    }

    /**
     * @description A saved ticket's tracker: the one it was saved with, else the one its pattern matches now.
     * @param w the work item row
     * @return the tracker, or null
     */
    public static RLY_Work_Tracker__c trackerOf(RLY_Work_Item__c w) {
        RLY_Work_Tracker__c saved = w.Tracker__c == null ? null : byId(w.Tracker__c);
        return saved != null ? saved : route(w.Ticket__c);
    }

    /**
     * @description A tracker by its Id (active or not).
     * @param trackerId the tracker
     * @return the tracker, or null
     */
    public static RLY_Work_Tracker__c byId(Id trackerId) {
        for (RLY_Work_Tracker__c t : RlyWorkStore.trackers()) {
            if (t.Id != null && t.Id == trackerId) {
                return t;
            }
        }
        return null;
    }

    /**
     * @description The active trackers in routing order.
     * @return the trackers
     */
    public static List<RLY_Work_Tracker__c> active() {
        List<RLY_Work_Tracker__c> out = new List<RLY_Work_Tracker__c>();
        for (RLY_Work_Tracker__c t : RlyWorkStore.trackers()) {
            if (t.Active__c == true) {
                out.add(t);
            }
        }
        return out;
    }

    /**
     * @description Whether a ticket matches one of the patterns (space separated, whole ticket, any case).
     * @param ticket the ticket
     * @param patterns the patterns
     * @return true on a match
     */
    public static Boolean matches(String ticket, String patterns) {
        if (String.isBlank(patterns) || ticket == null) {
            return false;
        }
        for (String f : patterns.trim().split('\\s+')) {
            try {
                if (Pattern.compile('(?i)^(?:' + f + ')$').matcher(ticket).matches()) {
                    return true;
                }
            } catch (Exception e) {
                continue; // a pattern that isn't a valid expression is skipped (refused when the tracker is saved)
            }
        }
        return false;
    }

    /**
     * @description The active trackers' patterns with their names: CLAIMS-\d+ (Claims stories), CHG\d{7} (Changes).
     * @return the text, or empty
     */
    public static String patternList() {
        List<String> out = new List<String>();
        for (RLY_Work_Tracker__c t : active()) {
            if (String.isNotBlank(t.Ticket_Pattern__c)) {
                out.add(t.Ticket_Pattern__c.trim() + ' (' + t.Name + ')');
            }
        }
        return String.join(out, ', ');
    }

    /**
     * @description A tracker kind in words.
     * @param kind Jira, Azure_Boards, ServiceNow, None or Other
     * @return for example Azure Boards
     */
    public static String kindLabel(String kind) {
        if (kind == RlyWorkTracker.AZURE) {
            return 'Azure Boards';
        }
        if (kind == RlyWorkTracker.OTHER) {
            return 'Other (link)';
        }
        return kind == null || kind == RlyWorkTracker.NONE ? 'No integration' : kind;
    }
}
