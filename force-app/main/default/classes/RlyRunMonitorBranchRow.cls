/**
 * @description One row of the Pipeline Monitor's Active branches (RlyRunMonitorBranches): the release's pull request
 * (its number, and its state from the release's status: open, merged or closed), the newest run's state (running,
 * failed, ok or idle) and org, and the last activity.
 */
public with sharing class RlyRunMonitorBranchRow {

    private static final Set<String> MERGED = new Set<String>{ 'Merged', 'Deploying', 'Deployed', 'Deploy failed' };
    private static final Set<String> CLOSED = new Set<String>{ 'Rejected', 'Closed', 'Failed' };

    /**
     * @description Fills a branch row from its release: number, pull request, target org and last change.
     * @param b the row
     * @param rel the release
     */
    public static void withRelease(RlyRunMonitorViews.BranchRow b, RLY_Release__c rel) {
        b.releaseId = rel.Id;
        b.releaseName = rel.Name;
        b.releaseStatus = rel.Status__c;
        b.prNumber = rel.PR_Number__c == null ? null : rel.PR_Number__c.intValue();
        b.prUrl = rel.PR_URL__c;
        b.prState = b.prNumber == null ? null : prState(rel.Status__c);
        b.stage = rel.Target_Org__r == null ? null : rel.Target_Org__r.Name;
        b.lastActivity = rel.LastModifiedDate;
    }

    /**
     * @description Fills a branch row from its newest run: the state, the org it ran in and the last activity.
     * @param b the row
     * @param run the run
     */
    public static void withRun(RlyRunMonitorViews.BranchRow b, RLY_Pipeline_Run__c run) {
        b.runRecordId = run.Id;
        b.step = run.Workflow_Step__c;
        b.stage = String.isNotBlank(run.Target_Org__c) ? run.Target_Org__c : b.stage;
        b.state = runState(run.Status__c);
        Datetime last = run.Finished__c != null ? run.Finished__c : run.Started__c;
        if (b.lastActivity == null || (last != null && last > b.lastActivity)) {
            b.lastActivity = last;
        }
    }

    /**
     * @description A branch's state from its newest run's status.
     * @param status the run's status
     * @return running, failed, ok or idle
     */
    public static String runState(String status) {
        if (RlyRunMonitorStore.ACTIVE.contains(status)) {
            return 'running';
        }
        if (status == RlyRunMonitorInput.FAILED) {
            return 'failed';
        }
        return status == RlyRunMonitorInput.SUCCEEDED ? 'ok' : 'idle';
    }

    // The pull request's state from its release's status.
    private static String prState(String status) {
        if (MERGED.contains(status)) {
            return 'merged';
        }
        return CLOSED.contains(status) ? 'closed' : 'open';
    }
}
