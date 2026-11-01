/**
 * @description Moves a release along: reads where it is (retrieve, pipeline run, pull request, result files)
 * and saves what changed. The release page calls it while something is running.
 *
 * Statuses: Retrieving → Workflow running → Validating → Checks failed | Ready for approval
 *           → Deploying (after approval) → Deployed | Deploy failed. Rejected, Closed and
 *           Failed end it. A promotion starts Submitted (queued: its first run, mode promote, starts on the next
 *           read) → Workflow running → …; a back promote sync Submitted → Deploying (mode sync) → Deployed | Failed.
 *           A release with only manual steps (RlyManualOnly) Submitted → Ready for approval → Deploying while its manual
 *           steps in the target are open → Deployed, with no pipeline run.
 *           Callouts come first (Slack too: the card is edited on every change it shows) and the saves last; a deploy to the hub
 *           then queues the back promote syncs (RlyBackPromote.afterDeploy). When the checks pass and the target org's
 *           approval rule needs no approver, the release is approved by rule and its deploy starts (RlyAutoApproval); after a
 *           deploy the flows chosen Activate are activated (RlyFlowActivation). In a sandbox copy of the hub it only reads.
 */
public with sharing class RlyStatusReader {

    /** @description Statuses in which something is running and the page keeps checking. */
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Submitted', 'Retrieving', 'Workflow running', 'Validating', 'Deploying' };

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
        // In a sandbox copy of the hub the page only reads: no deploy, approval, run, sync, activation or Slack post.
        if (!OPEN_STATUSES.contains(rel.Status__c) || rel.Source_Org__c == null || !RlyHubGuard.isHub()) {
            return rel;
        }
        RlyGit git = RlyGit.forConnection(RlyReleaseStore.git());
        String oldStatus = rel.Status__c;
        RLY_Release__c prior = rel.clone(true, true, true, true);
        try {
            readLatest(rel, git);
            RlyAutoApproval.afterChecks(rel, git, oldStatus);
        } catch (Exception e) {
            rel.Error_Message__c = ('Couldn\'t read the latest status: ' + e.getMessage()).left(2000);
        }
        RlyFlowActivation.afterRead(rel, oldStatus); // flows chosen Activate, in the org just deployed to (callouts)
        rel.Last_Synced__c = System.now();
        RlySlackCardSync.notifyChange(prior, rel); // the Slack callouts (the card is kept current) come before any DML
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        if (oldStatus != 'Deployed' && rel.Status__c == 'Deployed') {
            RlyBackPromoteQueue.afterDeploy(rel);
        }
        return rel;
    }

    /**
     * @description Whether something is running for the release (the page keeps checking).
     * @param rel the release
     * @return true in an open status
     */
    public static Boolean isOpen(RLY_Release__c rel) {
        return rel != null && OPEN_STATUSES.contains(rel.Status__c);
    }

    private static void readLatest(RLY_Release__c rel, RlyGit git) {
        String relType = RlyPromotion.typeOf(rel);
        if (relType == RlyPromotion.TYPE_BACK_PROMOTE) {
            RlyBackPromoteRun.advanceSync(rel, git);
        } else if (RlyManualOnly.isManualOnly(rel)) {
            RlyManualOnly.advance(rel); // no pipeline: to approval, or Deployed when its manual steps are done
        } else if (rel.Status__c == RlyPromotion.QUEUED) {
            if (relType == RlyPromotion.TYPE_PROMOTION) {
                RlyPromotion.dispatch(rel, git);
            }
        } else if (rel.Status__c == 'Retrieving') {
            afterRetrieve(rel, git);
        } else if (rel.Status__c == 'Deploying') {
            RlyDeployReader.readDeploy(rel, git);
        } else {
            RlyCheckReader.readChecks(rel, git);
        }
    }

    // When the retrieve is done: commit the zip to the release branch and start the pipeline (mode hub). A release with
    // only deletions has no retrieve: it commits its marker file (.relay-inbox/<REL>.deletions) instead of a zip.
    // The release branch starts from the developer org's own branch, so Git merges it with what's in the target.
    private static void afterRetrieve(RLY_Release__c rel, RlyGit git) {
        RLY_Org__c source = RlyReleaseStore.org(rel.Source_Org__c);
        String branch = RlyPipelineRun.branchName(rel);
        RlyGitFile file = String.isBlank(rel.Retrieve_Id__c) ? RlyDeletions.marker(rel, branch) : retrievedZip(rel, source, branch);
        if (file == null) {
            if (String.isBlank(rel.Retrieve_Id__c)) {
                fail(rel, 'The release has no components and no deletions.');
            }
            return;
        }
        if (!git.branchExists(branch)) {
            git.createBranch(branch, baseBranch(source, rel));
        }
        git.putFile(file);
        git.startPipeline(RlyPipelineRun.inputs(rel, 'hub', branch));
        rel.Source_Branch__c = branch;
        rel.Status__c = 'Workflow running';
        rel.Pending_Run__c = 'hub';
        rel.Checks_Requested__c = System.now();
        rel.Error_Message__c = null;
    }

    // The retrieved zip as a file to commit; null while the retrieve runs or when it failed (the release is then Failed).
    private static RlyGitFile retrievedZip(RLY_Release__c rel, RLY_Org__c source, String branch) {
        RlyRetrieve.RetrieveStatus st = RlyRetrieve.check(source, rel.Retrieve_Id__c);
        if (!st.done) {
            return null;
        }
        String problem = retrieveProblem(st, source);
        if (problem != null) {
            fail(rel, problem);
            return null;
        }
        return new RlyGitFile('.relay-inbox/' + rel.Name + '.zip', branch)
            .withContent(st.zipBase64, rel.Name + ': components from ' + source.Name);
    }

    // The developer org's branch; releases raised before every dev org had one start from the target, as they did.
    // A hotfix starts from the target's branch, so its pull request (and its merge commit, promoted later on its own)
    // carries only the hotfix.
    private static String baseBranch(RLY_Org__c source, RLY_Release__c rel) {
        return RlyHotfix.isHotfix(rel) || String.isBlank(source.Branch__c) ? rel.Target_Branch__c : source.Branch__c.trim();
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
