/**
 * @description Slack messages sent the moment a release changes, from RlySlackCardSync / RlySlackDelivery (before the
 * release is saved: callouts only):
 *   hotfix    "Hotfix in progress" in the target org's channel when a hotfix is raised, even with reminders off and
 *             whatever events are selected (the org's Slack_Hotfix_Alerts__c, on by default)
 *   mentions  tags for the thread reply when the target org has Slack_Mentions__c on: the developer when checks fail,
 *             the approvers when the release is ready for approval (linked Slack users only)
 * Never throws: a failure is kept for the Slack record's last result.
 */
public with sharing class RlySlackAlert {

    private static final Set<String> APPROVER_SETS = new Set<String>{ 'RLY_Approver', 'RLY_Admin' };

    /**
     * @description Posts the hotfix alert when this change is a hotfix being raised.
     * @param s the Slack record (on)
     * @param rel the release, as RlyReleaseStore reads it, with its new status
     * @param event the change's event (RlySlack.eventFor)
     * @return whether an alert went out
     */
    public static Boolean hotfix(RLY_Notification__c s, RLY_Release__c rel, String event) {
        if (event != 'Raised' || rel.Is_Hotfix__c != true || rel.Target_Org__c == null) {
            return false;
        }
        RLY_Org__c org = RlySlackDueStore.org(rel.Target_Org__c);
        if (org == null || org.Slack_Hotfix_Alerts__c != true || String.isBlank(org.Slack_Channel__c)) {
            return false;
        }
        String result;
        Boolean sent = false;
        try {
            String who = RlySlackNudge.mentions(RlySlackDueReads.memberIds(new Set<Id>{ rel.CreatedById }).values());
            RlySlackApi.call('chat.postMessage', new Map<String, Object>{ 'channel' => org.Slack_Channel__c.trim(),
                'text' => RlySlackNudge.hotfix(rel, who) });
            result = 'Sent: ' + rel.Name + ' · hotfix alert';
            sent = true;
        } catch (Exception e) {
            result = RlySlackApi.isRateLimited(e) ? RlySlack.busyResult(rel) : 'Failed: ' + rel.Name + ' · hotfix alert: ' + e.getMessage();
        }
        RlySlack.record(s.Id, result);
        return sent;
    }

    /**
     * @description The mentions to add to an event's thread reply, or "" (mentions off, or nobody linked).
     * @param rel the release
     * @param event the event
     * @return the mentions, with a leading space, or ""
     */
    public static String mentionsFor(RLY_Release__c rel, String event) {
        if (event != 'Checks failed' && event != 'Ready for approval') {
            return '';
        }
        try {
            RLY_Org__c org = RlySlackDueStore.org(rel.Target_Org__c);
            if (org == null || org.Slack_Mentions__c != true) {
                return '';
            }
            Set<Id> people = event == 'Checks failed' ? new Set<Id>{ rel.CreatedById } : RlySlackDueReads.holders(APPROVER_SETS);
            return RlySlackNudge.mentions(RlySlackDueReads.memberIds(people).values());
        } catch (Exception e) {
            return ''; // mentions are a nicety: the reply goes out without them
        }
    }
}
