/**
 * @description The on-the-spot match when an unlinked person presses Approve or Reject in Slack: users.info gives their
 * Slack email; exactly one active user with that Federation ID (SSO) or Salesforce email (Email), who is an approver and
 * has no link yet, is the match, linked with Linked by SSO or Email. The lookup is a callout: the link is saved by
 * saveFound after the press's other callouts (Salesforce refuses a callout after uncommitted DML). Manual mode skips it.
 */
public with sharing class RlySlackPresser {

    /** @description The approver found (Name, Id, member ID set), or null. */
    public User approver;
    /** @description The link to save once the callouts are done, or null. */
    public User toSave;
    /** @description The person is a Salesforce user who isn't an approver. */
    public Boolean notApprover = false;

    /**
     * @description Matches a Slack user who pressed a button. Never throws.
     * @param memberId the Slack user who pressed
     * @return the result (approver null when there is no match)
     */
    public static RlySlackPresser find(String memberId) {
        RlySlackPresser out = new RlySlackPresser();
        try {
            if (RlySlackDirectory.linkedUser(memberId) != null) {
                out.notApprover = true; // linked, yet approverFor found nobody: not an approver
                return out;
            }
            String how = RlySlackMatch.matchBy();
            RlySlackPeople.Person p = how == RlySlackMatch.MANUAL || String.isBlank(memberId) ? null
                : RlySlackPeople.byId(memberId.trim().toUpperCase());
            List<User> users = p == null ? new List<User>() : RlySlackDirectory.usersWith(p.email, how);
            if (users.size() == 1) {
                out.take(users[0], p.memberId, how);
            }
        } catch (Exception e) {
            return out;
        }
        return out;
    }

    private void take(User u, String memberId, String how) {
        if (RlySlackDirectory.accessOf(u.Id) == null) {
            notApprover = true;
        } else if (String.isBlank(u.RLY_Slack_Member_Id__c)) {
            u.RLY_Slack_Member_Id__c = memberId;
            approver = u;
            toSave = RlySlackDirectory.linkRow(u.Id, memberId, how);
        }
    }

    /**
     * @description Saves the link a match found. Never throws.
     * @param p the match, or null
     */
    public static void saveFound(RlySlackPresser p) {
        if (p != null && p.toSave != null) {
            RlySlackDirectory.save(new List<User>{ p.toSave });
        }
    }
}
