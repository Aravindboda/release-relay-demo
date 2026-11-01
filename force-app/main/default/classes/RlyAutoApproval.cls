/**
 * @description Approves a release by its target org's approval rule (RlyApprovalRules) at the point its checks pass, the
 * moment it would otherwise become 'Ready for approval' and wait for an approver. When the rule says no approver is
 * needed it records Approved_Via__c 'Rule', no approver and the comment "Approved automatically: <reason>", then starts
 * the deploy exactly as an approval does (RlyApprovalRuns.startMerge). The manual steps gate still applies: with manual
 * steps before deploy still to do, the approval is recorded and the deployment team's last check starts the deploy
 * (RlyManualStepCheck). Back promote syncs keep their own approval setting. Callouts only: the caller saves.
 */
public with sharing class RlyAutoApproval {

    private static final String READY = 'Ready for approval';

    /**
     * @description After an approver accepted a blocking scan's findings: approves by rule when that made the release
     * ready for approval and its target org needs no approver.
     * @param rel the release, as changed now
     * @param oldStatus its status before (Checks failed)
     * @return true when it was approved by rule
     */
    public static Boolean afterBypass(RLY_Release__c rel, String oldStatus) {
        return rel.Status__c == READY && afterChecks(rel, RlyGit.forConnection(RlyReleaseStore.git()), oldStatus);
    }

    /**
     * @description Approves the release by rule when its checks just passed and its target org needs no approver.
     * @param rel the release, as read now (with Target_Org__r's approval rule fields)
     * @param git the Git provider
     * @param oldStatus its status before this read
     * @return true when it was approved by rule
     */
    public static Boolean afterChecks(RLY_Release__c rel, RlyGit git, String oldStatus) {
        if (oldStatus == READY || rel.Status__c != READY || rel.Approval_Status__c == 'Approved'
            || RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE) {
            return false;
        }
        RlyApprovalRules.Decision d = RlyApprovalRules.decide(rel);
        if (d.needed) {
            return false;
        }
        RlyApprover byRule = new RlyApprover();
        byRule.via = RlyReleaseLog.VIA_RULE;
        byRule.name = RlyReleaseLog.VIA_RULE;
        byRule.comment = d.reason;
        if (RlyManualStepGate.blocks(rel)) {
            RlyApprovalRuns.recordApproval(rel, byRule);
        } else {
            RlyApprovalRuns.startMerge(rel, git, byRule);
        }
        return true;
    }
}
