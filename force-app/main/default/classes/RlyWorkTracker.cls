/**
 * @description Work items (build 40): the work tracker, through the Named Credential the admin set up (callout:<name>/…;
 * Release Relay never holds the tracker's password or token). Posts a moment to a ticket (RlyWorkCalls makes the
 * calls for Jira, Azure Boards, ServiceNow or a web call) and reads a ServiceNow change request for the production gate
 * (RlyWorkGate). Callouts only, no DML.
 */
public with sharing class RlyWorkTracker {

    /** @description Jira. */
    public static final String JIRA = 'Jira';
    /** @description Azure Boards. */
    public static final String AZURE = 'Azure_Boards';
    /** @description ServiceNow. */
    public static final String SERVICENOW = 'ServiceNow';
    /** @description No integration: tracked in Release Relay only. */
    public static final String NONE = 'None';
    /** @description Links, and an optional web call. */
    public static final String OTHER = 'Other';
    /** @description The trackers. */
    public static final Set<String> TRACKERS = new Set<String>{ JIRA, AZURE, SERVICENOW, NONE, OTHER };

    /**
     * @description Whether the settings post to a tracker.
     * @param s the settings, or null
     * @return true with a tracker, a Named Credential and Post updates on
     */
    public static Boolean posts(RLY_Work_Tracking__c s) {
        return s != null && s.Post_Updates__c == true && String.isNotBlank(s.Named_Credential__c) && s.Tracker__c != NONE
            && TRACKERS.contains(s.Tracker__c);
    }

    /**
     * @description Posts one moment to a ticket.
     * @param s the settings
     * @param m the ticket, moment, comment and release details
     * @return the outcome
     */
    public static RlyWorkTypes.Outcome post(RLY_Work_Tracking__c s, RlyWorkTypes.Message m) {
        RlyWorkTypes.Outcome o = new RlyWorkTypes.Outcome();
        try {
            m.state = stateFor(s, m.moment);
            if (s.Tracker__c == JIRA) {
                RlyWorkCalls.jira(s, m, o);
            } else if (s.Tracker__c == AZURE) {
                RlyWorkCalls.azure(s, m, o);
            } else if (s.Tracker__c == SERVICENOW) {
                RlyWorkCalls.serviceNow(s, m, o);
            } else {
                RlyWorkCalls.webCall(s, m, o);
            }
        } catch (Exception e) {
            o.ok = false;
            o.message = ('Couldn\'t reach the tracker: ' + e.getMessage()).left(255);
        }
        return o;
    }

    /**
     * @description Reads a ServiceNow change request: approved, and now inside its planned start and end.
     * @param s the settings
     * @param changeNo the change number
     * @return the change
     */
    public static RlyWorkTypes.Change change(RLY_Work_Tracking__c s, String changeNo) {
        RlyWorkTypes.Change c = new RlyWorkTypes.Change();
        try {
            Map<String, Object> rec = RlyWorkCalls.changeRecord(s, changeNo);
            if (rec == null) {
                c.message = changeNo + ' wasn\'t found in ServiceNow.';
                return c;
            }
            readChange(rec, changeNo, c);
        } catch (Exception e) {
            c.message = 'Couldn\'t read ' + changeNo + ' in ServiceNow: ' + e.getMessage();
        }
        return c;
    }

    // Approved and inside the planned window (ServiceNow sends GMT "yyyy-MM-dd HH:mm:ss").
    private static void readChange(Map<String, Object> rec, String changeNo, RlyWorkTypes.Change c) {
        String approval = String.valueOf(rec.get('approval'));
        Datetime starts = gmt(rec.get('start_date'));
        Datetime ends = gmt(rec.get('end_date'));
        Datetime now = System.now();
        if (approval != 'approved') {
            c.message = changeNo + ' isn\'t approved yet (approval: ' + approval + ', state: ' + rec.get('state') + ').';
        } else if (starts != null && now < starts) {
            c.message = changeNo + ' is approved; its window starts ' + starts.format() + '.';
        } else if (ends != null && now > ends) {
            c.message = changeNo + ' is approved but its window ended ' + ends.format() + '.';
        } else {
            c.allowed = true;
            c.message = changeNo + ' is approved' + (ends == null ? '' : ' until ' + ends.format()) + '.';
        }
    }

    // The state or transition the admin mapped to this moment ({"Deployed to SIT":"In QA"}), or null.
    private static String stateFor(RLY_Work_Tracking__c s, String moment) {
        if (String.isBlank(s.State_Map__c)) {
            return null;
        }
        try {
            Object m = JSON.deserializeUntyped(s.State_Map__c);
            Object v = m instanceof Map<String, Object> ? ((Map<String, Object>) m).get(moment) : null;
            return v == null ? null : String.valueOf(v);
        } catch (JSONException e) {
            return null;
        }
    }

    private static Datetime gmt(Object value) {
        String s = value == null ? '' : String.valueOf(value).trim();
        if (s.length() < 19) {
            return null;
        }
        try {
            return Datetime.valueOfGmt(s.left(19));
        } catch (Exception e) {
            return null;
        }
    }
}
