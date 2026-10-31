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
     * @description Where releases into an org are approved.
     * @param org the target org, with Approval_In__c (or null)
     * @return Salesforce, Slack or Git; blank is Salesforce, and so is Slack while Slack is off
     */
    public static String approvalIn(RLY_Org__c org) {
        String value = org == null || String.isBlank(org.Approval_In__c) ? IN_SALESFORCE : org.Approval_In__c;
        return value == IN_SLACK && !RlySlack.isOn() ? IN_SALESFORCE : value;
    }
}
