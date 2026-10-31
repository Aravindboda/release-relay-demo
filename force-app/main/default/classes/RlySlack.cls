/**
 * @description Slack notifications for releases. The hub's RLY_Notification__c record (channel Slack) turns Slack on
 * and picks the events; each target org picks its channel (Slack_Channel__c, Slack_Post__c). The Slack app (Named
 * Credential RLY_Slack) posts one card per release and edits it as the release moves (RlySlackDelivery); the old
 * incoming webhook is used only when the app isn't set up. Slack is optional: with no record, or Slack off, nothing
 * is called. Sending never throws: the result is kept for Last_Result__c and saved by saveResults(), which callers
 * run after all their callouts (a callout can't follow DML in the same transaction).
 */
public with sharing class RlySlack {

    /** @description The channel value of the Slack record. */
    public static final String CHANNEL = 'Slack';
    /** @description The only webhook URLs accepted (legacy). */
    public static final String WEBHOOK_PREFIX = 'https://hooks.slack.com/services/';
    /** @description Every event an admin can select. */
    public static final List<String> EVENTS = new List<String>{ 'Ready for approval', 'Checks failed', 'Deployed', 'Deploy failed', 'Rejected', 'Raised' };
    /** @description An approval (the merge starts): it edits the card and replies, whenever Slack is on. */
    public static final String APPROVED = 'Approved';

    private static final Set<String> STATUS_EVENTS = new Set<String>{ 'Ready for approval', 'Checks failed', 'Deployed', 'Deploy failed', 'Rejected' };
    private static final Integer TIMEOUT_MS = 10000;

    // The Slack record's last result, saved by saveResults() once the transaction's callouts are done.
    private static RLY_Notification__c pending;

    /**
     * @description The event a status change is, when it is one Slack can be told about. Raised is the move from
     * Retrieving to Workflow running; Approved is the move to Deploying (the merge starts).
     * @param oldStatus the status before
     * @param newStatus the status now
     * @return the event, or null
     */
    public static String eventFor(String oldStatus, String newStatus) {
        if (oldStatus == 'Retrieving' && newStatus == 'Workflow running') {
            return 'Raised';
        }
        if (oldStatus == newStatus) {
            return null;
        }
        return newStatus == 'Deploying' ? APPROVED : (STATUS_EVENTS.contains(newStatus) ? newStatus : null);
    }

    /**
     * @description Tells Slack about a release whose status changed (when that change is an event). Never throws.
     * @param rel the release, as RlyReleaseStore reads it, with its new status
     * @param oldStatus its status before
     */
    public static void notifyTransition(RLY_Release__c rel, String oldStatus) {
        String event = eventFor(oldStatus, rel.Status__c);
        if (event != null) {
            notify(rel, event);
        }
    }

    /**
     * @description Whether Slack is on (the record exists and is enabled).
     * @return true when on
     */
    public static Boolean isOn() {
        try {
            RLY_Notification__c s = settings();
            return s != null && s.Enabled__c;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Whether a message would be sent for an event (Slack on and the event selected; Approved whenever on).
     * @param event the event
     * @return true when it would be sent
     */
    public static Boolean wants(String event) {
        try {
            return wanted(settings(), event);
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Sends a release's card and reply when Slack is on and the event is selected. Never throws.
     * @param rel the release, as RlyReleaseStore reads it
     * @param event the event, one of EVENTS or APPROVED
     */
    public static void notify(RLY_Release__c rel, String event) {
        RLY_Notification__c s = settings();
        if (!wanted(s, event)) {
            return;
        }
        String what = rel.Name + ' · ' + event;
        String result;
        String appProblem;
        try {
            result = RlySlackDelivery.deliver(rel, event);
        } catch (Exception e) {
            appProblem = 'Failed: ' + what + ': ' + e.getMessage();
            result = RlySlackApi.isNotSetUp(e) ? null : appProblem;
        }
        if (result == null && event != APPROVED && String.isNotBlank(s.Webhook_URL__c)) {
            result = send(s, RlySlackMessage.forRelease(rel, event), what);
        }
        record(s.Id, result == null ? appProblem : result);
    }

    private static Boolean wanted(RLY_Notification__c s, String event) {
        return s != null && s.Enabled__c && (event == APPROVED || selected(s).contains(event));
    }

    // Legacy webhook post; the result is kept for saveResults(). Never throws.
    private static String send(RLY_Notification__c s, String payload, String what) {
        String result;
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(s.Webhook_URL__c.trim());
            req.setTimeout(TIMEOUT_MS);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(payload);
            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            result = code >= 200 && code < 300 ? 'Sent: ' + what
                : 'Failed: HTTP ' + code + ' for ' + what + ' ' + String.valueOf(res.getBody()).left(120);
        } catch (Exception e) {
            result = 'Failed: ' + what + ': ' + e.getMessage();
        }
        return result;
    }

    /**
     * @description Keeps a result for Last_Result__c (saved by saveResults()).
     * @param settingsId the Slack record
     * @param result what happened (null records nothing)
     */
    public static void record(Id settingsId, String result) {
        if (settingsId != null && result != null) {
            pending = new RLY_Notification__c(Id = settingsId, Last_Sent__c = System.now(), Last_Result__c = result.left(255));
        }
    }

    /**
     * @description Saves the last result (Last_Sent__c, Last_Result__c). Run it after every callout of the transaction.
     * Never throws.
     */
    public static void saveResults() {
        if (pending == null) {
            return;
        }
        RLY_Notification__c toSave = pending;
        pending = null;
        try {
            new Data().saveRecord(toSave);
        } catch (Exception e) {
            // Only the result line is lost; the release itself is saved already.
            pending = null;
        }
    }

    /**
     * @description The Slack record, webhook URL and signing secret included: for Apex only, never sent to the browser.
     * @return the record, or null when there is none
     */
    public static RLY_Notification__c settings() {
        return new Data().readSettings();
    }

    /**
     * @description Saves the Slack record (admins only; checked by RlySlackController).
     * @param s the fields to save
     */
    public static void saveSettings(RLY_Notification__c s) {
        new Data().saveRecord(s);
    }

    /**
     * @description The events selected on a Slack record.
     * @param s the record
     * @return the events
     */
    public static Set<String> selected(RLY_Notification__c s) {
        return String.isBlank(s.Events__c) ? new Set<String>() : new Set<String>(s.Events__c.split(';'));
    }

    /** @description The Slack record is hub configuration, read and written in system mode for the flow and for admins. */
    private without sharing class Data {

        /**
         * @description The Slack record.
         * @return the record, or null
         */
        public RLY_Notification__c readSettings() {
            List<RLY_Notification__c> rows = [SELECT Id, Name, Channel__c, Enabled__c, Webhook_URL__c, Signing_Secret__c, Events__c,
                                                     Last_Sent__c, Last_Result__c
                                              FROM RLY_Notification__c WHERE Channel__c = :CHANNEL WITH SYSTEM_MODE
                                              ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Inserts or updates the record.
         * @param s the fields to save
         */
        public void saveRecord(RLY_Notification__c s) {
            upsert as system s;
        }
    }
}
