/**
 * @description The Slack items of the Home tab's health line (RlyHomeHealth), from saved records only (no callouts).
 * Slack: RLY_Notification__c Enabled__c and Last_Result__c, as RlySetupStatus reads them. Approve in Slack, only when
 * Slack is on and an org on the route is approved from its Slack card (RlyApprover.inSlack): the signing secret is saved
 * (checked for a value only), the Site Slack posts to is found (RlySlackDirectory.actionsUrl) and every approver is linked
 * to a Slack member (RlySlackDirectory.approvers). Reads go through those classes; this class holds no queries.
 */
public with sharing class RlyHomeSlackHealth {

    private static final String SLACK_SENT = 'Sent';

    /**
     * @description The Slack item.
     * @param slack the Slack record, or null
     * @return the item
     */
    public static RlyHomeHealth.Item slackItem(RLY_Notification__c slack) {
        RlyHomeHealth.Item i = RlyHomeHealth.item('slack', 'Slack');
        if (slack == null || !slack.Enabled__c) {
            return RlyHomeHealth.withState(i, 'Off', RlyHomeHealth.TONE_NONE);
        }
        if (String.isBlank(slack.Last_Result__c)) {
            return RlyHomeHealth.withState(i, 'Not tested', RlyHomeHealth.TONE_WAIT);
        }
        i.title = slack.Last_Result__c;
        return slack.Last_Result__c.startsWith(SLACK_SENT) ? RlyHomeHealth.withState(i, 'Connected', RlyHomeHealth.TONE_OK)
            : RlyHomeHealth.withState(i, 'Last message failed', RlyHomeHealth.TONE_BAD);
    }

    /**
     * @description The Approve in Slack item, when Slack is on and an org on the route is approved from its Slack card.
     * @param slack the Slack record (with Signing_Secret__c), or null
     * @param orgs the stages and the hub, with their approval fields
     * @return the item, or null when no org is approved in Slack
     */
    public static RlyHomeHealth.Item approveItem(RLY_Notification__c slack, List<RLY_Org__c> orgs) {
        if (slack == null || !slack.Enabled__c) {
            return null;
        }
        List<String> names = slackOrgs(orgs);
        if (names.isEmpty()) {
            return null;
        }
        RlyHomeHealth.Item i = RlyHomeHealth.item('approve', 'Approve in Slack');
        i.title = 'Releases into ' + String.join(names, ', ') + ' are approved from their Slack card.';
        if (String.isBlank(slack.Signing_Secret__c)) {
            return RlyHomeHealth.withState(i, 'signing secret not saved', RlyHomeHealth.TONE_BAD);
        }
        if (RlySlackDirectory.actionsUrl() == null) {
            return RlyHomeHealth.withState(i, 'Site not set up', RlyHomeHealth.TONE_BAD);
        }
        return linkState(i, unlinkedApprovers());
    }

    /**
     * @description Ready when every approver is linked to Slack, else how many aren't.
     * @param i the item
     * @param unlinked approvers without a Slack member ID
     * @return the item with its state
     */
    @TestVisible
    private static RlyHomeHealth.Item linkState(RlyHomeHealth.Item i, Integer unlinked) {
        if (unlinked == 0) {
            return RlyHomeHealth.withState(i, 'Ready', RlyHomeHealth.TONE_OK);
        }
        return RlyHomeHealth.withState(i, unlinked + (unlinked == 1 ? ' approver' : ' approvers') + ' not linked',
            RlyHomeHealth.TONE_WAIT);
    }

    private static Integer unlinkedApprovers() {
        Integer unlinked = 0;
        for (User u : RlySlackDirectory.approvers()) {
            unlinked += String.isBlank(u.RLY_Slack_Member_Id__c) ? 1 : 0;
        }
        return unlinked;
    }

    private static List<String> slackOrgs(List<RLY_Org__c> orgs) {
        List<String> names = new List<String>();
        for (RLY_Org__c o : orgs) {
            if (RlyApprover.inSlack(o)) {
                names.add(o.Name);
            }
        }
        return names;
    }
}
