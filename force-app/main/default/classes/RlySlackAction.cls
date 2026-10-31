/**
 * @description Handles Slack's button clicks and form submissions (RlySlackActions): checks the signature, maps the
 * Slack user to a Release Relay approver (User.RLY_Slack_Member_Id__c, holding RLY_Approver or RLY_Admin), and only
 * for releases into an org approved in Slack. Approve approves for that user; Reject opens a form asking why, and its
 * submission rejects for that user. Refusals go back to the user only (ephemeral). Slack is optional: with Slack off,
 * no signing secret, or a bad signature, the request is refused.
 */
public with sharing class RlySlackAction {

    /** @description callback_id of the reject form. */
    public static final String REJECT_FORM = 'rly_reject_form';
    /** @description block_id of the reason input. */
    public static final String REASON_BLOCK = 'reason';
    /** @description action_id of the reason input. */
    public static final String REASON_INPUT = 'reason_input';

    /** @description What goes back to Slack. */
    public class Reply {
        /** @description HTTP status. */
        public Integer status = 200;
        /** @description JSON body, or empty. */
        public String body = '';
    }

    /**
     * @description Handles one request. Never throws.
     * @param req the request from Slack
     * @return the reply
     */
    public static Reply handle(RestRequest req) {
        Reply out = new Reply();
        try {
            RLY_Notification__c s = RlySlack.settings();
            if (s == null || !s.Enabled__c || !RlySlackSignature.isValid(req, s.Signing_Secret__c)) {
                out.status = 401;
                return out;
            }
            Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(RlySlackSignature.payload(req));
            String kind = RlySlackPayload.text(p, 'type');
            if (kind == 'block_actions') {
                onButton(p);
            } else if (kind == 'view_submission') {
                out.body = onRejectForm(p);
            }
        } catch (Exception e) {
            out.body = '';
        }
        return out;
    }

    private static void onButton(Map<String, Object> p) {
        List<Object> actions = (List<Object>) p.get('actions');
        Map<String, Object> action = actions == null || actions.isEmpty() ? new Map<String, Object>() : (Map<String, Object>) actions[0];
        String actionId = RlySlackPayload.text(action, 'action_id');
        if (actionId != RlySlackCard.APPROVE_ACTION && actionId != RlySlackCard.REJECT_ACTION) {
            return;
        }
        String memberId = RlySlackPayload.text(RlySlackPayload.child(p, 'user'), 'id');
        String channelId = RlySlackPayload.text(RlySlackPayload.child(p, 'channel'), 'id');
        RLY_Release__c rel = RlySlackPayload.release(RlySlackPayload.text(action, 'value'));
        User u = allowedUser(rel, memberId);
        if (u == null) {
            whisper(channelId, memberId, refusal(rel));
        } else if (actionId == RlySlackCard.APPROVE_ACTION) {
            approve(rel, u, channelId);
        } else {
            openRejectForm(RlySlackPayload.text(p, 'trigger_id'), rel);
        }
    }

    private static void approve(RLY_Release__c rel, User u, String channelId) {
        try {
            RlyApprovalService.approveAs(rel.Id, RlyApprover.slackUser(u, null));
        } catch (Exception e) {
            whisper(channelId, u.RLY_Slack_Member_Id__c, rel.Name + ': ' + e.getMessage());
        }
    }

    private static String onRejectForm(Map<String, Object> p) {
        Map<String, Object> view = RlySlackPayload.child(p, 'view');
        if (RlySlackPayload.text(view, 'callback_id') != REJECT_FORM) {
            return '';
        }
        RLY_Release__c rel = RlySlackPayload.release(RlySlackPayload.text(view, 'private_metadata'));
        User u = allowedUser(rel, RlySlackPayload.text(RlySlackPayload.child(p, 'user'), 'id'));
        if (u == null) {
            return formError(refusal(rel));
        }
        try {
            RlyApprovalService.rejectAs(rel.Id, RlyApprover.slackUser(u, reason(view)));
        } catch (Exception e) {
            return formError(e.getMessage());
        }
        return '';
    }

    // view.state.values.reason.reason_input.value
    private static String reason(Map<String, Object> view) {
        Map<String, Object> values = RlySlackPayload.child(RlySlackPayload.child(view, 'state'), 'values');
        return RlySlackPayload.text(RlySlackPayload.child(RlySlackPayload.child(values, REASON_BLOCK), REASON_INPUT), 'value');
    }

    private static String formError(String message) {
        return JSON.serialize(new Map<String, Object>{ 'response_action' => 'errors',
            'errors' => new Map<String, Object>{ REASON_BLOCK => message.left(150) } });
    }

    private static void openRejectForm(String triggerId, RLY_Release__c rel) {
        Map<String, Object> input = new Map<String, Object>{ 'type' => 'input', 'block_id' => REASON_BLOCK,
            'label' => RlySlackCard.plain('Why are you rejecting?'),
            'element' => new Map<String, Object>{ 'type' => 'plain_text_input', 'action_id' => REASON_INPUT, 'multiline' => true } };
        Map<String, Object> view = new Map<String, Object>{ 'type' => 'modal', 'callback_id' => REJECT_FORM,
            'private_metadata' => String.valueOf(rel.Id), 'title' => RlySlackCard.plain(('Reject ' + rel.Name).left(24)),
            'submit' => RlySlackCard.plain('Reject release'), 'close' => RlySlackCard.plain('Cancel'),
            'blocks' => new List<Object>{ input } };
        try {
            RlySlackApi.call('views.open', new Map<String, Object>{ 'trigger_id' => triggerId, 'view' => view });
        } catch (Exception e) {
            return;
        }
    }

    // A message only that Slack user sees.
    private static void whisper(String channelId, String memberId, String message) {
        if (String.isBlank(channelId) || String.isBlank(memberId)) {
            return;
        }
        try {
            RlySlackApi.call('chat.postEphemeral', new Map<String, Object>{ 'channel' => channelId, 'user' => memberId, 'text' => message });
        } catch (Exception e) {
            return;
        }
    }

    /**
     * @description What a Slack user who may not act on the release is told.
     * @param rel the release, or null
     * @return the message
     */
    public static String refusal(RLY_Release__c rel) {
        return 'You can\'t approve ' + (rel == null ? 'this release' : rel.Name) + '. Ask an admin to link your Slack account in '
            + System.Label.RLY_App_Name + ' → Pipeline.';
    }

    // The linked approver, for a release into an org approved in Slack; otherwise null.
    private static User allowedUser(RLY_Release__c rel, String memberId) {
        if (rel == null || !RlyApprover.inSlack(rel.Target_Org__r)) {
            return null;
        }
        User u = RlySlackDirectory.approverFor(memberId);
        if (u != null) {
            u.RLY_Slack_Member_Id__c = memberId;
        }
        return u;
    }
}
