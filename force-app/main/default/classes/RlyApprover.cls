/**
 * @description Who approves or rejects a release, and where: the current user on the release page, a linked Slack
 * user (Approve or Reject on the Slack card), or the Git provider's own reviewers. Also the values of
 * RLY_Org__c.Approval_In__c (where releases into an org are approved).
 */
public with sharing class RlyApprover {

    /** @description Approved in Salesforce: the release page or the Approvals tab. */
    public static final String VIA_RELAY = 'Salesforce';
    /** @description Approved or rejected from the Slack card. */
    public static final String VIA_SLACK = 'Slack';
    /** @description Approval_In__c: approved in Salesforce (the default; blank means this too). */
    public static final String IN_SALESFORCE = 'Salesforce';
    /** @description Approval_In__c: approved from the Slack card. */
    public static final String IN_SLACK = 'Slack';
    /** @description Approval_In__c: approved by the Git provider's reviewers. */
    public static final String IN_GIT = 'Git';

    /** @description The user, or null for GitHub. */
    public Id userId;
    /** @description The user's name, or null. */
    public String name;
    /** @description Release Relay, Slack or the Git provider's name. */
    public String via;
    /** @description The comment, or null. */
    public String comment;

    /**
     * @description The current user on the release page.
     * @param comment the comment, or null
     * @return the approver
     */
    public static RlyApprover currentUser(String comment) {
        RlyApprover a = new RlyApprover();
        a.userId = UserInfo.getUserId();
        a.name = UserInfo.getName();
        a.via = VIA_RELAY;
        a.comment = comment;
        return a;
    }

    /**
     * @description A Release Relay user acting from the Slack card.
     * @param u the linked user, with Name
     * @param comment the comment, or null
     * @return the approver
     */
    public static RlyApprover slackUser(User u, String comment) {
        RlyApprover a = new RlyApprover();
        a.userId = u.Id;
        a.name = u.Name;
        a.via = VIA_SLACK;
        a.comment = comment;
        return a;
    }

    /**
     * @description The Git provider: the merge run waits for the provider's own reviewers.
     * @param providerLabel the provider's name (RlyGit.providerLabel)
     * @return the approver, with no user
     */
    public static RlyApprover gitProvider(String providerLabel) {
        RlyApprover a = new RlyApprover();
        a.via = providerLabel;
        return a;
    }

    /**
     * @description Whether releases into an org can be approved in Salesforce. Always true when Slack approval isn't
     * available, so every org can be approved somewhere.
     * @param org the target org (or null)
     * @return true when Salesforce approval is on
     */
    public static Boolean inSalesforce(RLY_Org__c org) {
        if (org == null || !inSlack(org)) {
            return true;
        }
        return usesToggles(org) ? org.Approve_In_Salesforce__c == true : org.Approval_In__c != IN_SLACK;
    }

    /**
     * @description Whether releases into an org can be approved from their Slack card (and Slack is on).
     * @param org the target org (or null)
     * @return true when Slack approval is on
     */
    public static Boolean inSlack(RLY_Org__c org) {
        if (org == null || !RlySlack.isOn()) {
            return false;
        }
        return usesToggles(org) ? org.Approve_In_Slack__c == true : org.Approval_In__c == IN_SLACK;
    }

    /**
     * @description Whether the deploy into an org also waits for the Git provider's environment reviewers.
     * @param org the target org (or null)
     * @return true when Git review is required
     */
    public static Boolean gitReview(RLY_Org__c org) {
        if (org == null) {
            return false;
        }
        return org.Require_Git_Review__c == true || org.Approval_In__c == IN_GIT;
    }

    /**
     * @description Where releases into an org are approved, in words: Salesforce, Slack, or Salesforce or Slack.
     * @param org the target org (or null)
     * @return the places, for the release page
     */
    public static String approvalIn(RLY_Org__c org) {
        List<String> places = new List<String>();
        if (inSalesforce(org)) {
            places.add(IN_SALESFORCE);
        }
        if (inSlack(org)) {
            places.add(IN_SLACK);
        }
        String text = String.join(places, ' or ');
        return gitReview(org) ? text + ', then ' + RlyGitName.reviewers() + ' reviewers' : text;
    }

    /**
     * @description Refuses a Salesforce approval for a release into an org approved only from Slack.
     * @param rel the release (or null)
     */
    public static void requireSalesforce(RLY_Release__c rel) {
        if (rel != null && !inSalesforce(rel.Target_Org__r)) {
            throw new RlyReleaseException('Releases into ' + rel.Target_Org__r.Name + ' are approved from their Slack card.');
        }
    }

    // Rows saved since the toggles came use them; older rows (no toggle switched from its default) use Approval_In__c.
    private static Boolean usesToggles(RLY_Org__c org) {
        return String.isBlank(org.Approval_In__c) || org.Approve_In_Slack__c == true || org.Approve_In_Salesforce__c != true;
    }
}
