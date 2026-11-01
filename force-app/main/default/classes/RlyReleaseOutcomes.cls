/**
 * @description The approval and outcome events of a save (RlyReleaseTransitions): first and second approval, approved
 * automatically by the target org's rule, rejected; deployed or back promoted, deploy failed, the branches merged
 * back, failed or closed.
 */
public with sharing class RlyReleaseOutcomes {

    /**
     * @description Adds the approval events between the saved and the new release.
     * @param old the release as it was
     * @param rel the release as saved now
     */
    public static void approvals(RLY_Release__c old, RLY_Release__c rel) {
        if (autoApproved(old, rel)) {
            return;
        }
        if (old.Approved_By__c == null && rel.Approved_By__c != null && rel.Status__c != 'Rejected') {
            firstApproval(rel);
        }
        if (old.Second_Approved_By__c == null && rel.Second_Approved_By__c != null) {
            approved(rel, rel.Second_Approved_By__c, 'Second approval');
        }
        if (old.Status__c != 'Rejected' && rel.Status__c == 'Rejected') {
            RlyReleaseLog.add(rel, 'Rejected', 'Rejected' + RlyEvidenceText.comment(rel.Approval_Comment__c))
                .inOrg(rel.Target_Org__c).byActor(rel.Approved_By__c, RlyReleaseTransitions.viaOf(rel.Approved_Via__c));
        }
    }

    // Approved by the target org's rule just now: the Auto_Approved event.
    private static Boolean autoApproved(RLY_Release__c old, RLY_Release__c rel) {
        Boolean now = old.Approval_Status__c != 'Approved' && rel.Approval_Status__c == 'Approved';
        if (!now || rel.Approved_Via__c != RlyReleaseLog.VIA_RULE) {
            return false;
        }
        RlyReleaseLog.add(rel, 'Auto_Approved', RlyEvidenceText.text(rel.Approval_Comment__c))
            .inOrg(rel.Target_Org__c).byActor(null, RlyReleaseLog.VIA_RULE);
        return true;
    }

    private static void firstApproval(RLY_Release__c rel) {
        Boolean done = rel.Approval_Status__c == 'Approved';
        approved(rel, rel.Approved_By__c, (done ? 'Approved' : 'First approval') + RlyEvidenceText.comment(rel.Approval_Comment__c)
            + (done ? '' : '. Waiting for a second approver'));
    }

    private static void approved(RLY_Release__c rel, Id who, String detail) {
        RlyReleaseLog.add(rel, 'Approved', detail).inOrg(rel.Target_Org__c).byActor(who, RlyReleaseTransitions.viaOf(rel.Approved_Via__c));
    }

    /**
     * @description Adds the outcome events: the branches merged back, then deployed, deploy failed, failed or closed.
     * @param old the release as it was
     * @param rel the release as saved now
     */
    public static void outcome(RLY_Release__c old, RLY_Release__c rel) {
        if (old.Back_Merge_Result__c != rel.Back_Merge_Result__c && String.isNotBlank(rel.Back_Merge_Result__c)) {
            RlyReleaseLog.add(rel, 'Merged_Back', 'Branches brought up to date: ' + RlyEvidenceText.backMergeCounts(rel.Back_Merge_Result__c));
        }
        if (old.Status__c == rel.Status__c) {
            return;
        }
        Boolean sync = RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE;
        if (rel.Status__c == 'Deployed') {
            deployed(rel, sync);
        } else if (rel.Status__c == 'Deploy failed' || (sync && rel.Status__c == 'Failed')) {
            RlyEvidenceText.Deploy d = RlyEvidenceText.deployOf(rel.Deploy_Result__c);
            RlyReleaseLog.add(rel, 'Deploy_Failed', 'Deploy to ' + RlyReleaseTransitions.targetName(rel) + ' failed: '
                + RlyEvidenceText.text(rel.Error_Message__c)).inOrg(rel.Target_Org__c).withReference(d.deployId);
        } else {
            ended(rel);
        }
    }

    private static void deployed(RLY_Release__c rel, Boolean sync) {
        RlyEvidenceText.Deploy d = RlyEvidenceText.deployOf(rel.Deploy_Result__c);
        RlyReleaseLog.add(rel, sync ? 'Back_Promoted' : 'Deployed', (sync ? 'Back promoted to ' : 'Deployed to ')
            + RlyReleaseTransitions.targetName(rel) + d.suffix()).inOrg(rel.Target_Org__c).withReference(d.deployId);
    }

    private static void ended(RLY_Release__c rel) {
        if (rel.Status__c == 'Closed') {
            RlyReleaseLog.add(rel, 'Comment', 'Closed: the pull request was closed without merging');
        } else if (rel.Status__c == 'Failed') {
            RlyReleaseLog.add(rel, 'Comment', 'Failed: ' + RlyEvidenceText.text(rel.Error_Message__c));
        }
    }
}
