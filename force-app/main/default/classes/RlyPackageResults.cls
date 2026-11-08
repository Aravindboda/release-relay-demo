/**
 * @description Build 55: what the pipeline did with package references (result packages: kept, leftOut,
 * componentsLeftOut), read once per run when its result arrives, and one "Package references" History event per run:
 * "Kept 3 (ns1) from <target branch> · Left out in <org>: 2 (ns2), 1 component". A raise or added changes (mode hub) writes kept in
 * raise.json: it is read with the validation result (one more file read, only when the run had packages) and kept on
 * Validation_Result__c as raisePackages, so the release page shows it in the Validation line.
 */
public with sharing class RlyPackageResults {

    /** @description Event_Type__c of the History event. */
    public static final String EVENT = 'Package_References';
    /** @description The result key the pipeline writes. */
    public static final String KEY = 'packages';
    /** @description Where the raise's packages are kept on the validation result. */
    public static final String RAISE_KEY = 'raisePackages';

    /**
     * @description A validation result arrived: for a raise or added changes, the raise's kept references are read and
     * kept on the result; then the History event.
     * @param rel the release
     * @param git the Git provider
     * @param val the validation result (changed in place)
     */
    public static void onValidation(RLY_Release__c rel, RlyGit git, Map<String, Object> val) {
        if (val == null) {
            return;
        }
        Map<String, Object> raised = null;
        if (rel.Pending_Run__c == 'hub' && RlyOrgPackages.knownOf(RlyOrgPackageStore.orgs()).size() > 0) {
            Map<String, Object> raise = RlyPipelineRun.result(git, rel, 'raise');
            raised = raise == null ? null : asMap(raise.get(KEY));
            if (raised != null) {
                val.put(RAISE_KEY, raised);
            }
        }
        record(rel, raised, asMap(val.get(KEY)));
    }

    /**
     * @description A deploy (or back promote sync) result arrived: the History event for what was left out.
     * @param rel the release
     * @param result the result
     */
    public static void onDeploy(RLY_Release__c rel, Map<String, Object> result) {
        if (result != null) {
            record(rel, null, asMap(result.get(KEY)));
        }
    }

    /**
     * @description Adds the History event when the pipeline kept or left out anything.
     * @param rel the release
     * @param raised the raise's packages (kept), or null
     * @param deployed the validation's or deploy's packages (leftOut, componentsLeftOut), or null
     */
    public static void record(RLY_Release__c rel, Map<String, Object> raised, Map<String, Object> deployed) {
        List<String> parts = new List<String>();
        String kept = keptText(raised, rel.Target_Branch__c);
        String left = leftOutText(deployed, targetName(rel));
        if (kept != null) {
            parts.add(kept);
        }
        if (left != null) {
            parts.add(left);
        }
        if (!parts.isEmpty()) {
            RlyReleaseLog.add(rel, EVENT, String.join(parts, ' · ')).inOrg(rel.Target_Org__c)
                .withReference((String) rel.getPopulatedFieldsAsMap().get('Run_URL__c'));
        }
    }

    /**
     * @description What a raise kept, or null.
     * @param raised the raise's packages, or null
     * @param branch the branch references were kept from (the target branch)
     * @return for example "Kept 3 (ns1) from <target branch>"
     */
    public static String keptText(Map<String, Object> raised, String branch) {
        String kept = counts(raised == null ? null : raised.get('kept'));
        return kept == null ? null : 'Kept ' + kept + (String.isBlank(branch) ? '' : ' from ' + branch);
    }

    /**
     * @description What a validation or deploy left out of the org, or null.
     * @param deployed the validation's or deploy's packages, or null
     * @param orgName the org references were left out in
     * @return for example "Left out in <org>: 2 (ns2), 1 component"
     */
    public static String leftOutText(Map<String, Object> deployed, String orgName) {
        if (deployed == null) {
            return null;
        }
        List<String> what = new List<String>();
        String left = counts(deployed.get('leftOut'));
        if (left != null) {
            what.add(left);
        }
        Integer components = deployed.get('componentsLeftOut') instanceof List<Object> ? ((List<Object>) deployed.get('componentsLeftOut')).size() : 0;
        if (components > 0) {
            what.add(components + (components == 1 ? ' component' : ' components'));
        }
        return what.isEmpty() ? null : 'Left out in ' + (String.isBlank(orgName) ? 'the target' : orgName) + ': ' + String.join(what, ', ');
    }

    // {"ns1": 3, "ns2": 2} as "5 (ns1 3, ns2 2)", or "3 (ns1)" for one namespace; null when empty.
    private static String counts(Object o) {
        Map<String, Object> m = asMap(o);
        if (m == null || m.isEmpty()) {
            return null;
        }
        List<String> names = new List<String>(m.keySet());
        names.sort();
        Integer total = 0;
        List<String> each = new List<String>();
        for (String ns : names) {
            Integer n = toInt(m.get(ns));
            total += n;
            each.add(ns + ' ' + n);
        }
        if (total == 0) {
            return null;
        }
        return total + ' (' + (names.size() == 1 ? names[0] : String.join(each, ', ')) + ')';
    }

    private static Integer toInt(Object o) {
        try {
            return o == null ? 0 : Integer.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return 0;
        }
    }

    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
    }

    // The target org's name when the release was read with it.
    private static String targetName(RLY_Release__c rel) {
        Object target = rel.getPopulatedFieldsAsMap().get('Target_Org__r');
        return target instanceof RLY_Org__c ? (String) ((RLY_Org__c) target).getPopulatedFieldsAsMap().get('Name') : null;
    }
}
