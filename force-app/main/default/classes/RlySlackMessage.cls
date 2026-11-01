/**
 * @description The legacy webhook message for a release event (used only when the Slack app isn't set up): a header
 * (REL · event), the title, the route, who raised it, the reason when its checks failed, and a button that opens the
 * release on the hub's Releases tab, and its post (postWebhook). Also the shared pieces of the Slack card: the link, the reason and escaping.
 */
public with sharing class RlySlackMessage {

    private static final Integer TIMEOUT_MS = 10000;

    /**
     * @description Posts a message to the legacy incoming webhook. Never throws.
     * @param webhookUrl the webhook URL (RLY_Notification__c.Webhook_URL__c)
     * @param payload the message as JSON (forRelease)
     * @param what what is sent, for the result
     * @return the result for Last_Result__c
     */
    public static String postWebhook(String webhookUrl, String payload, String what) {
        String result;
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(webhookUrl.trim());
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
     * @description The message as JSON.
     * @param rel the release, as RlyReleaseStore reads it
     * @param event the event
     * @return the webhook payload
     */
    public static String forRelease(RLY_Release__c rel, String event) {
        String header = (rel.Name + ' · ' + event).left(150);
        List<Object> blocks = new List<Object>{
            new Map<String, Object>{ 'type' => 'header', 'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => header } },
            new Map<String, Object>{ 'type' => 'section', 'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => body(rel, event).left(2900) } },
            new Map<String, Object>{ 'type' => 'actions', 'elements' => new List<Object>{ new Map<String, Object>{
                'type' => 'button', 'text' => new Map<String, Object>{ 'type' => 'plain_text', 'text' => 'Open in ' + System.Label.RLY_App_Name },
                'url' => link(rel) } } }
        };
        return JSON.serialize(new Map<String, Object>{ 'text' => header + ': ' + rel.Title__c, 'blocks' => blocks });
    }

    /**
     * @description The release on the hub's Releases tab.
     * @param rel the release
     * @return the URL
     */
    public static String link(RLY_Release__c rel) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/RLY_My_Releases?c__release=' + rel.Id;
    }

    private static String body(RLY_Release__c rel, String event) {
        String text = '*' + esc(rel.Title__c) + '*\n'
            + esc(rel.Source_Org__r == null ? '' : rel.Source_Org__r.Name) + ' → '
            + esc(rel.Target_Org__r == null ? '' : rel.Target_Org__r.Name) + ' · ' + esc(rel.Target_Branch__c) + '\n'
            + 'Raised by ' + esc(rel.CreatedBy == null ? '' : rel.CreatedBy.Name);
        String reason = event == 'Checks failed' ? checksReason(rel) : (event == 'Deploy failed' || event == 'Rejected' ? rel.Error_Message__c : null);
        return String.isBlank(reason) ? text : text + '\n' + esc(reason.left(500));
    }

    /**
     * @description Why the checks failed: the validation's message and/or the code scan's.
     * @param rel the release
     * @return the reason, one line per check
     */
    public static String checksReason(RLY_Release__c rel) {
        List<String> parts = new List<String>();
        if (blocks(rel.Validation_Status__c)) {
            parts.add('Validation: ' + messageOf(rel.Validation_Result__c, 'failed'));
        }
        if (blocks(rel.Scan_Status__c)) {
            parts.add('Code scan: ' + messageOf(rel.Scan_Result__c,
                rel.Scan_Blocking__c == null ? 'failed' : rel.Scan_Blocking__c.intValue() + ' blocking finding(s)'));
        }
        return String.join(parts, '\n');
    }

    private static Boolean blocks(String checkStatus) {
        return checkStatus == 'Failed' || checkStatus == 'Error';
    }

    private static String messageOf(String resultJson, String fallback) {
        try {
            Object m = ((Map<String, Object>) JSON.deserializeUntyped(resultJson)).get('message');
            return m == null ? fallback : String.valueOf(m);
        } catch (Exception e) {
            return fallback;
        }
    }

    /**
     * @description Escapes text for Slack mrkdwn (&amp; &lt; &gt;).
     * @param value the text
     * @return the escaped text, or an empty string
     */
    public static String esc(String value) {
        return value == null ? '' : value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}
