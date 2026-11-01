/**
 * @description Reads a release's checks: the pull request the pipeline opened, the code scan and the validation
 * result files (a validation can be a conflict with the target branch), and decides whether it's ready for approval.
 * A check or resolve run that ends without writing its results makes them Error, as a hub run does.
 */
public with sharing class RlyCheckReader {

    private static final Set<String> FINISHED = new Set<String>{ 'Passed', 'Failed', 'Skipped', 'Error', 'Bypassed' };
    // Runs that open the pull request (and write raise.json).
    private static final Set<String> RAISE_MODES = new Set<String>{ 'hub', RlyPromotion.MODE };

    /**
     * @description Reads the pull request and the check results of a release that is being checked.
     * @param rel the release (Workflow running or Validating)
     * @param git the Git provider
     */
    public static void readChecks(RLY_Release__c rel, RlyGit git) {
        RlyGit.PullRequest pr = git.findPullRequest(rel.Source_Branch__c, rel.Target_Branch__c);
        RlyGit.Run run = RlyPipelineRun.findRun(git, rel);
        if (pr == null) {
            if (run != null && run.failed() && RAISE_MODES.contains(rel.Pending_Run__c)) {
                RlyStatusReader.fail(rel, raiseProblem(rel, git));
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
            noteRaiseFailure(rel, git, run);
        }
        decide(rel);
    }

    // A hub run on an open pull request (changes added to the release) that failed: raise.json says why.
    private static void noteRaiseFailure(RLY_Release__c rel, RlyGit git, RlyGit.Run run) {
        if (run.failed() && RAISE_MODES.contains(rel.Pending_Run__c)) {
            Map<String, Object> raiseResult = RlyPipelineRun.result(git, rel, 'raise');
            if (isFailed(raiseResult)) {
                rel.Error_Message__c = String.valueOf(raiseResult.get('message')).left(2000);
            }
        }
    }

    private static Boolean isFailed(Map<String, Object> raiseResult) {
        return raiseResult != null && String.valueOf(raiseResult.get('status')) == 'Failed' && raiseResult.get('message') != null;
    }

    // raise.json's message when the run says why it failed (hub and promote write it), else a pointer to the run. A
    // promotion that clashes (the next stop has a change the stage doesn't) lists the files: they are kept in
    // Validation_Result__c as raiseConflicts, which the release page lists under the message.
    private static String raiseProblem(RLY_Release__c rel, RlyGit git) {
        Map<String, Object> raiseResult = RlyPipelineRun.result(git, rel, 'raise');
        if (!isFailed(raiseResult)) {
            return 'The pipeline couldn\'t open the pull request. Open the run for the reason.';
        }
        Object files = raiseResult.get('conflicts');
        if (files instanceof List<Object> && !((List<Object>) files).isEmpty()) {
            rel.Validation_Result__c = JSON.serialize(new Map<String, Object>{
                'raiseConflicts' => files, 'clash' => raiseResult.get('clash'), 'message' => raiseResult.get('message') }).left(131072);
        }
        return String.valueOf(raiseResult.get('message'));
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
            // A conflict with the target fails the validation (the picklist has no Conflict value); the page shows the files.
            rel.Validation_Status__c = RlyConflictResult.isConflict(val) ? 'Failed' : String.valueOf(val.get('status'));
            rel.Validation_Result__c = RlyConflictResult.fit(val);
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
