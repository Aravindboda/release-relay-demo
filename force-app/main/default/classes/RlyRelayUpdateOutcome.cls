/**
 * @description Install Release Relay update: what a step shows from its result file: status, tests run, test failures
 * and component errors (one line each), the message, the run link (https only) and when it finished.
 */
public with sharing class RlyRelayUpdateOutcome {

    private static final String HTTPS = 'https://';
    private static final Integer MOST_FAILURES = 20;
    private static final Integer LINE_CHARS = 400;

    /**
     * @description Puts a result on a step: tests run, failures, message, run link and when it finished.
     * @param s the step
     * @param r the result
     * @param status the step's new status
     */
    public static void apply(RlyRelayUpdateState.Step s, Map<String, Object> r, String status) {
        s.status = status;
        Object tests = r.get('testsRun');
        s.testsRun = tests == null ? s.testsRun : Integer.valueOf(String.valueOf(tests));
        s.failures = failures(r);
        s.message = r.get('message') == null ? null : String.valueOf(r.get('message')).left(1000);
        String url = https(r.get('runUrl'));
        s.runUrl = url == null ? s.runUrl : url;
        s.finishedAt = r.get('finishedAt') == null ? null : String.valueOf(r.get('finishedAt'));
    }

    /**
     * @description A result's test failures and component errors, one line each (at most MOST_FAILURES).
     * @param r the result
     * @return the lines
     */
    public static List<String> failures(Map<String, Object> r) {
        List<String> out = new List<String>();
        for (Object o : asList(r.get('testFailures'))) {
            Map<String, Object> t = asMap(o);
            out.add((text(t.get('name')) + '.' + text(t.get('method')) + ': ' + text(t.get('message'))).left(LINE_CHARS));
        }
        for (Object o : asList(r.get('componentErrors'))) {
            Map<String, Object> c = asMap(o);
            String line = c.get('line') == null ? '' : ' (line ' + text(c.get('line')) + ')';
            out.add((text(c.get('type')) + ' ' + text(c.get('name')) + line + ': ' + text(c.get('problem'))).left(LINE_CHARS));
        }
        while (out.size() > MOST_FAILURES) {
            out.remove(out.size() - 1);
        }
        return out;
    }

    /**
     * @description A link, when it is https.
     * @param value the link
     * @return it, or null
     */
    public static String https(Object value) {
        String url = value == null ? '' : String.valueOf(value).trim();
        return url.startsWith(HTTPS) ? url : null;
    }

    /**
     * @description A value as text (empty when null).
     * @param o the value
     * @return the text
     */
    public static String text(Object o) {
        return o == null ? '' : String.valueOf(o);
    }

    private static List<Object> asList(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
    }
}
