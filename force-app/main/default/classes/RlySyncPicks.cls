/**
 * @description Sync status: checks what the page picked for a back promote or push (RlySyncPromote) and writes it for the
 * pipeline (RLY_Release__c.Sync_Paths__c: keys, paths, branchOnly).
 */
public with sharing class RlySyncPicks {

    /** @description Most components one pick takes. */
    public static final Integer MAX_PICKS = 2000;

    private static final Pattern KEY_PATTERN = Pattern.compile('^[A-Za-z0-9]{2,80}:[^,\\r\\n]{1,255}$');

    /**
     * @description Checks a pick: components (Type:Name, up to MAX_PICKS) and their files (repo paths).
     * @param pick the pick
     */
    public static void check(RlySyncPromote.Pick pick) {
        if (isEmpty(pick)) {
            throw new RlyReleaseException('Pick at least one component.');
        }
        if (pick.keys.size() > MAX_PICKS || pick.paths.size() > MAX_PICKS * 4) {
            throw new RlyReleaseException('Pick at most ' + MAX_PICKS + ' components at a time.');
        }
        checkKeys(pick.keys);
        checkPaths(pick.paths);
    }

    /**
     * @description The picks for the pipeline; null (everything) unless something was picked or the org only takes
     * its branch.
     * @param pick the pick, or null for everything
     * @param lower the org that gets the files (a developer org gets its branch only: no deploy)
     * @return the JSON, or null
     */
    public static String serialized(RlySyncPromote.Pick pick, RLY_Org__c lower) {
        Boolean branchOnly = !RlySyncRoute.hasSignIn(lower);
        if (pick == null && !branchOnly) {
            return null;
        }
        Map<String, Object> m = new Map<String, Object>{ 'branchOnly' => branchOnly };
        if (pick != null) {
            m.put('keys', pick.keys);
            m.put('paths', pick.paths);
        }
        String json = JSON.serialize(m);
        if (json.length() > 131072) {
            throw new RlyReleaseException('Too many files picked for one back promote: pick fewer components.');
        }
        return json;
    }

    /**
     * @description What the page sent.
     * @param pickJson {higherOrgId, lowerOrgId, keys, paths}
     * @return the pick, or null
     */
    public static RlySyncPromote.Pick parse(String pickJson) {
        try {
            return String.isBlank(pickJson) ? null : (RlySyncPromote.Pick) JSON.deserialize(pickJson, RlySyncPromote.Pick.class);
        } catch (JSONException e) {
            throw new RlyReleaseException('The picked components couldn\'t be read.');
        }
    }

    private static Boolean isEmpty(RlySyncPromote.Pick pick) {
        return pick == null || pick.keys == null || pick.keys.isEmpty() || pick.paths == null || pick.paths.isEmpty();
    }

    private static void checkKeys(List<String> keys) {
        for (String k : keys) {
            if (k == null || !KEY_PATTERN.matcher(k).matches()) {
                throw new RlyReleaseException('"' + k + '" isn\'t Type:Name.');
            }
        }
    }

    private static void checkPaths(List<String> paths) {
        for (String p : paths) {
            Boolean unsafe = String.isBlank(p) || p.contains('..') || p.startsWith('/') || p.startsWith('.github') || p.length() > 400;
            if (unsafe) {
                throw new RlyReleaseException('"' + p + '" isn\'t a file the pipeline can bring.');
            }
        }
    }
}
