/**
 * @description "Why checks fail" on the Metrics tab: reads a few releases' latest check results (the page sends at most
 * MAX_PER_CALL release Ids per call, from RlyMetricsFlow's list) and sorts each into one reason, with the files in any
 * conflict. A release whose checks have passed since says "Fixed since". Code scan failures are counted from the history
 * by RlyMetricsFlow.
 */
public with sharing class RlyMetricsChecks {

    /** @description The most releases one call reads. */
    public static final Integer MAX_PER_CALL = 10;
    /** @description The reasons, in the order the chart shows them. */
    public static final List<String> REASONS = new List<String>{ 'Test failures', 'Deploy errors', 'Conflicts with the branch',
        'Quality gates', 'Code coverage', 'Fixed since', 'Other' };

    /**
     * @description Sorts some releases' failed checks into reasons.
     * @param releaseIds the releases (at most MAX_PER_CALL)
     * @return the reasons and the conflict files of this part
     */
    public static RlyMetricsViews.Reasons read(List<Id> releaseIds) {
        Map<String, Integer> reasons = new Map<String, Integer>();
        Map<String, Integer> files = new Map<String, Integer>();
        for (RLY_Release__c r : RlyMetricsStore.results(checked(releaseIds))) {
            Map<String, Object> result = parsed(r.Validation_Result__c);
            bump(reasons, reasonOf(r, result));
            addFiles(files, result);
        }
        RlyMetricsViews.Reasons out = new RlyMetricsViews.Reasons();
        out.reasons = bars(reasons);
        out.files = bars(files);
        return out;
    }

    // Release Ids only, at most MAX_PER_CALL.
    private static Set<Id> checked(List<Id> releaseIds) {
        Set<Id> ids = new Set<Id>();
        for (Id i : releaseIds == null ? new List<Id>() : releaseIds) {
            if (i != null && i.getSobjectType() == RLY_Release__c.SObjectType) {
                ids.add(i);
            }
        }
        if (ids.size() > MAX_PER_CALL) {
            throw new RlyReleaseException('Read at most ' + MAX_PER_CALL + ' releases at a time.');
        }
        return ids;
    }

    // The files in a result's conflicts (file name only).
    private static void addFiles(Map<String, Integer> files, Map<String, Object> result) {
        for (Object c : listOf(result.get('conflicts'))) {
            Object file = c instanceof Map<String, Object> ? ((Map<String, Object>) c).get('file') : null;
            if (file != null) {
                bump(files, String.valueOf(file).substringAfterLast('/'));
            }
        }
    }

    /**
     * @description One release's reason, from its latest check result.
     * @param r the release
     * @param result its Validation_Result__c, parsed
     * @return one of REASONS
     */
    public static String reasonOf(RLY_Release__c r, Map<String, Object> result) {
        if (r.Validation_Status__c == 'Passed') {
            return 'Fixed since';
        }
        Map<String, Object> gates = result.get('gates') instanceof Map<String, Object> ? (Map<String, Object>) result.get('gates') : null;
        if (!listOf(result.get('conflicts')).isEmpty()) {
            return 'Conflicts with the branch';
        }
        if (gates != null && gates.get('passed') == false) {
            return 'Quality gates';
        }
        if (!listOf(result.get('testFailures')).isEmpty()) {
            return 'Test failures';
        }
        if (!listOf(result.get('componentErrors')).isEmpty()) {
            return 'Deploy errors';
        }
        return listOf(result.get('coverageWarnings')).isEmpty() ? 'Other' : 'Code coverage';
    }

    private static List<RlyMetricsViews.Bar> bars(Map<String, Integer> counts) {
        List<RlyMetricsViews.Bar> out = new List<RlyMetricsViews.Bar>();
        for (String k : counts.keySet()) {
            RlyMetricsViews.Bar b = new RlyMetricsViews.Bar();
            b.label = k;
            b.value = counts.get(k);
            out.add(b);
        }
        return out;
    }

    private static void bump(Map<String, Integer> counts, String key) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }

    private static List<Object> listOf(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    private static Map<String, Object> parsed(String json) {
        if (String.isBlank(json)) {
            return new Map<String, Object>();
        }
        try {
            Object o = System.JSON.deserializeUntyped(json);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        } catch (JSONException e) {
            return new Map<String, Object>();
        }
    }
}
