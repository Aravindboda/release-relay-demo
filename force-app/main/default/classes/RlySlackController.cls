/**
 * @description Pipeline tab, Slack card (admins): whether Slack is on, the webhook URL (encrypted; never sent to the
 * browser, only a masked hint), the events that send a message, and a test message.
 */
public with sharing class RlySlackController {

    /** @description What the Slack card shows. Never the webhook URL. */
    public class SlackSettings {
        /** @description The current user is an admin (the card is shown only to admins). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description Slack is on. */
        @AuraEnabled public Boolean enabled = false;
        /** @description The selected events. */
        @AuraEnabled public List<String> events = new List<String>();
        /** @description Every event that can be selected. */
        @AuraEnabled public List<String> allEvents = RlySlack.EVENTS;
        /** @description Saved (ends ••••xxxx), or null when no URL is saved. */
        @AuraEnabled public String webhookHint;
        /** @description When the last message was sent. */
        @AuraEnabled public Datetime lastSent;
        /** @description What happened to it. */
        @AuraEnabled public String lastResult;
    }

    /** @description What the card saves. */
    public class SlackInput {
        /** @description Slack on or off. */
        public Boolean enabled;
        /** @description A new webhook URL, or blank to keep the saved one. */
        public String webhookUrl;
        /** @description The selected events. */
        public List<String> events;
    }

    /**
     * @description The Slack settings for the card (empty for users who aren't admins).
     * @return the settings, without the webhook URL
     */
    @AuraEnabled
    public static SlackSettings getSlack() {
        SlackSettings out = new SlackSettings();
        out.isAdmin = RlyOrgController.isAdmin();
        RLY_Notification__c s = out.isAdmin ? RlySlack.settings() : null;
        if (s != null) {
            out.enabled = s.Enabled__c;
            out.events = new List<String>(RlySlack.selected(s));
            out.webhookHint = String.isBlank(s.Webhook_URL__c) ? null : 'Saved (ends ••••' + s.Webhook_URL__c.trim().right(4) + ')';
            out.lastSent = s.Last_Sent__c;
            out.lastResult = s.Last_Result__c;
        }
        return out;
    }

    /**
     * @description Saves the Slack settings. A blank webhook URL keeps the saved one.
     * @param settingsJson a SlackInput as JSON
     * @return the settings as saved
     */
    @AuraEnabled
    public static SlackSettings saveSlack(String settingsJson) {
        requireAdmin();
        SlackInput input = readInput(settingsJson);
        RLY_Notification__c saved = RlySlack.settings();
        RLY_Notification__c row = new RLY_Notification__c(Id = saved == null ? null : saved.Id, Name = 'Slack',
            Channel__c = RlySlack.CHANNEL, Enabled__c = input.enabled == true, Events__c = RlySlackRules.events(input.events));
        String url = RlySlackRules.webhook(input.webhookUrl);
        if (url != null) {
            row.Webhook_URL__c = url;
        } else if (row.Enabled__c && (saved == null || String.isBlank(saved.Webhook_URL__c))) {
            throw auraError('Paste the Slack webhook URL to turn Slack on.');
        }
        RlySlack.saveSettings(row);
        return getSlack();
    }

    /**
     * @description Sends "Release Relay test message from <hub>" to the saved webhook and records the result.
     * @return the settings, with the result
     */
    @AuraEnabled
    public static SlackSettings sendSlackTest() {
        requireAdmin();
        if (RlySlack.settings() == null) {
            throw auraError('Save the Slack settings first.');
        }
        RlySlack.sendText('Release Relay test message from ' + URL.getOrgDomainUrl().toExternalForm());
        RlySlack.saveResults();
        return getSlack();
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
            throw auraError('Changing notifications needs the Release Relay Admin permission set.');
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
