/**
 * @description The nightly archive call (RlyArchiveRest, POST /services/apexrest/rly/archive) from the Git pipeline's
 * scheduled job, one pass per call. Body: {"runUrl": the GitHub Actions run, "runId": the run of the previous call}.
 * Answer: {"runId", "pass", "removed", "records", "remaining", "done", "skipped", "reason"}. Every call stamps
 * Last_Nightly_Call__c and Last_Nightly_Result__c. A call is skipped (no run row) outside the production hub, for a
 * caller who isn't an admin, with nightly off or no days, or while another run is going. Nothing eligible on the first
 * call leaves a Succeeded row "Nothing to remove". Otherwise the first call starts a Nightly run and makes pass 1;
 * later calls pass its runId.
 */
public with sharing class RlyArchiveNightly {

    /** @description Skipped outside the production hub. */
    public static final String SKIP_HUB = 'Skipped: this org isn\'t the production hub';
    /** @description Skipped for a caller without Release Relay Admin. */
    public static final String SKIP_ADMIN = 'Skipped: the pipeline\'s hub user needs Release Relay Admin';
    /** @description Skipped with nightly off (board wording). */
    public static final String SKIP_OFF = 'Skipped: nightly is off';
    /** @description Skipped with no days set. */
    public static final String SKIP_DAYS = 'Skipped: no Retention days set';
    /** @description Skipped while another run is going. */
    public static final String SKIP_BUSY = 'Skipped: another run is going';
    /** @description Skipped when the runId sent isn't a nightly run that is still going. */
    public static final String SKIP_ENDED = 'Skipped: that run has finished';
    /** @description A first call with nothing eligible. */
    public static final String NOTHING = 'Nothing to remove';

    /**
     * @description Handles one call.
     * @param body the request body (JSON)
     * @return the answer
     */
    public static Map<String, Object> handle(String body) {
        Map<String, Object> input = parse(body);
        RLY_Git_Connection__c conn = RlyArchiveSettings.read();
        Id runId = toId(input.get('runId'));
        String why = skipReason(conn);
        RLY_Archive_Run__c run = why == null && runId != null ? RlyArchiveRuns.find(runId) : null;
        why = why != null ? why : busyReason(runId, run);
        if (why != null) {
            RlyArchiveSettings.stampCall(conn, why);
            Map<String, Object> skipped = answer(null, why);
            skipped.put('skipped', true);
            return skipped;
        }
        if (run == null) {
            run = firstRun(conn, url(input.get('runUrl')));
            if (run.Status__c != RlyArchiveRuns.RUNNING) {
                RlyArchiveSettings.stampCall(conn, RlyArchiveRuns.SUCCEEDED + ': ' + NOTHING.toLowerCase());
                return answer(run.Id, NOTHING);
            }
        }
        RlyArchiveViews.PassResult p = RlyArchiveRunner.pass(run);
        RlyArchiveSettings.stampCall(conn, resultText(p));
        Map<String, Object> out = answer(p.runId, p.message);
        out.put('pass', p.pass);
        out.put('done', p.done);
        out.put('removed', p.releases);
        out.put('records', p.records);
        out.put('remaining', p.remaining);
        return out;
    }

    // A later call must name a nightly run that is still going; a first call is refused while another run goes.
    private static String busyReason(Id runId, RLY_Archive_Run__c run) {
        if (runId == null) {
            return RlyArchiveRuns.running() != null ? SKIP_BUSY : null;
        }
        Boolean going = run != null && run.Status__c == RlyArchiveRuns.RUNNING && run.How__c == RlyArchiveRuns.NIGHTLY;
        return going ? null : SKIP_ENDED;
    }

    // The first call starts a Nightly run, or leaves a Succeeded "Nothing to remove" row when nothing is eligible.
    private static RLY_Archive_Run__c firstRun(RLY_Git_Connection__c conn, String runUrl) {
        Integer days = RlyArchiveSettings.days(conn);
        Datetime cut = RlyArchiveService.cutoff(days);
        return RlyArchiveEligible.countReleases(cut) == 0 ? RlyArchiveRuns.nothingToRemove(days, cut, runUrl)
            : RlyArchiveRuns.start(RlyArchiveRuns.NIGHTLY, days, runUrl);
    }

    // Why the call is skipped, or null.
    private static String skipReason(RLY_Git_Connection__c conn) {
        if (!RlyArchiveService.onHub() || conn == null) {
            return SKIP_HUB;
        }
        if (!RlyOrgController.isAdmin()) {
            return SKIP_ADMIN;
        }
        if (!RlyArchiveSettings.nightly(conn)) {
            return SKIP_OFF;
        }
        return RlyArchiveSettings.days(conn) == null ? SKIP_DAYS : null;
    }

    // What Last_Nightly_Result__c says after a pass.
    private static String resultText(RlyArchiveViews.PassResult p) {
        if (p.status == RlyArchiveRuns.RUNNING) {
            return 'Running: pass ' + p.pass;
        }
        return p.status == RlyArchiveRuns.SUCCEEDED ? RlyArchiveRuns.SUCCEEDED : p.status + ': ' + p.message;
    }

    // A finished answer (done, nothing removed); a pass overwrites what it changes.
    private static Map<String, Object> answer(Id runId, String reason) {
        return new Map<String, Object>{ 'runId' => runId, 'pass' => 0, 'removed' => 0, 'records' => 0, 'remaining' => 0,
            'done' => true, 'skipped' => false, 'reason' => reason };
    }

    private static Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object o = JSON.deserializeUntyped(body);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        } catch (JSONException e) {
            return new Map<String, Object>();
        }
    }

    // Only an https address is kept (the GitHub Actions run).
    private static String url(Object o) {
        String s = o instanceof String ? ((String) o).trim() : null;
        return String.isNotBlank(s) && s.startsWith('https://') ? s.left(255) : null;
    }

    private static Id toId(Object o) {
        if (!(o instanceof String) || String.isBlank((String) o)) {
            return null;
        }
        try {
            return Id.valueOf((String) o);
        } catch (StringException e) {
            return null;
        }
    }
}
