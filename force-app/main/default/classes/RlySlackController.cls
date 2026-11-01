/**
 * @description Pipeline tab, Slack connection card (admins): whether Slack is on and which events post, the Slack app's
 * connection (auth.test through the Named Credential RLY_Slack; the bot token stays in the External Credential), the
 * signing secret for Approve and Reject from Slack (encrypted; only a masked hint goes to the browser), the Site URL
 * to give Slack, and which approvers are linked to their Slack member IDs. Callouts come before any save.
 */
public with sharing class RlySlackController {

    /** @description What the Slack card shows. Never the signing secret, webhook URL or token. */
    public class SlackSettings {
        /** @description The current user is an admin (the card is shown only to admins). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description Slack is on. */
        @AuraEnabled public Boolean enabled = false;
        /** @description The selected events. */
        @AuraEnabled public List<String> events = new List<String>();
        /** @description Every event that can be selected. */
        @AuraEnabled public List<String> allEvents = RlySlack.EVENTS;
        /** @description The Slack app answers through the Named Credential. */
        @AuraEnabled public Boolean connected = false;
        /** @description The Slack workspace, when connected. */
        @AuraEnabled public String workspace;
        /** @description Connected, Not set up, or Error: the reason. */
        @AuraEnabled public String status = 'Not set up';
        /** @description Saved (ends ••••xxxx), or null when no signing secret is saved. */
        @AuraEnabled public String signingSecretHint;
        /** @description The Interactivity Request URL to give Slack, or null when no Site is set up. */
        @AuraEnabled public String actionsUrl;
        /** @description Approvers linked to a Slack member ID. */
        @AuraEnabled public Integer approversLinked = 0;
        /** @description Every approver. */
        @AuraEnabled public Integer approversTotal = 0;
        /** @description Every approver and their Slack member ID. */
        @AuraEnabled public List<ApproverLink> approvers = new List<ApproverLink>();
        /** @description When the last message was sent. */
        @AuraEnabled public Datetime lastSent;
        /** @description What happened to it. */
        @AuraEnabled public String lastResult;
    }

    /** @description An approver and their Slack member ID. */
    public class ApproverLink {
        /** @description The user. */
        @AuraEnabled public Id userId;
        /** @description The user's name. */
        @AuraEnabled public String name;
        /** @description The Slack member ID, or null. */
        @AuraEnabled public String slackMemberId;
    }

    /** @description What the card saves. */
    public class SlackInput {
        /** @description Slack on or off. */
        public Boolean enabled;
        /** @description The selected events. */
        public List<String> events;
        /** @description A new signing secret, or blank to keep the saved one. */
        public String signingSecret;
    }

    /**
     * @description The Slack settings and connection for the card (empty for users who aren't admins).
     * @return the settings
     */
    @AuraEnabled
    public static SlackSettings getSlack() {
        if (!RlyOrgController.isAdmin()) {
            return new SlackSettings();
        }
        return fill(connection());
    }

    /**
     * @description Saves the Slack settings. A blank signing secret keeps the saved one. Turning Slack on with no event
     * selected selects all six.
     * @param settingsJson a SlackInput as JSON
     * @return the settings as saved
     */
    @AuraEnabled
    public static SlackSettings saveSlack(String settingsJson) {
        requireAdmin();
        SlackInput input = readInput(settingsJson);
        RLY_Notification__c saved = RlySlack.settings();
        RLY_Notification__c row = new RLY_Notification__c(Id = saved == null ? null : saved.Id, Name = RlySlack.CHANNEL,
            Channel__c = RlySlack.CHANNEL, Enabled__c = input.enabled == true, Events__c = RlySlackRules.events(input.events));
        if (row.Enabled__c && row.Events__c == null && (saved == null || !saved.Enabled__c)) {
            row.Events__c = String.join(RlySlack.EVENTS, ';');
        }
        String secret = RlySlackRules.signingSecret(input.signingSecret);
        if (secret != null) {
            row.Signing_Secret__c = secret;
        }
        SlackSettings out = connection();
        RlySlack.saveSettings(row);
        return fill(out);
    }

    /**
     * @description Checks the Slack app's connection (auth.test).
     * @return the settings, with the workspace and status
     */
    @AuraEnabled
    public static SlackSettings testSlack() {
        RlyHubGuard.requireHub();
        requireAdmin();
        return fill(connection());
    }

    /**
     * @description Posts a test message to a channel and records the result.
     * @param channel #channel-name or a channel ID (invite the app to it first)
     * @return the settings, with the result
     */
    @AuraEnabled
    public static SlackSettings sendSlackTest(String channel) {
        RlyHubGuard.requireHub();
        requireAdmin();
        RLY_Notification__c s = RlySlack.settings();
        if (s == null) {
            throw auraError('Save the Slack settings first.');
        }
        if (!RlySlackRules.isChannel(channel)) {
            throw auraError('Type a channel such as #channel-name, or a channel ID.');
        }
        SlackSettings out = connection();
        String result;
        try {
            RlySlackApi.call('chat.postMessage', new Map<String, Object>{ 'channel' => channel.trim(),
                'text' => System.Label.RLY_App_Name + ' test message from ' + URL.getOrgDomainUrl().toExternalForm() });
            result = 'Sent: test message to ' + channel.trim();
        } catch (Exception e) {
            result = 'Failed: test message to ' + channel.trim() + ': ' + e.getMessage();
        }
        RlySlack.record(s.Id, result);
        RlySlack.saveResults();
        return fill(out);
    }

    /**
     * @description Links an approver to their Slack member ID (admins only). Blank clears it.
     * @param userId the user
     * @param memberId the Slack member ID (U…), or blank
     * @return the settings
     */
    @AuraEnabled
    public static SlackSettings saveSlackMember(Id userId, String memberId) {
        requireAdmin();
        if (userId == null) {
            throw auraError('Pick a user.');
        }
        String value = RlySlackRules.memberId(memberId);
        SlackSettings out = connection();
        RlySlackDirectory.link(userId, value);
        return fill(out);
    }

    // auth.test: a callout, so it comes before the saves.
    private static SlackSettings connection() {
        SlackSettings out = new SlackSettings();
        out.isAdmin = true;
        try {
            Map<String, Object> r = RlySlackApi.call('auth.test', new Map<String, Object>());
            out.connected = true;
            out.workspace = r.get('team') == null ? null : String.valueOf(r.get('team'));
            out.status = 'Connected';
        } catch (Exception e) {
            out.status = RlySlackApi.isNotSetUp(e) ? 'Not set up' : ('Error: ' + e.getMessage()).left(255);
        }
        return out;
    }

    private static SlackSettings fill(SlackSettings out) {
        RLY_Notification__c s = RlySlack.settings();
        if (s != null) {
            out.enabled = s.Enabled__c;
            out.events = new List<String>(RlySlack.selected(s));
            out.signingSecretHint = String.isBlank(s.Signing_Secret__c) ? null : 'Saved (ends ••••' + s.Signing_Secret__c.right(4) + ')';
            out.lastSent = s.Last_Sent__c;
            out.lastResult = s.Last_Result__c;
        }
        out.actionsUrl = RlySlackDirectory.actionsUrl();
        for (User u : RlySlackDirectory.approvers()) {
            ApproverLink link = new ApproverLink();
            link.userId = u.Id;
            link.name = u.Name;
            link.slackMemberId = u.RLY_Slack_Member_Id__c;
            out.approvers.add(link);
            out.approversLinked += String.isBlank(u.RLY_Slack_Member_Id__c) ? 0 : 1;
        }
        out.approversTotal = out.approvers.size();
        return out;
    }

    private static SlackInput readInput(String settingsJson) {
        try {
            SlackInput input = (SlackInput) JSON.deserialize(settingsJson, SlackInput.class);
            return input == null ? new SlackInput() : input;
        } catch (Exception e) {
            throw auraError('The Slack settings couldn\'t be read.');
        }
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw auraError('Changing Slack needs the ' + System.Label.RLY_App_Name + ' Admin permission set.');
        }
    }

    /**
     * @description An error the page shows as it is.
     * @param message the message
     * @return the exception
     */
    public static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
