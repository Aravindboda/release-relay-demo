/**
 * @description The words of Slack reminders, the daily digest, mentions and hotfix alerts (RlySlackDue, RlySlackAlert).
 * Text only, no callouts or DML: Slack mrkdwn with names escaped; a mention is <@member id>.
 */
public with sharing class RlySlackNudge {

    /** @description Hours a release waits before a reminder when the org sets none. */
    public static final Integer DEFAULT_HOURS = 4;
    /** @description The digest hour when the org sets none. */
    public static final Integer DEFAULT_DIGEST_HOUR = 8;

    /**
     * @description The org's reminder period in hours (1 to 72; DEFAULT_HOURS when blank).
     * @param org the org
     * @return the hours
     */
    public static Integer hoursOf(RLY_Org__c org) {
        Integer h = org == null || org.Slack_Reminder_Hours__c == null ? DEFAULT_HOURS : org.Slack_Reminder_Hours__c.intValue();
        return Math.min(Math.max(h, 1), 72);
    }

    /**
     * @description The org's digest hour (0 to 23; DEFAULT_DIGEST_HOUR when blank).
     * @param org the org
     * @return the hour
     */
    public static Integer digestHourOf(RLY_Org__c org) {
        Integer h = org == null || org.Slack_Digest_Hour__c == null ? DEFAULT_DIGEST_HOUR : org.Slack_Digest_Hour__c.intValue();
        return Math.min(Math.max(h, 0), 23);
    }

    /**
     * @description Mentions for Slack members: " <@U1> <@U2>", or "" for none.
     * @param memberIds the Slack member ids
     * @return the text
     */
    public static String mentions(List<String> memberIds) {
        List<String> parts = new List<String>();
        for (String m : memberIds) {
            if (String.isNotBlank(m) && parts.size() < RlySlackDueStore.MAX_MENTIONS) {
                parts.add('<@' + m.trim() + '>');
            }
        }
        return parts.isEmpty() ? '' : ' ' + String.join(parts, ' ');
    }

    /** @description How long a release has waited, and for whom. */
    public class Wait {
        /** @description Hours waited. */
        public Integer hours = 0;
        /** @description Manual steps still to do in its target org (deployed releases). */
        public Integer steps = 0;
        /** @description The mentions (see mentions), or "". */
        public String who = '';
    }

    /**
     * @description A reminder for a release waiting for approval or for its manual steps.
     * @param rel the release
     * @param w how long it has waited, its steps to do and the mentions
     * @return the text
     */
    public static String reminder(RLY_Release__c rel, Wait w) {
        Integer hoursWaited = w.hours;
        Integer stepsToDo = w.steps;
        String who = w.who;
        String org = RlySlackMessage.esc(rel.Target_Org__r == null ? '' : rel.Target_Org__r.Name);
        String waited = hoursWaited + ' hour' + (hoursWaited == 1 ? '' : 's');
        if (rel.Status__c == RlySlackDueStore.DEPLOYED) {
            return ':alarm_clock: ' + rel.Name + ' was deployed to ' + org + ' ' + waited + ' ago and still has ' + stepsToDo
                + ' manual step' + (stepsToDo == 1 ? '' : 's') + ' to do.' + (String.isBlank(who) ? '' : who + ' (deploy team)')
                + ' <' + RlySlackMessage.link(rel) + '|Open in Release Relay>';
        }
        return ':alarm_clock: ' + rel.Name + ' has waited *' + waited + '* for approval into ' + org + '.'
            + (String.isBlank(who) ? '' : who + ' can approve.') + ' <' + RlySlackMessage.link(rel) + '|Open in Release Relay>';
    }

    /**
     * @description The hotfix alert.
     * @param rel the hotfix release (with Source_Org__r, Target_Org__r, CreatedBy)
     * @param who the developer's mention, or "" (then the name)
     * @return the text
     */
    public static String hotfix(RLY_Release__c rel, String who) {
        String source = RlySlackMessage.esc(rel.Source_Org__r == null ? '' : rel.Source_Org__r.Name);
        String target = RlySlackMessage.esc(rel.Target_Org__r == null ? '' : rel.Target_Org__r.Name);
        String raiser = String.isBlank(who) ? RlySlackMessage.esc(RlySlackCard.raisedBy(rel)) : who.trim();
        return ':rotating_light: *Hotfix in progress → ' + target + '*\n' + rel.Name + ' · ' + RlySlackMessage.esc(rel.Title__c)
            + ' · raised by ' + raiser + '\nReason: ' + RlySlackMessage.esc(String.isBlank(rel.Hotfix_Reason__c) ? 'not given' : rel.Hotfix_Reason__c.left(500))
            + '\nRoute: ' + source + ' → ' + target + ' (hotfix) · <' + RlySlackMessage.link(rel) + '|Open in Release Relay>';
    }

    /**
     * @description An org's daily digest, or null when there is nothing to say.
     * @param org the org
     * @param lines deployed, waiting, failed and steps (RlySlackDueStore.digest); a freeze coming is added from the org's
     * release window (Window_* fields)
     * @param day the day it is for
     * @return the text, or null
     */
    public static String digest(RLY_Org__c org, Map<String, List<RLY_Release__c>> lines, Date day) {
        List<String> out = new List<String>();
        addLine(out, ':white_check_mark: Deployed yesterday', lines.get('deployed'));
        addLine(out, ':hourglass_flowing_sand: Waiting for approval', lines.get('waiting'));
        addLine(out, ':clipboard: Manual steps to do', lines.get('steps'));
        addLine(out, ':x: Failed', lines.get('failed'));
        // A freeze on the org running now or starting within a week (its release window, build 39).
        String freeze = RlyWindowText.soon(org.Name, new RlyReleaseWindow(org), Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0)));
        if (freeze != null) {
            out.add(':snowflake: ' + freeze);
        }
        if (out.isEmpty()) {
            return null;
        }
        Datetime noon = Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
        return '*' + RlySlackMessage.esc(org.Name) + ' · daily digest · ' + noon.format('EEE d MMM') + '*\n' + String.join(out, '\n');
    }

    private static void addLine(List<String> out, String label, List<RLY_Release__c> rels) {
        if (rels == null || rels.isEmpty()) {
            return;
        }
        List<String> names = new List<String>();
        for (RLY_Release__c r : rels) {
            names.add(r.Name);
        }
        out.add(label + ': ' + String.join(names, ', '));
    }
}
