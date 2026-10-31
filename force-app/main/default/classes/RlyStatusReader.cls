/**
 * @description Moves a release along: reads where it is (retrieve, pipeline run, pull request, result files)
 * and saves what changed. The release page calls it while something is running.
 *
 * Statuses: Retrieving → Workflow running → Validating → Checks failed | Ready for approval
 *           → Deploying (after approval) → Deployed | Deploy failed. Rejected, Closed and
 *           Failed end it. Callouts come first (Slack too, for a status that's an event) and the saves last.
 */
public with sharing class RlyStatusReader {

    /** @description Statuses in which something is running and the page keeps checking. */
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Retrieving', 'Workflow running', 'Validating', 'Deploying' };

    /**
     * @description Reads the latest status of a release and saves it. A failure to read keeps the release where it is,
     * with the reason on the page; the next check tries again.
     * @param releaseId the release
     * @return the release as saved
     */
    public static RLY_Release__c advance(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        if (!OPEN_STATUSES.contains(rel.Status__c) || rel.Source_Org__c == null) {
            return rel;
        }
        RlyGit git = RlyGit.forConnection(RlyReleaseStore.git());
        String oldStatus = rel.Status__c;
        try {
            readLatest(rel, git);
        } catch (Exception e) {
            rel.Error_Message__c = ('Couldn\'t read the latest status: ' + e.getMessage()).left(2000);
        }
        rel.Last_Synced__c = System.now();
        RlySlack.notifyTransition(rel, oldStatus); // the Slack callout comes before any DML
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        return rel;
    }

    private static void readLatest(RLY_Release__c rel, RlyGit git) {
        if (rel.Status__c == 'Retrieving') {
            afterRetrieve(rel, git);
        } else if (rel.Status__c == 'Deploying') {
            RlyDeployReader.readDeploy(rel, git);
        } else {
            RlyCheckReader.readChecks(rel, git);
            RlyApprovalRuns.approveInGitIfSet(rel);
        }
    }

    // When the retrieve is done: commit the zip to the release branch and start the pipeline (mode hub).
    // The release branch starts from the developer org's own branch, so Git merges it with what's in the target.
    private static void afterRetrieve(RLY_Release__c rel, RlyGit git) {
        RLY_Org__c source = RlyReleaseStore.org(rel.Source_Org__c);
        RlyRetrieve.RetrieveStatus st = RlyRetrieve.check(source, rel.Retrieve_Id__c);
        if (!st.done) {
            return;
        }
        String problem = retrieveProblem(st, source);
        if (problem != null) {
            fail(rel, problem);
            return;
        }
        String branch = RlyPipelineRun.branchName(rel);
        if (!git.branchExists(branch)) {
            git.createBranch(branch, baseBranch(source, rel));
        }
        git.putFile(new RlyGitFile('.relay-inbox/' + rel.Name + '.zip', branch)
            .withContent(st.zipBase64, rel.Name + ': components from ' + source.Name));
        git.startPipeline(RlyPipelineRun.inputs(rel, 'hub', branch));
        rel.Source_Branch__c = branch;
        rel.Status__c = 'Workflow running';
        rel.Pending_Run__c = 'hub';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    // The developer org's branch; releases raised before every dev org had one start from the target, as they did.
    // A hotfix starts from the target's branch, so its pull request carries only the hotfix.
    private static String baseBranch(RLY_Org__c source, RLY_Release__c rel) {
        return source.Role__c == 'Stage' || String.isBlank(source.Branch__c) ? rel.Target_Branch__c : source.Branch__c.trim();
    }

    private static String retrieveProblem(RlyRetrieve.RetrieveStatus st, RLY_Org__c source) {
        if (!st.success || String.isBlank(st.zipBase64)) {
            return 'Retrieving from ' + source.Name + ' failed: ' + (st.message == null ? '' : st.message)
                + (st.problems.isEmpty() ? '' : ' ' + String.join(st.problems, '; '));
        }
        if (!st.problems.isEmpty()) {
            return 'Some components couldn\'t be retrieved from ' + source.Name + ': ' + String.join(st.problems, '; ');
        }
        return null;
    }

    /**
     * @description Ends the release as Failed, with the reason.
     * @param rel the release
     * @param message the reason
     */
    public static void fail(RLY_Release__c rel, String message) {
        rel.Status__c = 'Failed';
        rel.Error_Message__c = message.left(2000);
    }
}
