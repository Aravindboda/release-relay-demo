/**
 * @description One Approve or Reject press on a Slack card (RlySlackAction): who pressed it, where, and on which
 * release, and the private (ephemeral) replies to that person: an error, a refusal, or, for an approver who isn't linked
 * yet, "Link my account" (a URL button to the Link your Slack account tab with a signed token, RlySlackLink).
 */
public with sharing class RlySlackPress {

    /** @description action_id of the Link my account button (a URL button; its click needs no answer). */
    public static final String LINK_ACTION = 'rly_link_account';

    /** @description The button's action_id. */
    public String actionId;
    /** @description The Slack user who pressed. */
    public String memberId;
    /** @description The channel of the card. */
    public String channelId;
    /** @description The Slack workspace. */
    public String teamId;
    /** @description The trigger for a form (Reject). */
    public String triggerId;
    /** @description The release on the card, or null. */
    public RLY_Release__c rel;

    /**
     * @description Reads a block_actions payload.
     * @param p the payload
     */
    public RlySlackPress(Map<String, Object> p) {
        List<Object> actions = (List<Object>) p.get('actions');
        Map<String, Object> action = actions == null || actions.isEmpty() ? new Map<String, Object>() : (Map<String, Object>) actions[0];
        actionId = RlySlackPayload.text(action, 'action_id');
        memberId = RlySlackPayload.text(RlySlackPayload.child(p, 'user'), 'id');
        channelId = RlySlackPayload.text(RlySlackPayload.child(p, 'channel'), 'id');
        teamId = RlySlackPayload.text(RlySlackPayload.child(p, 'team'), 'id');
        triggerId = RlySlackPayload.text(p, 'trigger_id');
        rel = isCardButton() ? RlySlackPayload.release(RlySlackPayload.text(action, 'value')) : null;
    }

    /**
     * @description Whether the press is Approve or Reject on a card.
     * @return true when it is
     */
    public Boolean isCardButton() {
        return actionId == RlySlackCard.APPROVE_ACTION || actionId == RlySlackCard.REJECT_ACTION;
    }

    /**
     * @description Whether the release on the card can be approved in Slack.
     * @return true when it can
     */
    public Boolean releaseInSlack() {
        return rel != null && RlyApprover.inSlack(rel.Target_Org__r);
    }

    /**
     * @description Tells the person who pressed, privately, why nothing happened: the release isn't approved in Slack,
     * they aren't an approver, or they link their account first.
     * @param found the on-the-spot match, or null when none was tried
     */
    public void refuse(RlySlackPresser found) {
        if (found == null) {
            whisper(RlySlackAction.refusal(rel), null);
        } else if (found.notApprover) {
            whisper(RlySlackLink.CANT_APPROVE, null);
        } else {
            RLY_Notification__c s = RlySlack.settings();
            String url = RlySlackLink.url(RlySlackLink.token(memberId, teamId, s.Signing_Secret__c), rel.Id);
            String text = notLinkedText(actionId == RlySlackCard.APPROVE_ACTION ? 'Approve' : 'Reject');
            whisper(text, linkBlocks(text, url));
        }
    }

    /**
     * @description What an unlinked approver is told first.
     * @param verb Approve or Reject
     * @return the sentence
     */
    public static String notLinkedText(String verb) {
        return 'You\'re not linked to ' + System.Label.RLY_App_Name + ' yet, so your ' + verb + ' wasn\'t counted.';
    }

    // The private reply with the Link my account button.
    private static List<Object> linkBlocks(String text, String url) {
        Map<String, Object> intro = new Map<String, Object>{ 'type' => 'section', 'text' => new Map<String, Object>{ 'type' => 'mrkdwn',
            'text' => text + '\nLink your Slack account to your Salesforce user once; after that, Approve and Reject here work for you.' } };
        Map<String, Object> button = new Map<String, Object>{ 'type' => 'button', 'action_id' => LINK_ACTION, 'style' => 'primary',
            'text' => RlySlackCard.plain('Link my account'), 'url' => url };
        Map<String, Object> note = new Map<String, Object>{ 'type' => 'context', 'elements' => new List<Object>{
            new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => 'The link works for ' + RlySlackLink.MINUTES
                + ' minutes and only for you. Ask an admin if you aren\'t an approver.' } } };
        return new List<Object>{ intro, new Map<String, Object>{ 'type' => 'actions', 'elements' => new List<Object>{ button } }, note };
    }

    /**
     * @description A message only the person who pressed sees (chat.postEphemeral). Never throws.
     * @param message the text
     * @param blocks Block Kit blocks, or null for text only
     */
    public void whisper(String message, List<Object> blocks) {
        if (String.isBlank(channelId) || String.isBlank(memberId)) {
            return;
        }
        Map<String, Object> body = new Map<String, Object>{ 'channel' => channelId, 'user' => memberId, 'text' => message };
        if (blocks != null) {
            body.put('blocks', blocks);
        }
        try {
            RlySlackApi.call('chat.postEphemeral', body);
        } catch (Exception e) {
            return;
        }
    }
}
