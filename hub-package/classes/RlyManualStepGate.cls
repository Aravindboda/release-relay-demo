/**
 * @description The deploy gate of manual steps (RlyManualSteps): a deploy into an org doesn't start while a Before deploy
 * run of that deploy (the release and its target org) is still to do. An approval then is recorded and the release keeps
 * waiting (Status Ready for approval, Approval_Status__c Approved); a queued back promote sync stays queued. When the
 * deployment team checks off the last one, the deploy starts (RlyManualStepCheck). Also the counts the release page,
 * the release lists and the Slack card show (in words: RlyManualStepText).
 */
public with sharing class RlyManualStepGate {

    private static final String READY = 'Ready for approval';

    /**
     * @description How many Before deploy runs of the release's deploy into its target are still to do.
     * @param rel the release, with Target_Org__c
     * @return the number
     */
    public static Integer beforeOpen(RLY_Release__c rel) {
        return rel == null || rel.Id == null ? 0 : RlyManualStepStore.openBefore(rel.Id, rel.Target_Org__c, null);
    }

    /**
     * @description Whether the deploy into the release's target waits for manual steps.
     * @param rel the release
     * @return true while a Before deploy run is still to do
     */
    public static Boolean blocks(RLY_Release__c rel) {
        return beforeOpen(rel) > 0;
    }

    /**
     * @description Whether the release was approved (or queued, for a back promote sync) and its deploy waits for the
     * deployment team, or would start once they finish.
     * @param rel the release
     * @return true when it is approved and waiting, or a queued sync
     */
    public static Boolean isWaiting(RLY_Release__c rel) {
        if (RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE && rel.Status__c == RlyPromotion.QUEUED) {
            return true;
        }
        return rel.Status__c == READY && rel.Approval_Status__c == 'Approved';
    }

    /**
     * @description Before an approval starts the merge: refuses another approval of a release that is approved and still
     * waits for manual steps; records the first of two approvals (RlyTwoApprovers); and, when the deploy waits for manual
     * steps, records the approval (the release keeps waiting; with two approvers the first stays in Approved_By__c).
     * @param rel the release (Ready for approval)
     * @param who who approves
     * @return true when the release keeps waiting (the caller saves and stops)
     */
    public static Boolean waitsInstead(RLY_Release__c rel, RlyApprover who) {
        Boolean approved = rel.Approval_Status__c == 'Approved';
        String waiting = approved ? notice(rel) : null;
        if (waiting != null) {
            throw new RlyReleaseException(waiting);
        }
        if (!approved && RlyTwoApprovers.recordsFirst(rel, who)) {
            return true;
        }
        if (!blocks(rel)) {
            return false;
        }
        RLY_Release__c prior = rel.clone(true, true, true, true);
        RlyApprovalRuns.recordApproval(rel, who);
        RlyTwoApprovers.keepBoth(rel, prior);
        return true;
    }

    /**
     * @description The notice while the deploy waits for manual steps.
     * @param rel the release
     * @return "Approved. Deploys when the deployment team finishes 2 manual steps before deploy." (a queued sync: "Deploys
     * when ..."), or null
     */
    public static String notice(RLY_Release__c rel) {
        if (rel == null || !isWaiting(rel)) {
            return null;
        }
        Integer n = beforeOpen(rel);
        if (n == 0) {
            return null;
        }
        String text = 'Deploys when the deployment team finishes ' + RlyManualSteps.stepWords(n) + ' before deploy.';
        return rel.Status__c == READY ? 'Approved. ' + text : text;
    }

    /**
     * @description The runs of the release's deploy into its target, counted.
     * @param rel the release
     * @return the counts
     */
    public static RlyManualSteps.Counts counts(RLY_Release__c rel) {
        RlyManualSteps.Counts c = new RlyManualSteps.Counts();
        if (rel == null || rel.Id == null) {
            return c;
        }
        for (RLY_Manual_Step_Run__c r : RlyManualStepStore.runsOfReleases(new Set<Id>{ rel.Id })) {
            Integer open = r.Status__c == RlyManualSteps.STATUS_TO_DO ? 1 : 0;
            if (r.Step__r != null && r.Step__r.Timing__c == RlyManualSteps.TIMING_BEFORE) {
                c.beforeCount++;
                c.beforeOpen += open;
            } else {
                c.afterCount++;
                c.afterOpen += open;
            }
        }
        return c;
    }
}
