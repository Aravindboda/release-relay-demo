/**
 * @description Install Release Relay update: reads the running step's result the way the release pages do. Each result
 * file under results/<request id>/ on the results branch is opened with RlyResultSignature (strict: while the hub has
 * a run-signing key, only files the pipeline signed count) and must carry the step's run token (attempt); a file from
 * an earlier run is ignored. A check is decided by validate.json (or a failed raise.json); an install by deploy.json
 * (or a failed merge.json). A run that ended without a result fails the step with the run's conclusion. Links are
 * kept only when they start with https://. Callouts only: the caller saves the update afterwards.
 */
public with sharing class RlyRelayUpdateResults {

    private static final String FAILED_STATUS = 'Failed';

    /**
     * @description Reads the running step's result and puts it on the update (not saved).
     * @param u the current update
     * @return the step's key when it was running (its state may now be final), or null when nothing runs
     */
    public static String refresh(RLY_Relay_Update__c u) {
        Map<String, RlyRelayUpdateState.Step> steps = RlyRelayUpdateState.read(u);
        String key = RlyRelayUpdateState.running(steps);
        if (key == null) {
            return null;
        }
        RlyRelayUpdateState.Step s = steps.get(key);
        RlyGit g = RlyRelayUpdateRuns.git();
        RlyGit.Run run = g.findRun(RlyRelayUpdateRuns.runTitle(s, key));
        if (run != null && RlyRelayUpdateOutcome.https(run.url) != null) {
            s.runUrl = run.url;
        }
        Boolean decided = RlyRelayUpdateState.isCheck(key) ? readCheck(g, s) : readInstall(g, s);
        if (!decided && run != null && run.completed()) {
            s.status = RlyRelayUpdateState.FAILED;
            s.message = 'The run ended (' + run.conclusion + ') without a result. Open the run for its log.'
                + (String.isBlank(s.message) ? '' : ' ' + s.message);
        }
        RlyRelayUpdateState.write(u, steps);
        return key;
    }

    // validate.json decides; a failed raise.json (no pull request) fails the check before it.
    private static Boolean readCheck(RlyGit g, RlyRelayUpdateState.Step s) {
        Map<String, Object> validate = result(g, s, 'validate');
        if (validate != null) {
            RlyRelayUpdateOutcome.apply(s, validate, RlyRelayUpdateOutcome.text(validate.get('status')) == 'Passed' ? RlyRelayUpdateState.PASSED : RlyRelayUpdateState.FAILED);
            Object head = validate.get('headSha');
            s.head = head == null ? null : String.valueOf(head);
            return true;
        }
        return failedBy(result(g, s, 'raise'), s);
    }

    // deploy.json decides; a failed merge.json fails the install before it.
    private static Boolean readInstall(RlyGit g, RlyRelayUpdateState.Step s) {
        Map<String, Object> deploy = result(g, s, 'deploy');
        if (deploy != null) {
            RlyRelayUpdateOutcome.apply(s, deploy, RlyRelayUpdateOutcome.text(deploy.get('status')) == 'Deployed' ? RlyRelayUpdateState.INSTALLED : RlyRelayUpdateState.FAILED);
            return true;
        }
        return failedBy(result(g, s, 'merge'), s);
    }

    private static Boolean failedBy(Map<String, Object> r, RlyRelayUpdateState.Step s) {
        if (r == null || RlyRelayUpdateOutcome.text(r.get('status')) != FAILED_STATUS) {
            return false;
        }
        RlyRelayUpdateOutcome.apply(s, r, RlyRelayUpdateState.FAILED);
        return true;
    }

    // A result file of this step's run: signed while the hub has a key, with the run's token (or, from a pipeline that
    // writes none, finished after the step started).
    private static Map<String, Object> result(RlyGit g, RlyRelayUpdateState.Step s, String step) {
        String raw = g.getFileRaw('results/' + s.requestId + '/' + step + '.json', RlyPipelineRun.RESULTS_BRANCH);
        if (String.isBlank(raw)) {
            return null;
        }
        RlyResultSignature.Opened opened = RlyResultSignature.open(raw, s.requestId, step);
        if (opened.rejected) {
            s.message = RlyResultSignature.REJECTED + ' (' + step + '.json). Add the hub\'s run-signing key to the repository as RELAY_RUN_KEY.';
            return null;
        }
        Map<String, Object> r = opened.data;
        if (r == null) {
            return null;
        }
        Object attempt = r.get('attempt');
        if (attempt != null) {
            return String.valueOf(attempt).equals(s.token) ? r : null;
        }
        return finishedAfterStart(r, s) ? r : null;
    }

    private static Boolean finishedAfterStart(Map<String, Object> r, RlyRelayUpdateState.Step s) {
        Object finished = r.get('finishedAt');
        if (finished == null || s.startedAt == null) {
            return false;
        }
        try {
            Datetime at = (Datetime) JSON.deserialize('"' + String.valueOf(finished) + '"', Datetime.class);
            return at >= s.startedAt.addMinutes(-2);
        } catch (Exception e) {
            return false;
        }
    }
}
