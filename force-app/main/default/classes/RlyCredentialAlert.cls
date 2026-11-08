/**
 * @description The Slack alert of the Credentials dashboard (build 49): when Slack is on and the hub org has a Slack
 * channel, one message lists the items that just turned Critical, Expired or Failed. An item that stays that way isn't
 * posted again. Callout only (the result is kept for the Slack record and saved with the rows); never throws.
 */
public with sharing class RlyCredentialAlert {

    private static final Integer MAX_LINES = 15;

    /**
     * @description Posts the alert.
     * @param turnedBad the items that just turned Critical, Expired or Failed
     * @return what happened, or null when nothing was to post
     */
    public static String post(List<RLY_Credential_Status__c> turnedBad) {
        if (turnedBad == null || turnedBad.isEmpty()) {
            return null;
        }
        RLY_Notification__c s;
        String channel;
        try {
            s = RlySlack.settings();
            channel = hubChannel();
        } catch (Exception e) {
            return null;
        }
        if (s == null || !s.Enabled__c || String.isBlank(channel)) {
            return null;
        }
        String result;
        try {
            RlySlackApi.call('chat.postMessage', new Map<String, Object>{ 'channel' => channel, 'text' => text(turnedBad) });
            result = 'Sent: credentials alert · ' + turnedBad.size() + (turnedBad.size() == 1 ? ' item' : ' items');
        } catch (Exception e) {
            result = 'Failed: credentials alert: ' + e.getMessage();
        }
        RlySlack.record(s.Id, result);
        return result;
    }

    /**
     * @description The message.
     * @param rows the items
     * @return the text
     */
    public static String text(List<RLY_Credential_Status__c> rows) {
        List<String> lines = new List<String>{ ':warning: *' + System.Label.RLY_App_Name + ' credentials need attention*' };
        for (Integer i = 0; i < rows.size() && i < MAX_LINES; i++) {
            RLY_Credential_Status__c r = rows[i];
            String expiry = r.Expires_On__c == null ? '' : ' · expires ' + Datetime.newInstance(r.Expires_On__c, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy');
            lines.add('• ' + r.Status__c + ': ' + r.Kind__c + ' · ' + r.Name + expiry + (String.isBlank(r.Message__c) ? '' : ' — ' + r.Message__c.left(200)));
        }
        if (rows.size() > MAX_LINES) {
            lines.add('… and ' + (rows.size() - MAX_LINES) + ' more.');
        }
        lines.add('Open ' + System.Label.RLY_App_Name + ' → Pipeline → Credentials for how to renew each one.');
        return String.join(lines, '\n');
    }

    // The hub org's Slack channel.
    private static String hubChannel() {
        for (RLY_Org__c o : RlyCredentialStore.orgs()) {
            if (o.Role__c == 'Hub' && String.isNotBlank(o.Slack_Channel__c)) {
                return o.Slack_Channel__c.trim();
            }
        }
        return null;
    }
}
