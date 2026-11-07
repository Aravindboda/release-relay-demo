/**
 * @description Flow activation a batch at a time (build 37). After a deploy, a release activates its chosen flows in
 * the org it went to (RlyFlowActivation): each flow is a read and an activation call, so a release with many flows could
 * run out of callouts or time in one read, and that error can't be caught (the whole read would roll back). Each read
 * now activates at most PER_READ flows: those without a result for that org in Flow_Results__c, which is the cursor. A
 * deployed release with flows still to activate keeps its page checking (pending) and the next read carries on
 * (continueAfterDeploy); the page shows progress ("Activating flows: 8 of 30").
 */
public with sharing class RlyFlowBatch {

    /** @description Most flows activated in one read. */
    public static final Integer PER_READ = 8;

    /**
     * @description The next flows to activate: chosen flows without a result for the org yet, at most PER_READ.
     * @param rel the release, with Flow_Results__c
     * @param orgName the target org's name (results are kept per org name)
     * @param chosen the flows the release activates
     * @return up to PER_READ flow names
     */
    public static List<String> nextNames(RLY_Release__c rel, String orgName, List<String> chosen) {
        Set<String> done = doneIn(rel, orgName);
        List<String> out = new List<String>();
        for (String n : chosen) {
            if (out.size() == PER_READ) {
                break;
            }
            if (!done.contains(n)) {
                out.add(n);
            }
        }
        return out;
    }

    /**
     * @description Whether a deployed release still has flows to activate (its page keeps checking).
     * @param rel the release, with Target_Org__r.Name, Flow_Actions__c and Flow_Results__c
     * @return true while some chosen flow has no result for the target org
     */
    public static Boolean hasPending(RLY_Release__c rel) {
        return counts(rel)[1] > 0;
    }

    /**
     * @description Progress for the page, while flows are left to activate.
     * @param rel the release
     * @return for example Activating flows: 8 of 30, or null when none are left
     */
    public static String progress(RLY_Release__c rel) {
        Integer[] c = counts(rel);
        return c[1] > 0 ? 'Activating flows: ' + (c[0] - c[1]) + ' of ' + c[0] : null;
    }

    /**
     * @description The next read of a deployed release with flows left: claims the read, activates the next batch and
     * saves. A release with nothing left, a sandbox copy of the hub, or a read shared with another viewer comes back as
     * it is.
     * @param rel the release, as read
     * @param freshFor the shared-read window in seconds
     * @return the release as saved
     */
    public static RLY_Release__c continueAfterDeploy(RLY_Release__c rel, Integer freshFor) {
        if (rel == null || rel.Source_Org__c == null || !hasPending(rel) || !RlyHubGuard.isHub()) {
            return rel;
        }
        if (RlySharedRead.isFresh(rel, freshFor) || !RlySharedRead.claim(rel.Id, freshFor)) {
            return RlyReleaseStore.release(rel.Id);
        }
        String oldStatus = rel.Status__c;
        RlyFlowActivation.afterRead(rel, oldStatus);
        rel.Last_Synced__c = System.now();
        return RlySharedRead.save(rel, oldStatus);
    }

    // [chosen, left]: the release's chosen flows and those without a result for the target org (0, 0 when not deployed).
    private static Integer[] counts(RLY_Release__c rel) {
        if (rel == null || rel.Status__c != 'Deployed' || rel.Target_Org__c == null || rel.Target_Org__r == null) {
            return new Integer[]{ 0, 0 };
        }
        List<String> chosen = RlyFlowActivation.namesFor(rel);
        if (chosen.isEmpty()) {
            return new Integer[]{ 0, 0 };
        }
        Set<String> done = doneIn(rel, rel.Target_Org__r.Name);
        if (done.isEmpty()) {
            // Nothing activated in this org yet: a release deployed before build 37 (or with activation off) is left
            // alone; the deploy's own read starts the first batch.
            return new Integer[]{ chosen.size(), 0 };
        }
        Integer left = 0;
        for (String n : chosen) {
            left += done.contains(n) ? 0 : 1;
        }
        return new Integer[]{ chosen.size(), left };
    }

    // The flows with a result (any status) for the org.
    private static Set<String> doneIn(RLY_Release__c rel, String orgName) {
        Set<String> done = new Set<String>();
        for (Object o : RlyFlowResults.parse(rel.Flow_Results__c)) {
            Map<String, Object> m = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            if (orgName != null && orgName.equals(String.valueOf(m.get('org')))) {
                done.add(String.valueOf(m.get('flow')));
            }
        }
        return done;
    }
}
