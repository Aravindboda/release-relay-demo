/**
 * @description Follows a running rollback (RlyRollback starts it): reads results/<request>/rollback.json from the
 * results branch like every other result (its attempt must be the rollback's token), or notices a run that failed
 * before writing one, and records Rolled back or Failed: the rollback fields, a history event (Rolled_Back or
 * Rollback_Failed) and the Slack card's line. Callouts first, saves last; reading problems leave it running.
 */
public with sharing class RlyRollbackRun {

    /**
     * @description The title of a rollback's pipeline run.
     * @param ownerName the request the rollback runs as
     * @return the run title
     */
    public static String runTitle(String ownerName) {
        return 'Release Relay ' + ownerName + ' (' + RlyRollback.MODE + ')';
    }

    /**
     * @description For a release with nothing running (RlyReleasesController.refreshRelease): reads its running
     * rollback, or else, on the hub, starts or reads the queued and running back promote syncs (RlyBackPromoteRun.catchUp).
     * @param releaseId the release
     */
    public static void readIdle(Id releaseId) {
        if (RlyRollbackState.isRunning(releaseId)) {
            advance(releaseId);
        } else if (RlyHubGuard.isHub()) {
            RlyBackPromoteRun.catchUp();
        }
    }

    /**
     * @description Reads a running rollback's result and records how it ended. Reading problems leave it running.
     * @param releaseId the release
     */
    public static void advance(Id releaseId) {
        RLY_Release__c running = RlyRollbackState.rowOf(releaseId);
        if (running.Rollback_Status__c != RlyRollbackState.RUNNING || !RlyHubGuard.isHub()) {
            return;
        }
        Map<String, Object> started = RlyRollbackState.result(running);
        String owner = RlyEvidenceText.str(started.get('request'));
        Map<String, Object> outcome;
        try {
            RlyGit git = RlyGit.forConnection(RlyReleaseStore.git());
            outcome = readResult(git, owner, running.Rollback_Token__c);
            if (outcome == null) {
                outcome = runFailure(git, owner, running);
            }
        } catch (Exception e) {
            return; // couldn't read: the next check tries again
        }
        if (outcome != null) {
            finish(running, started, outcome);
        }
    }

    private static Map<String, Object> readResult(RlyGit git, String owner, String token) {
        String raw = git.getFileRaw('results/' + owner + '/' + RlyRollback.MODE + '.json', RlyPipelineRun.RESULTS_BRANCH);
        Map<String, Object> r = RlyEvidenceText.parse(raw);
        return r.isEmpty() || token == null || !token.equals(String.valueOf(r.get('attempt'))) ? null : r;
    }

    // A run that failed before it wrote a result (looked for a minute after the start, so an earlier run isn't taken).
    private static Map<String, Object> runFailure(RlyGit git, String owner, RLY_Release__c running) {
        if (running.Rollback_On__c != null && running.Rollback_On__c > System.now().addMinutes(-1)) {
            return null;
        }
        RlyGit.Run run = git.findRun(runTitle(owner));
        if (run == null || !run.failed()) {
            return null;
        }
        return new Map<String, Object>{ 'status' => 'Failed', 'runUrl' => run.url,
            'message' => 'The pipeline run failed before it wrote a result. Open the run.' };
    }

    // Rolled back or Failed: the fields, the history event and the Slack card's line.
    private static void finish(RLY_Release__c running, Map<String, Object> started, Map<String, Object> outcome) {
        Boolean ok = String.valueOf(outcome.get('status')) == 'Rolled back';
        Map<String, Object> merged = started.clone();
        for (String k : outcome.keySet()) {
            Object v = outcome.get(k);
            merged.put(k, v instanceof List<Object> ? firstOf((List<Object>) v) : v);
        }
        RLY_Release__c row = running.clone(true, true, true, true);
        row.Rollback_Status__c = ok ? RlyRollbackState.ROLLED_BACK : RlyRollbackState.FAILED;
        row.Rollback_On__c = ok ? System.now() : running.Rollback_On__c;
        row.Rollback_Result__c = JSON.serialize(merged).left(32768);
        String org = RlyRollbackState.orgName(row);
        String counts = RlyRollbackState.counts(row);
        String detail = ok ? 'Rolled back in ' + org + ': ' + counts + ' · “' + row.Rollback_Reason__c + '”'
            : 'Rollback failed in ' + org + ': ' + RlyEvidenceText.text(RlyEvidenceText.str(merged.get('message')));
        RlyReleaseLog.add(new RLY_Release__c(Id = row.Id), ok ? 'Rolled_Back' : 'Rollback_Failed', detail)
            .inOrg(row.Rollback_Org__c).byActor(row.Rollback_By__c, RlyReleaseLog.VIA_SALESFORCE)
            .withReference(RlyEvidenceText.str(merged.get('deployId')));
        record(row, running);
    }

    private static List<Object> firstOf(List<Object> values) {
        List<Object> out = new List<Object>();
        for (Object v : values) {
            if (out.size() < 50) {
                out.add(v);
            }
        }
        return out;
    }

    /**
     * @description Tells Slack about a rollback change (callouts), then saves the rollback fields, the Slack result and
     * the history (DML).
     * @param row the rollback fields as changed, with Rollback_Org__r.Name
     * @param earlier the rollback fields before the change, or null when it starts
     */
    public static void record(RLY_Release__c row, RLY_Release__c earlier) {
        RLY_Release__c rel = RlyReleaseStore.release(row.Id);
        if (rel != null) {
            RLY_Release__c prior = rel.clone(true, true, true, true);
            prior.Rollback_Status__c = earlier == null ? null : earlier.Rollback_Status__c;
            prior.Rollback_Org__c = earlier == null ? null : earlier.Rollback_Org__c;
            rel.Rollback_Status__c = row.Rollback_Status__c;
            rel.Rollback_Org__c = row.Rollback_Org__c;
            RlyRollbackState.remember(row);
            RlySlackCardSync.notifyChange(prior, rel);
        }
        RlyRollbackState.save(row);
        RlySlack.saveResults();
        RlyReleaseLog.flush();
    }
}
