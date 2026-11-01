/**
 * @description Releases with only manual steps (Manual_Only__c): a change done by hand (for example profile access) that
 * still has to be tracked, approved and done in order in every org. They carry no metadata, so there is no retrieve, Git
 * branch, pull request, pipeline run, code scan or validation ("Not needed: manual steps only").
 *
 * Status flow: raised (or promoted) Submitted → on the next read of its page Ready for approval (the target org's approval
 * rule decides: RlyAutoApproval; the hub always needs an approver) → once approved and the manual steps before deploy are
 * done, Deploying while its manual-step runs in that org are still to do → Deployed when every one of them is Done or Not
 * needed (the deployment team checks them off: RlyManualStepCheck; the page's reads finish it too). No callouts.
 */
public with sharing class RlyManualOnly {

    /** @description What the release page, Slack card and evidence say instead of the Git and pipeline steps. */
    public static final String NOT_NEEDED = 'Not needed: manual steps only';
    /** @description The pill. */
    public static final String PILL = 'Manual steps only';

    private static final String READY = 'Ready for approval';
    private static final String DEPLOYING = 'Deploying';
    private static final String DEPLOYED = 'Deployed';
    private static final String NOT_CONFIGURED = 'Not configured';

    /**
     * @description Whether a release has only manual steps. A release read without the field counts as not.
     * @param rel the release, or null
     * @return true for a manual-steps-only release
     */
    public static Boolean isManualOnly(RLY_Release__c rel) {
        return rel != null && rel.isSet('Manual_Only__c') && rel.Manual_Only__c == true;
    }

    /**
     * @description Marks a new release (or promotion) as manual steps only: queued, with nothing to scan or validate.
     * @param rel the release, not saved yet
     */
    public static void mark(RLY_Release__c rel) {
        rel.Manual_Only__c = true;
        rel.Status__c = RlyPromotion.QUEUED;
        rel.Scan_Status__c = NOT_CONFIGURED;
        rel.Validation_Status__c = NOT_CONFIGURED;
        rel.Component_Count__c = 0;
        rel.Deletion_Count__c = 0;
    }

    /**
     * @description Whether every carried release has only manual steps (the promotion then has only manual steps too).
     * @param carried the carried releases, with Manual_Only__c
     * @return true when none of them has a merge commit to carry
     */
    public static Boolean allManualOnly(List<RLY_Release__c> carried) {
        if (carried == null || carried.isEmpty()) {
            return false;
        }
        for (RLY_Release__c r : carried) {
            if (!isManualOnly(r)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @description On a read of its page: a queued release goes to its approval point (Ready for approval; the caller
     * applies the approval rule); a deploying one is Deployed when its manual steps in the target are done.
     * @param rel the release (manual steps only)
     */
    public static void advance(RLY_Release__c rel) {
        if (rel.Status__c == RlyPromotion.QUEUED) {
            rel.Status__c = READY;
            rel.Error_Message__c = null;
        } else if (rel.Status__c == DEPLOYING) {
            finishIfDone(rel, null);
        }
    }

    /**
     * @description Starts the "deploy" of an approved release whose manual steps before deploy are done: Deploying, and
     * Deployed at once when none of its manual steps in the target is still to do.
     * @param rel the release (manual steps only)
     */
    public static void startDeploy(RLY_Release__c rel) {
        rel.Status__c = DEPLOYING;
        rel.Deploy_Status__c = DEPLOYING;
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
        finishIfDone(rel, null);
    }

    /**
     * @description Deployed, when the release has only manual steps, is deploying and none of its runs in the target is
     * still to do.
     * @param rel the release
     * @param skipRunId a run just checked off and not saved yet (not counted), or null
     * @return true when it is Deployed now
     */
    public static Boolean finishIfDone(RLY_Release__c rel, Id skipRunId) {
        if (!isManualOnly(rel) || rel.Status__c != DEPLOYING || openRuns(rel, skipRunId) > 0) {
            return false;
        }
        rel.Status__c = DEPLOYED;
        rel.Deploy_Status__c = DEPLOYED;
        rel.Error_Message__c = null;
        return true;
    }

    /**
     * @description How many of the release's manual-step runs in its target org are still to do.
     * @param rel the release, with Id and Target_Org__c
     * @param skipRunId a run not to count, or null
     * @return the number
     */
    public static Integer openRuns(RLY_Release__c rel, Id skipRunId) {
        Integer n = 0;
        for (RLY_Manual_Step_Run__c r : RlyManualStepStore.runsOfReleases(new Set<Id>{ rel.Id })) {
            if (r.Org__c == rel.Target_Org__c && r.Id != skipRunId && r.Status__c == RlyManualSteps.STATUS_TO_DO) {
                n++;
            }
        }
        return n;
    }

    /**
     * @description The release this checked-off run finishes: manual steps only, deploying into the run's org, and no other
     * run there still to do.
     * @param run the run, checked off (not saved yet)
     * @return the release, or null
     */
    public static RLY_Release__c finishedBy(RLY_Manual_Step_Run__c run) {
        RLY_Release__c rel = RlyReleaseStore.release(run.Release__c);
        if (!isManualOnly(rel) || rel.Status__c != DEPLOYING || rel.Target_Org__c != run.Org__c) {
            return null;
        }
        return openRuns(rel, run.Id) == 0 ? rel : null;
    }

    /**
     * @description The notice while a manual-steps-only release waits for the deployment team after its approval.
     * @param rel the release
     * @return "Deployed in <org> when the deployment team finishes 2 manual steps.", or null
     */
    public static String notice(RLY_Release__c rel) {
        if (!isManualOnly(rel) || rel.Status__c != DEPLOYING) {
            return null;
        }
        Integer n = openRuns(rel, null);
        String target = rel.Target_Org__r == null ? 'the target org' : rel.Target_Org__r.Name;
        return n == 0 ? null : 'Manual steps only: deployed in ' + target + ' when the deployment team finishes '
            + RlyManualSteps.stepWords(n) + '.';
    }
}
