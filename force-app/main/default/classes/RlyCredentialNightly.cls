/**
 * @description The Credentials dashboard's nightly refresh (build 49), in the pipeline's nightly archive call
 * (RlyArchiveNightly, POST /rly/archive). The first call of the night (no runId) runs the checks before the archive pass
 * touches anything: checkFirst makes every callout, the archive pass does its DML, then saveAfter saves the rows and adds
 * "credentials" to the answer. Only in the production hub and for the pipeline's admin user, like the archive. Never
 * throws: a failed check never stops the archive.
 */
public with sharing class RlyCredentialNightly {

    /**
     * @description The checks (callouts only), on the night's first call.
     * @param body the call's body ({"runUrl", "runId"})
     * @return the pass to save after the archive, or null when this call doesn't check
     */
    public static RlyCredentialCheck.Pass checkFirst(String body) {
        try {
            if (!isFirstCall(body) || !RlyArchiveService.onHub() || !RlyOrgController.isAdmin()) {
                return null;
            }
            return RlyCredentialCheck.gather();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Saves the pass and says what it found in the answer.
     * @param p the pass, or null
     * @param answer the archive call's answer
     */
    public static void saveAfter(RlyCredentialCheck.Pass p, Map<String, Object> answer) {
        if (p == null || answer == null) {
            return;
        }
        try {
            RlyCredentialCheck.save(p);
            answer.put('credentials', RlyCredentialCheck.summary(p));
        } catch (Exception e) {
            answer.put('credentials', 'Not saved: ' + e.getMessage());
        }
    }

    /**
     * @description Whether this is the night's first call: it sends no runId (build 55: the package read uses it too).
     * @param body the call's body
     * @return true for the first call
     */
    public static Boolean isFirstCall(String body) {
        if (String.isBlank(body)) {
            return true;
        }
        try {
            Object o = JSON.deserializeUntyped(body);
            Object runId = o instanceof Map<String, Object> ? ((Map<String, Object>) o).get('runId') : null;
            return !(runId instanceof String) || String.isBlank((String) runId);
        } catch (Exception e) {
            return true;
        }
    }
}
