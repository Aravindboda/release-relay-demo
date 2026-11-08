/**
 * @description Pipeline Monitor: a run whose checks failed. GitHub ends a check run "successfully" when the check-only
 * deploy, a test or the code scan fails (the pipeline records the failure in its result files), so the run would show
 * green. The run turns Failed, with why, in either order:
 *   afterRead       the release has just turned Checks failed (RlyStatusReader): its run's green attempts become Failed
 *   failedChecksOf  the run's end arrives after the release is Checks failed (RlyRunMonitorInbound): saved as Failed
 */
public with sharing class RlyRunMonitorChecks {

    /** @description The release status that fails its run. */
    public static final String CHECKS_FAILED = 'Checks failed';
    /** @description Most test names in the message. */
    private static final Integer MAX_TESTS = 3;

    /**
     * @description After a release was read and saved: when it has just turned Checks failed, marks its run Failed.
     * Never throws (the monitor must not stop a release from moving).
     * @param rel the release as saved
     * @param oldStatus its status before the read
     * @return how many runs were marked Failed (0 also when it couldn't save them)
     */
    public static Integer afterRead(RLY_Release__c rel, String oldStatus) {
        if (rel == null || rel.Status__c != CHECKS_FAILED || oldStatus == CHECKS_FAILED || String.isBlank(rel.Run_ID__c)) {
            return 0;
        }
        try {
            List<RLY_Pipeline_Run__c> runs = RlyRunMonitorStore.succeededAttempts(rel.Run_ID__c);
            String why = reasonFor(rel);
            for (RLY_Pipeline_Run__c r : runs) {
                r.Status__c = RlyRunMonitorInput.FAILED;
                r.Failure_Message__c = why;
            }
            RlyRunMonitorStore.updateAll(runs);
            return runs.size();
        } catch (Exception e) {
            return 0; // the run's end post still turns it Failed (failedChecksOf)
        }
    }

    /**
     * @description Why a run that ended green failed, when its release's checks failed in that run.
     * @param rel the run's release (RlyRunMonitorReleases.releaseByName), or null
     * @param githubRunId the run's GitHub id
     * @return the reason, or null when the run stays as GitHub says
     */
    public static String failedChecksOf(RLY_Release__c rel, Long githubRunId) {
        Boolean sameRun = rel != null && githubRunId != null && String.valueOf(githubRunId) == rel.Run_ID__c;
        return sameRun && rel.Status__c == CHECKS_FAILED ? reasonFor(rel) : null;
    }

    /**
     * @description The reason, from the release's check results: the failed tests, a conflict, the validation's
     * message and the scan's blocking findings.
     * @param rel the release
     * @return Checks failed: …
     */
    public static String reasonFor(RLY_Release__c rel) {
        List<String> parts = new List<String>();
        Map<String, Object> val = RlySyncParse.parsedOrEmpty(rel.Validation_Result__c);
        if (rel.Validation_Status__c == 'Failed' || rel.Validation_Status__c == 'Error') {
            parts.add(validationReason(val, rel));
        }
        if ((rel.Scan_Status__c == 'Failed' || rel.Scan_Status__c == 'Error') && rel.Scan_Blocking__c != null && rel.Scan_Blocking__c > 0) {
            Integer n = rel.Scan_Blocking__c.intValue();
            parts.add('code scan: ' + n + ' blocking finding' + (n == 1 ? '' : 's'));
        }
        return ('Checks failed' + (parts.isEmpty() ? '.' : ': ' + String.join(parts, '; ') + '.')).left(32768);
    }

    // The failed tests, a conflict or the validation's own message.
    private static String validationReason(Map<String, Object> val, RLY_Release__c rel) {
        List<Object> tests = val.get('testFailures') instanceof List<Object> ? (List<Object>) val.get('testFailures') : new List<Object>();
        if (!tests.isEmpty()) {
            return tests.size() + ' test' + (tests.size() == 1 ? '' : 's') + ' failed (' + testNames(tests) + ')';
        }
        if (val.get('conflicts') instanceof List<Object>) {
            return 'conflicts with ' + (String.isBlank(rel.Target_Branch__c) ? 'the target branch' : rel.Target_Branch__c);
        }
        Object message = val.get('message');
        return message == null ? 'the check-only deploy failed' : String.valueOf(message).normalizeSpace().left(500);
    }

    // The first few test names (Class.method), unique.
    private static String testNames(List<Object> tests) {
        Set<String> names = new Set<String>();
        for (Object o : tests) {
            if (names.size() >= MAX_TESTS) {
                break;
            }
            Map<String, Object> t = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            String name = t.get('name') == null ? '' : String.valueOf(t.get('name'));
            String method = t.get('method') == null ? '' : String.valueOf(t.get('method'));
            names.add(String.isBlank(method) ? name : name + '.' + method);
        }
        String text = String.join(new List<String>(names), ', ');
        return tests.size() > names.size() ? text + ', …' : text;
    }
}
