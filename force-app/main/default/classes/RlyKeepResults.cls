/**
 * @description Build 60: what the pipeline (version 34) says about lines, read when a validation result arrives.
 * D40: a raise or added changes write kept and removedOnPurpose in raise.json (lines the target branch had that the
 * developer org lacked: put back, or taken out as asked); they are kept on the validation result as raiseKept and
 * raiseRemoved, so the release page lists them under its pull request, and carried over when the checks run again.
 * D38: the validation writes orgDrift (changes the target org has that its branch doesn't) and maybe orgDriftNote;
 * orgDrift is kept on Org_Drift__c too, where approving reads it (RlyOrgDrift).
 */
public with sharing class RlyKeepResults {

    /** @description Where the raise's kept lines are kept on the validation result. */
    public static final String KEPT_KEY = 'raiseKept';
    /** @description Where the raise's lines taken out on purpose are kept on the validation result. */
    public static final String REMOVED_KEY = 'raiseRemoved';
    /** @description The validation result's key for the target org's own changes. */
    public static final String DRIFT_KEY = 'orgDrift';

    /**
     * @description A validation result arrived: adds the raise's lines (read once per raise) and keeps the drift.
     * @param rel the release, with Validation_Result__c still the previous result
     * @param git the Git provider
     * @param val the validation result (changed in place)
     */
    public static void onValidation(RLY_Release__c rel, RlyGit git, Map<String, Object> val) {
        if (val == null) {
            return;
        }
        Map<String, Object> raise = rel.Pending_Run__c == 'hub' ? RlyPipelineRun.result(git, rel, 'raise') : previous(rel);
        if (raise != null) {
            putList(val, KEPT_KEY, raise.containsKey('kept') ? raise.get('kept') : raise.get(KEPT_KEY));
            putList(val, REMOVED_KEY, raise.containsKey('removedOnPurpose') ? raise.get('removedOnPurpose') : raise.get(REMOVED_KEY));
        }
        List<Object> drift = asList(val.get(DRIFT_KEY));
        rel.Org_Drift__c = drift.isEmpty() ? null : JSON.serialize(drift).left(RlyKeepRules.MAX_CHARS);
    }

    // A check run again: the raise's lines from the result it replaces.
    private static Map<String, Object> previous(RLY_Release__c rel) {
        if (String.isBlank(rel.Validation_Result__c)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(rel.Validation_Result__c);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (JSONException e) {
            return null;
        }
    }

    private static void putList(Map<String, Object> val, String key, Object value) {
        List<Object> items = asList(value);
        if (!items.isEmpty()) {
            val.put(key, items);
        }
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }
}
