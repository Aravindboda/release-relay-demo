/**
 * @description The two-approver rule (optional, per target org: RLY_Org__c.Hotfix_Two_Approvers__c): a hotfix into such
 * an org needs two different approvers, neither of them the person who raised it. The first approval is recorded
 * (Approved_By__c, Approved_On__c) and keeps the release waiting; the second starts the merge and goes to
 * Second_Approved_By__c / Second_Approved_On__c, while the first approver stays in Approved_By__c. Applies wherever a
 * release is approved (the release page, the Approvals tab, Slack).
 */
public with sharing class RlyTwoApprovers {

    /**
     * @description Whether the release needs two approvers.
     * @param rel the release, with Is_Hotfix__c and Target_Org__r.Hotfix_Two_Approvers__c
     * @return true for a hotfix into an org that needs two
     */
    public static Boolean needsTwo(RLY_Release__c rel) {
        return RlyHotfix.isHotfix(rel) && rel.Target_Org__r != null && rel.Target_Org__r.Hotfix_Two_Approvers__c == true;
    }

    /**
     * @description Whether the release has its first approval and waits for the second.
     * @param rel the release
     * @return true while it waits for a second approver
     */
    public static Boolean waitsForSecond(RLY_Release__c rel) {
        return needsTwo(rel) && rel.Status__c == 'Ready for approval' && rel.Approved_By__c != null && rel.Approval_Status__c == 'Pending';
    }

    /**
     * @description Checks the approver and, when this is the first of two approvals, records it.
     * @param rel the release (Ready for approval)
     * @param who who approves
     * @return true when this approval was only the first of two (the caller saves and stops)
     */
    public static Boolean recordsFirst(RLY_Release__c rel, RlyApprover who) {
        if (!needsTwo(rel)) {
            return false;
        }
        if (who.userId == null || who.userId == rel.CreatedById) {
            throw new RlyReleaseException('You raised this hotfix, so two other people approve it.');
        }
        if (!waitsForSecond(rel)) {
            rel.Approved_By__c = who.userId;
            rel.Approved_Via__c = who.via;
            rel.Approved_On__c = System.now();
            rel.Approval_Comment__c = who.comment == null ? null : who.comment.left(2000);
            return true;
        }
        if (who.userId == rel.Approved_By__c) {
            throw new RlyReleaseException('You already approved it. A second approver is needed.');
        }
        return false;
    }

    /**
     * @description After the second approval started the merge: the first approver stays in Approved_By__c and the second
     * goes to Second_Approved_By__c.
     * @param rel the release, as the merge left it
     * @param prior the release before this approval
     */
    public static void keepBoth(RLY_Release__c rel, RLY_Release__c prior) {
        if (!needsTwo(rel) || rel.Approval_Status__c != 'Approved' || prior.Approved_By__c == null) {
            return;
        }
        rel.Second_Approved_By__c = rel.Approved_By__c;
        rel.Second_Approved_On__c = rel.Approved_On__c;
        rel.Approved_By__c = prior.Approved_By__c;
        rel.Approved_On__c = prior.Approved_On__c;
        if (String.isBlank(rel.Approval_Comment__c)) {
            rel.Approval_Comment__c = prior.Approval_Comment__c;
        }
    }

    /**
     * @description The notice while it waits for a second approver.
     * @param rel the release, with Approved_By__r.Name
     * @return the notice, or null
     */
    public static String notice(RLY_Release__c rel) {
        if (!waitsForSecond(rel)) {
            return null;
        }
        String name = rel.Approved_By__r == null ? RlyReleaseStore.userName(rel.Approved_By__c) : rel.Approved_By__r.Name;
        return 'Approved by ' + name + '. Waiting for a second approver.';
    }
}
