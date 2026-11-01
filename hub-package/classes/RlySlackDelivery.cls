/**
 * @description Posts a release's Slack card through the Slack app: the first event posts the card in the target org's
 * channel (and saves its channel ID and ts on the release); later events edit the card and reply in its thread. A
 * developer org with Post to Slack and a channel also gets a plain one-line copy (not tracked). Callouts only: the
 * caller saves the release.
 */
public with sharing class RlySlackDelivery {

    /**
     * @description Delivers an event. Throws RlySlackApi.SlackException when Slack refuses the card.
     * @param rel the release, as RlyReleaseStore reads it, with its new status
     * @param event the event
     * @return the result for Last_Result__c, or null when no org posts to Slack
     */
    public static String deliver(RLY_Release__c rel, String event) {
        String approverName = RlyReleaseStore.userName(rel.Approved_By__c);
        String result = toTarget(rel, event, approverName);
        if (copyToSource(rel, event, approverName) && result == null) {
            result = 'Sent: ' + rel.Name + ' · ' + event;
        }
        return result;
    }

    /**
     * @description The channel releases into an org post to.
     * @param org the org, with Slack_Post__c and Slack_Channel__c
     * @return the channel, or null when the org doesn't post to Slack
     */
    public static String channelOf(RLY_Org__c org) {
        return org == null || org.Slack_Post__c != true || String.isBlank(org.Slack_Channel__c) ? null : org.Slack_Channel__c.trim();
    }

    private static String toTarget(RLY_Release__c rel, String event, String approverName) {
        String channel = channelOf(rel.Target_Org__r);
        if (channel == null) {
            return null;
        }
        Map<String, Object> card = RlySlackCard.card(rel, approverName);
        if (String.isBlank(rel.Slack_Ts__c) || String.isBlank(rel.Slack_Channel_Id__c)) {
            card.put('channel', channel);
            Map<String, Object> posted = RlySlackApi.call('chat.postMessage', card);
            rel.Slack_Channel_Id__c = String.valueOf(posted.get('channel')).left(40);
            rel.Slack_Ts__c = String.valueOf(posted.get('ts')).left(40);
        } else {
            card.put('channel', rel.Slack_Channel_Id__c);
            card.put('ts', rel.Slack_Ts__c);
            RlySlackApi.call('chat.update', card);
        }
        RlySlackApi.call('chat.postMessage', new Map<String, Object>{ 'channel' => rel.Slack_Channel_Id__c,
            'thread_ts' => rel.Slack_Ts__c, 'text' => RlySlackReply.forEvent(rel, event, approverName) });
        return 'Sent: ' + rel.Name + ' · ' + event;
    }

    // A copy for the developer org's channel; a failure here doesn't affect the card.
    private static Boolean copyToSource(RLY_Release__c rel, String event, String approverName) {
        String channel = channelOf(rel.Source_Org__r);
        if (channel == null || rel.Source_Org__c == rel.Target_Org__c) {
            return false;
        }
        try {
            RlySlackApi.call('chat.postMessage', new Map<String, Object>{ 'channel' => channel,
                'text' => '*' + RlySlackMessage.esc(rel.Name + ' · ' + rel.Title__c) + '*: ' + RlySlackReply.forEvent(rel, event, approverName) });
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
