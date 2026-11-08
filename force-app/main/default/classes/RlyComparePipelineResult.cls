/**
 * @description Compare in the pipeline: reads what the pipeline wrote on the results branch (RlyComparePipeline).
 *   check  results/CMP-…/compare.json once it's there and from this run (its attempt is the run's token): every
 *          component with its status and its files (numbers only, no text)
 *   file   results/CMP-…/f/n.json when a file is opened: both copies, or a unified diff for a file too large for both
 * The texts are at most 300,000 characters each (the pipeline cuts them), so one file is one small read. No DML.
 */
public with sharing class RlyComparePipelineResult {

    private static final String MISSING = 'missing';

    /** @description Where a compare in the pipeline is. */
    public class Result {
        /** @description The result is there (false: ask again). */
        @AuraEnabled public Boolean done = false;
        /** @description The pipeline couldn't compare (message says why). */
        @AuraEnabled public Boolean failed = false;
        /** @description Why it failed. */
        @AuraEnabled public String message;
        /** @description The run on GitHub, once it has started. */
        @AuraEnabled public String runUrl;
        /** @description The run's GitHub status (queued, in_progress, completed). */
        @AuraEnabled public String runStatus;
        /** @description The components, in the order sent. */
        @AuraEnabled public List<RlyCompareFiles.ComponentDiff> components = new List<RlyCompareFiles.ComponentDiff>();
    }

    /**
     * @description Reads the compare's result.
     * @param compareId the compare's id
     * @param token the run's token
     * @return done = false until the run has written it
     */
    public static Result check(String compareId, String token) {
        RlyComparePipeline.checkId(compareId);
        RlyGit git = RlyComparePipeline.gitHub();
        Result r = new Result();
        Map<String, Object> summary = RlyResultSignature.lenient(git.getFileRaw('results/' + compareId + '/compare.json', RlyPipelineRun.RESULTS_BRANCH),
            compareId, 'compare');
        Boolean fromThisRun = summary != null && String.isNotBlank(token) && token.equals(String.valueOf(summary.get('attempt')));
        if (!fromThisRun) {
            readRun(git, compareId, r);
            return r;
        }
        r.done = true;
        r.runUrl = RlyRunMonitorInput.url(summary.get('runUrl'));
        if (String.valueOf(summary.get('status')) != 'Succeeded') {
            r.failed = true;
            r.message = summary.get('message') == null ? 'The compare run failed. Open the run for the reason.' : String.valueOf(summary.get('message'));
            return r;
        }
        for (Object o : RlySyncParse.asList(summary.get('components'))) {
            r.components.add(component(RlySyncParse.asMap(o)));
        }
        return r;
    }

    /**
     * @description One file's copies (or its unified diff).
     * @param compareId the compare's id
     * @param n the file's number
     * @return the file
     */
    public static RlyCompareFiles.FileDiff file(String compareId, Integer n) {
        RlyComparePipeline.checkId(compareId);
        if (n == null || n < 1 || n > 100000) {
            throw new RlyReleaseException('That file isn\'t part of the compare.');
        }
        // Signed pages (pipeline v27) come wrapped: unwrapped and checked like the summary (step = the page number).
        Map<String, Object> f = RlyResultSignature.lenient(RlyComparePipeline.gitHub().getFileRaw('results/' + compareId + '/f/' + n + '.json',
            RlyPipelineRun.RESULTS_BRANCH), compareId, String.valueOf(n));
        if (f == null) {
            throw new RlyReleaseException('That file isn\'t on the results branch any more: compare again.');
        }
        RlyCompareFiles.FileDiff d = new RlyCompareFiles.FileDiff();
        d.n = n;
        d.path = RlySyncParse.text(f.get('path'));
        d.left = RlySyncParse.text(f.get('left'));
        d.right = RlySyncParse.text(f.get('right'));
        d.patch = RlySyncParse.text(f.get('patch'));
        d.status = d.patch != null ? RlyCompareFiles.CHANGED : RlyCompareParts.statusOf(d.left, d.right);
        return d;
    }

    // While there's no result yet: the run's link and state; a run that ended without a result fails the compare.
    private static void readRun(RlyGit git, String compareId, Result r) {
        RlyGit.Run run = git.findRun(RlyComparePipeline.runTitle(compareId));
        if (run == null) {
            return;
        }
        r.runUrl = run.url;
        r.runStatus = run.status;
        if (run.completed()) {
            r.done = true;
            r.failed = true;
            r.message = 'The compare run ended without writing its result. Open the run for the reason.';
        }
    }

    // A component from the summary: missing becomes Not available with the pipeline's reason.
    private static RlyCompareFiles.ComponentDiff component(Map<String, Object> m) {
        RlyCompareFiles.ComponentDiff c = new RlyCompareFiles.ComponentDiff();
        c.key = RlySyncParse.text(m.get('key'));
        String status = RlySyncParse.text(m.get('status'));
        c.deleted = status == RlyCompareFiles.REMOVED;
        c.status = status == MISSING || status == null ? RlyCompareFiles.UNSUPPORTED : status;
        c.reason = RlySyncParse.text(m.get('reason'));
        for (Object o : RlySyncParse.asList(m.get('files'))) {
            c.files.add(fileRow(RlySyncParse.asMap(o)));
        }
        return c;
    }

    // A file row: its number when it has text to show, else why not.
    private static RlyCompareFiles.FileDiff fileRow(Map<String, Object> m) {
        RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
        f.path = RlySyncParse.text(m.get('path'));
        f.reason = RlySyncParse.text(m.get('reason'));
        Object n = m.get('n');
        f.n = n == null ? null : Integer.valueOf(String.valueOf(n));
        f.status = f.n == null && f.reason != null ? RlyCompareFiles.UNSUPPORTED : RlySyncParse.text(m.get('status'));
        return f;
    }
}
