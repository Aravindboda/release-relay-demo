/**
 * @description Work items (build 47): checks a tracker an admin adds or edits on the Pipeline tab: a name used by no
 * other tracker, a known kind, ticket patterns that are valid expressions and not already an active tracker's, at most
 * one active tracker without a pattern (it takes what the others don't), and each field's format (RlyWorkTrackerFields).
 * Fields that don't apply to the kind are cleared.
 */
public with sharing class RlyWorkTrackerCheck {

    private static final Integer MAX_NAME = 80;

    /**
     * @description The tracker as a record, after checking every value against the other trackers.
     * @param v the tracker from the page (id set when editing)
     * @return the record to save (Id set when editing)
     */
    public static RLY_Work_Tracker__c checked(RlyWorkTypes.TrackerView v) {
        String kind = kindOf(v.kind);
        String name = nameOf(v.name, v.id);
        String patterns = RlyWorkTrackerFields.trimmed(v.ticketPattern);
        RlyWorkTrackerFields.checkPatterns(patterns, 'ticket pattern');
        Boolean active = v.active != false;
        if (active) {
            checkNotTaken(patterns, v.id);
        }
        Boolean integrates = kind != RlyWorkTracker.NONE;
        Boolean posting = v.postUpdates == true && integrates;
        String stateMap = integrates ? RlyWorkTrackerFields.stateMapOf(v.stateMap) : null;
        String credential = integrates ? RlyWorkTrackerFields.credentialOf(v.namedCredential) : null;
        if (posting && credential == null) {
            throw new RlyReleaseException('Posting to the tracker needs the Named Credential your admin created in Setup (for example RLY_Work_Jira).');
        }
        RLY_Work_Tracker__c row = new RLY_Work_Tracker__c(Name = name, Type__c = kind, Ticket_Pattern__c = patterns,
            Link_Pattern__c = RlyWorkTrackerFields.linkOf(v.linkPattern), Post_Updates__c = posting, State_Map__c = stateMap, Active__c = active,
            Named_Credential__c = credential,
            ServiceNow_Table__c = kind == RlyWorkTracker.SERVICENOW ? RlyWorkTrackerFields.tableOf(v.serviceNowTable) : null,
            Change_Mentions_Release__c = v.changeMentionsRelease != false);
        placed(row, v.id);
        return row;
    }

    // Editing: the record's Id (it must still exist). Adding: the last place in the routing order.
    private static void placed(RLY_Work_Tracker__c row, Id trackerId) {
        if (trackerId == null) {
            row.Sort_Order__c = RlyWorkStore.trackers().size() + 1;
            return;
        }
        if (RlyWorkRouting.byId(trackerId) == null) {
            throw new RlyReleaseException('That tracker was removed: read the page again.');
        }
        row.Id = trackerId;
    }

    // No other active tracker has the same pattern; only one active tracker takes the rest (no pattern).
    private static void checkNotTaken(String patterns, Id selfId) {
        String mine = patterns == null ? '' : patterns.toLowerCase();
        for (RLY_Work_Tracker__c t : RlyWorkRouting.active()) {
            String theirs = String.isBlank(t.Ticket_Pattern__c) ? '' : t.Ticket_Pattern__c.trim().toLowerCase();
            if (t.Id != selfId && mine == theirs) {
                throw new RlyReleaseException(mine == '' ? t.Name + ' already takes every ticket the others don\'t (it has no pattern): give this tracker a pattern.'
                    : t.Name + ' already has the pattern ' + patterns + ': its tickets would never reach this tracker.');
            }
        }
    }

    private static String kindOf(String value) {
        String kind = String.isBlank(value) ? null : value.trim();
        if (kind == null || !RlyWorkTracker.TRACKERS.contains(kind)) {
            throw new RlyReleaseException('Pick Jira, Azure Boards, ServiceNow, No integration or Other.');
        }
        return kind;
    }

    private static String nameOf(String value, Id selfId) {
        String name = RlyWorkTrackerFields.trimmed(value);
        if (name == null || name.length() > MAX_NAME) {
            throw new RlyReleaseException('Give the tracker a name (up to ' + MAX_NAME + ' characters), for example Claims stories.');
        }
        for (RLY_Work_Tracker__c t : RlyWorkStore.trackers()) {
            if (t.Id != selfId && name.equalsIgnoreCase(t.Name)) {
                throw new RlyReleaseException('Another tracker is called ' + t.Name + '.');
            }
        }
        return name;
    }
}
