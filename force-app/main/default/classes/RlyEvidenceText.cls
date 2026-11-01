/**
 * @description Reads the pipeline's result files kept on a release (Validation_Result__c, Deploy_Result__c,
 * Back_Merge_Result__c) for the history, the evidence document and the change request summary, and words them:
 * tests run, coverage warnings, deploy ids, quick or full deploy, branches synced.
 */
public with sharing class RlyEvidenceText {

    /** @description What a validation result says. */
    public class Validation {
        /** @description The check-only deploy's id, or null. */
        public String deployId;
        /** @description Tests run. */
        public Integer testsRun = 0;
        /** @description Code coverage warnings, as "name: message". */
        public List<String> coverageWarnings = new List<String>();
        /** @description The result's message, or null. */
        public String message;
        /** @description It found conflicts with the target branch. */
        public Boolean conflict = false;

        /**
         * @description ": 12 tests run, 1 coverage warning, deploy 0Af…", or ": conflicts with the target branch".
         * @return the words (empty when there's nothing to say)
         */
        public String suffix() {
            if (conflict) {
                return ': conflicts with the target branch';
            }
            List<String> parts = new List<String>();
            if (testsRun > 0) {
                parts.add(testsRun + (testsRun == 1 ? ' test run' : ' tests run'));
            }
            if (!coverageWarnings.isEmpty()) {
                parts.add(coverageWarnings.size() + (coverageWarnings.size() == 1 ? ' coverage warning' : ' coverage warnings'));
            }
            if (String.isNotBlank(deployId)) {
                parts.add('deploy ' + deployId);
            }
            return parts.isEmpty() ? '' : ': ' + String.join(parts, ', ');
        }
    }

    /** @description What a deploy result says. */
    public class Deploy {
        /** @description The deploy's id, or null. */
        public String deployId;
        /** @description A quick deploy of the validation. */
        public Boolean quick = false;
        /** @description Tests run. */
        public Integer testsRun = 0;
        /** @description The result's message, or null. */
        public String message;

        /**
         * @description " (quick deploy 0Af…)" or " (full deploy 0Af…, 12 tests run)".
         * @return the words (empty without a deploy id)
         */
        public String suffix() {
            if (String.isBlank(deployId)) {
                return '';
            }
            return ' (' + (quick ? 'quick' : 'full') + ' deploy ' + deployId + (testsRun > 0 ? ', ' + testsRun + ' tests run' : '') + ')';
        }
    }

    /**
     * @description A value, or an empty string for null.
     * @param value the value
     * @return the text
     */
    public static String text(String value) {
        return value == null ? '' : value;
    }

    /**
     * @description ': “comment”', or nothing.
     * @param comment the comment, or null
     * @return the words
     */
    public static String comment(String comment) {
        return String.isBlank(comment) ? '' : ': “' + comment.trim().left(1000) + '”';
    }

    /**
     * @description ": 3 findings, 0 blocking", or nothing.
     * @param rel the release, with Scan_Violations__c and Scan_Blocking__c
     * @return the words
     */
    public static String scanCounts(RLY_Release__c rel) {
        if (rel.Scan_Violations__c == null) {
            return '';
        }
        Integer total = rel.Scan_Violations__c.intValue();
        Integer blocking = rel.Scan_Blocking__c == null ? 0 : rel.Scan_Blocking__c.intValue();
        return ': ' + total + (total == 1 ? ' finding, ' : ' findings, ') + blocking + ' blocking';
    }

    /**
     * @description Reads a validation result.
     * @param resultJson Validation_Result__c
     * @return what it says (empty when it can't be read)
     */
    public static Validation validationOf(String resultJson) {
        Validation v = new Validation();
        Map<String, Object> m = parse(resultJson);
        v.deployId = str(m.get('deployId'));
        v.testsRun = num(m.get('testsRun'));
        v.message = str(m.get('message'));
        v.conflict = RlyConflictResult.isConflict(m);
        for (Object w : m.get('coverageWarnings') instanceof List<Object> ? (List<Object>) m.get('coverageWarnings') : new List<Object>()) {
            Map<String, Object> wm = w instanceof Map<String, Object> ? (Map<String, Object>) w : new Map<String, Object>();
            v.coverageWarnings.add((str(wm.get('name')) == null ? '' : str(wm.get('name')) + ': ') + text(str(wm.get('message'))));
        }
        return v;
    }

    /**
     * @description Reads a deploy result.
     * @param resultJson Deploy_Result__c
     * @return what it says (empty when it can't be read)
     */
    public static Deploy deployOf(String resultJson) {
        Deploy d = new Deploy();
        Map<String, Object> m = parse(resultJson);
        d.deployId = str(m.get('deployId'));
        d.quick = m.get('quick') == true;
        d.testsRun = num(m.get('testsRun'));
        d.message = str(m.get('message'));
        return d;
    }

    /**
     * @description "3 synced, 1 conflict" from a back-merge result.
     * @param resultJson Back_Merge_Result__c
     * @return the counts by status
     */
    public static String backMergeCounts(String resultJson) {
        Map<String, Integer> counts = new Map<String, Integer>();
        List<String> order = new List<String>();
        for (RlyReleasesController.BranchSync b : RlyReleaseLinks.backMerge(resultJson)) {
            String key = b.status == null ? 'unknown' : b.status.toLowerCase();
            if (!counts.containsKey(key)) {
                counts.put(key, 0);
                order.add(key);
            }
            counts.put(key, counts.get(key) + 1);
        }
        List<String> parts = new List<String>();
        for (String k : order) {
            parts.add(counts.get(k) + ' ' + k);
        }
        return parts.isEmpty() ? 'nothing to sync' : String.join(parts, ', ');
    }

    /**
     * @description Parses a JSON object, or returns an empty map.
     * @param body the JSON
     * @return the object
     */
    public static Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object o = JSON.deserializeUntyped(body);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    /**
     * @description A value as text, or null.
     * @param value the value
     * @return the text
     */
    public static String str(Object value) {
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value);
    }

    private static Integer num(Object value) {
        if (value == null) {
            return 0;
        }
        try {
            return Decimal.valueOf(String.valueOf(value)).intValue();
        } catch (Exception e) {
            return 0;
        }
    }
}
