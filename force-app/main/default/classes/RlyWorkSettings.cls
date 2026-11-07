/**
 * @description Work items (build 40): the work tracking settings between the record and the Pipeline tab card. Checks
 * every value an admin saves: a known tracker, ticket and change formats that are valid expressions, an https link
 * with {id}, a Named Credential API name (needed to post or for the change gate), a state map that is a JSON object.
 */
public with sharing class RlyWorkSettings {

    private static final Pattern CREDENTIAL_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');

    /**
     * @description The settings for the pages.
     * @param r the record, or null
     * @return the settings
     */
    public static RlyWorkTypes.Settings viewOf(RLY_Work_Tracking__c r) {
        RlyWorkTypes.Settings v = new RlyWorkTypes.Settings();
        v.isAdmin = RlyOrgController.isAdmin();
        v.trackerLabel = RlyWorkBoard.trackerLabel(r);
        v.tracker = RlyWorkTracker.NONE;
        if (r == null) {
            return v;
        }
        v.tracker = String.isBlank(r.Tracker__c) ? RlyWorkTracker.NONE : r.Tracker__c;
        v.required = r.Required__c == true;
        v.ticketPattern = r.Ticket_Pattern__c;
        v.linkPattern = r.Link_Pattern__c;
        v.namedCredential = r.Named_Credential__c;
        v.postUpdates = r.Post_Updates__c == true;
        v.stateMap = r.State_Map__c;
        v.serviceNowTable = r.ServiceNow_Table__c;
        v.requireChange = r.Require_Change__c == true;
        v.changePattern = r.Change_Pattern__c;
        return v;
    }

    /**
     * @description The settings as a record, after checking every value.
     * @param v the settings from the page
     * @return the record to save
     */
    public static RLY_Work_Tracking__c checked(RlyWorkTypes.Settings v) {
        String tracker = trackerOf(v.tracker);
        checkPatterns(v.ticketPattern, 'ticket format');
        checkPatterns(v.changePattern, 'change format');
        checkStateMap(v.stateMap);
        Boolean posting = v.postUpdates == true && tracker != RlyWorkTracker.NONE;
        Boolean gate = v.requireChange == true && tracker == RlyWorkTracker.SERVICENOW;
        String credential = credentialOf(v.namedCredential, posting || gate);
        return new RLY_Work_Tracking__c(Tracker__c = tracker, Required__c = v.required == true, Ticket_Pattern__c = trimmed(v.ticketPattern),
            Link_Pattern__c = linkOf(v.linkPattern), Named_Credential__c = credential, Post_Updates__c = posting,
            State_Map__c = trimmed(v.stateMap), ServiceNow_Table__c = trimmed(v.serviceNowTable), Require_Change__c = gate,
            Change_Pattern__c = trimmed(v.changePattern));
    }

    private static String trackerOf(String value) {
        String tracker = String.isBlank(value) ? RlyWorkTracker.NONE : value.trim();
        if (!RlyWorkTracker.TRACKERS.contains(tracker)) {
            throw new RlyReleaseException('Pick Jira, Azure Boards, ServiceNow, No integration or Other.');
        }
        return tracker;
    }

    private static String linkOf(String value) {
        String link = trimmed(value);
        if (link != null && (!link.startsWith('https://') || !link.contains('{id}') || link.length() > 255)) {
            throw new RlyReleaseException('The link starts with https:// and has {id} where the ticket number goes.');
        }
        return link;
    }

    private static String credentialOf(String value, Boolean needed) {
        String credential = trimmed(value);
        if (credential != null && !CREDENTIAL_NAME.matcher(credential).matches()) {
            throw new RlyReleaseException('The Named Credential is its API name, for example Jira_Cloud.');
        }
        if (needed && credential == null) {
            throw new RlyReleaseException('Posting to the tracker (or the change gate) needs the Named Credential your admin created in Setup.');
        }
        return credential;
    }

    private static void checkPatterns(String patterns, String what) {
        String p = trimmed(patterns);
        if (p == null) {
            return;
        }
        if (p.length() > 255) {
            throw new RlyReleaseException('The ' + what + ' is up to 255 characters.');
        }
        for (String f : p.split('\\s+')) {
            try {
                Pattern.compile(f);
            } catch (Exception e) {
                throw new RlyReleaseException('"' + f + '" in the ' + what + ' isn\'t a valid pattern.');
            }
        }
    }

    private static void checkStateMap(String stateMap) {
        String m = trimmed(stateMap);
        if (m == null) {
            return;
        }
        Boolean ok;
        try {
            ok = JSON.deserializeUntyped(m) instanceof Map<String, Object>;
        } catch (JSONException e) {
            ok = false;
        }
        if (!ok) {
            throw new RlyReleaseException('The state map is JSON like {"Deployed to SIT":"In QA"}.');
        }
    }

    private static String trimmed(String s) {
        return String.isBlank(s) ? null : s.trim();
    }
}
