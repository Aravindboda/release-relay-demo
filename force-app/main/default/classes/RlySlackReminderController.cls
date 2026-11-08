/**
 * @description The Pipeline tab's per-org Slack reminder settings (LWC rlySlackOrgReminders, in the org window's Slack
 * section): reminders on/off and their hours, the daily digest on/off and its hour, mentions on/off and hotfix alerts
 * on/off. Anyone with the Pipeline tab reads them; only Release Relay Admins save them.
 */
public with sharing class RlySlackReminderController {

    /** @description One org's Slack reminder settings. */
    public class Settings {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String orgName;
        /** @description Its Slack channel, or null. */
        @AuraEnabled public String channel;
        /** @description Slack is on for the hub (Pipeline tab, Slack card). */
        @AuraEnabled public Boolean slackOn;
        /** @description Reminders on. */
        @AuraEnabled public Boolean reminders;
        /** @description Hours before (and between) reminders. */
        @AuraEnabled public Integer hours;
        /** @description Daily digest on. */
        @AuraEnabled public Boolean digest;
        /** @description The digest's hour (0 to 23). */
        @AuraEnabled public Integer digestHour;
        /** @description Mentions on. */
        @AuraEnabled public Boolean mentions;
        /** @description Hotfix alerts on. */
        @AuraEnabled public Boolean hotfixAlerts;
        /** @description The hub's time zone (digest hour and quiet hours). */
        @AuraEnabled public String timeZone;
        /** @description The viewer can edit. */
        @AuraEnabled public Boolean canEdit;
    }

    /** @description What the page saves. */
    public class Input {
        /** @description Reminders on. */
        public Boolean reminders;
        /** @description Hours (1 to 72). */
        public Integer hours;
        /** @description Digest on. */
        public Boolean digest;
        /** @description Digest hour (0 to 23). */
        public Integer digestHour;
        /** @description Mentions on. */
        public Boolean mentions;
        /** @description Hotfix alerts on. */
        public Boolean hotfixAlerts;
    }

    /**
     * @description An org's settings.
     * @param orgId the org
     * @return the settings
     */
    @AuraEnabled
    public static Settings orgSettings(Id orgId) {
        try {
            return view(requireOrg(orgId));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Saves an org's settings (Release Relay Admin).
     * @param orgId the org
     * @param inputJson the settings (Input)
     * @return the settings as saved
     */
    @AuraEnabled
    public static Settings saveOrgSettings(Id orgId, String inputJson) {
        try {
            RlyReleaseAccess.requireAdmin('Only Release Relay Admins can change Slack reminders.');
            RLY_Org__c org = requireOrg(orgId);
            Input input = String.isBlank(inputJson) ? null : (Input) JSON.deserialize(inputJson, Input.class);
            RlySlackDueStore.saveSettings(rowOf(org.Id, input));
            return view(RlySlackDueStore.org(org.Id));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description The row to save, checked: hours 1 to 72, digest hour 0 to 23.
     * @param orgId the org
     * @param input the settings
     * @return the row
     */
    public static RLY_Org__c rowOf(Id orgId, Input input) {
        if (input == null) {
            throw new RlyReleaseException('Nothing to save.');
        }
        if (outside(input.hours, 1, 72)) {
            throw new RlyReleaseException('Reminders wait 1 to 72 hours.');
        }
        if (outside(input.digestHour, 0, 23)) {
            throw new RlyReleaseException('The digest hour is 0 to 23.');
        }
        return new RLY_Org__c(Id = orgId, Slack_Reminders__c = input.reminders == true, Slack_Reminder_Hours__c = input.hours,
            Slack_Digest__c = input.digest == true, Slack_Digest_Hour__c = input.digestHour, Slack_Mentions__c = input.mentions == true,
            Slack_Hotfix_Alerts__c = input.hotfixAlerts != false);
    }

    // A blank value is fine (the default applies); otherwise it must be within lowest..highest.
    private static Boolean outside(Integer value, Integer lowest, Integer highest) {
        return value != null && (value < lowest || value > highest);
    }

    private static RLY_Org__c requireOrg(Id orgId) {
        RLY_Org__c org = RlySlackDueStore.org(orgId);
        if (org == null) {
            throw new RlyReleaseException('That org isn\'t registered.');
        }
        return org;
    }

    private static Settings view(RLY_Org__c o) {
        Settings x = new Settings();
        x.orgId = o.Id;
        x.orgName = o.Name;
        x.channel = o.Slack_Channel__c;
        x.slackOn = RlySlack.isOn();
        x.reminders = o.Slack_Reminders__c == true;
        x.hours = RlySlackNudge.hoursOf(o);
        x.digest = o.Slack_Digest__c == true;
        x.digestHour = RlySlackNudge.digestHourOf(o);
        x.mentions = o.Slack_Mentions__c == true;
        x.hotfixAlerts = o.Slack_Hotfix_Alerts__c != false;
        x.timeZone = RlySlackDueReads.hubTimeZone().getID();
        x.canEdit = RlyOrgController.isAdmin();
        return x;
    }
}
