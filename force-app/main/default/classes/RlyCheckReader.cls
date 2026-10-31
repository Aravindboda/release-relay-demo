/**
 * @description Reads a release's checks: the pull request the pipeline opened, the code scan and the validation
 * result files, and decides whether it's ready for approval.
 */
public with sharing class RlyCheckReader {

    private static final Set<String> FINISHED = new Set<String>{ 'Passed', 'Failed', 'Skipped', 'Error', 'Bypassed' };

    /**
     * @description Reads the pull request and the check results of a release that is being checked.
     * @param rel the release (Workflow running or Validating)
     * @param git the Git provider
     */
    public static void readChecks(RLY_Release__c rel, RlyGit git) {
        RlyGit.PullRequest pr = git.findPullRequest(rel.Source_Branch__c, rel.Target_Branch__c);
        RlyGit.Run run = RlyPipelineRun.findRun(git, rel);
        if (pr == null) {
            if (run != null && run.failed() && rel.Pending_Run__c == 'hub') {
                RlyStatusReader.fail(rel, 'The pipeline couldn\'t open the pull request. Open the run for the reason.');
            }
            return;
        }
        rel.PR_Number__c = pr.prNumber;
        rel.PR_URL__c = pr.url;
        if (pr.state == 'closed') {
            rel.Status__c = 'Closed';
            return;
        }
        if (rel.Status__c == 'Workflow running') {
            rel.Status__c = 'Validating';
        }
        readScan(rel, git);
        readValidation(rel, git);
        // The run ended without writing a result (a job failed early): don't wait forever.
        if (run != null && run.completed()) {
            markMissingResults(rel);
        }
        decide(rel);
    }

    private static void readScan(RLY_Release__c rel, RlyGit git) {
        Map<String, Object> scan = rel.Scan_Status__c == 'Pending' ? RlyPipelineRun.result(git, rel, 'scan') : null;
        if (scan != null) {
            rel.Scan_Status__c = String.valueOf(scan.get('status'));
            rel.Scan_Violations__c = RlyPipelineRun.toNumber(scan.get('total'));
            rel.Scan_Blocking__c = RlyPipelineRun.toNumber(scan.get('blocking'));
            rel.Scan_Result__c = JSON.serialize(scan).left(131072);
        }
    }

    private static void readValidation(RLY_Release__c rel, RlyGit git) {
        Map<String, Object> val = rel.Validation_Status__c == 'Pending' ? RlyPipelineRun.result(git, rel, 'validate') : null;
        if (val != null) {
            rel.Validation_Status__c = String.valueOf(val.get('status'));
            rel.Validation_Result__c = JSON.serialize(val).left(131072);
        }
    }

    private static void markMissingResults(RLY_Release__c rel) {
        if (rel.Scan_Status__c == 'Pending') {
            rel.Scan_Status__c = 'Error';
            rel.Scan_Result__c = JSON.serialize(new Map<String, Object>{ 'message' => 'The code scan didn\'t write a result. Open the run.' });
        }
        if (rel.Validation_Status__c == 'Pending') {
            rel.Validation_Status__c = 'Error';
            rel.Validation_Result__c = JSON.serialize(new Map<String, Object>{ 'message' => 'The validation didn\'t write a result. Open the run.' });
        }
    }

    /**
     * @description Ready for approval when both checks are done and neither blocks; a blocking scan can be bypassed,
     * a failed validation can't.
     * @param rel the release
     */
    public static void decide(RLY_Release__c rel) {
        if (!isDone(rel.Scan_Status__c) || !isDone(rel.Validation_Status__c)) {
            return;
        }
        rel.Status__c = blocks(rel.Scan_Status__c) || blocks(rel.Validation_Status__c) ? 'Checks failed' : 'Ready for approval';
    }

    private static Boolean isDone(String checkStatus) {
        return checkStatus == 'Not configured' || FINISHED.contains(checkStatus);
    }

    private static Boolean blocks(String checkStatus) {
        return checkStatus == 'Failed' || checkStatus == 'Error';
    }
}
