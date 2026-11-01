/**
 * @description Compare on Review (before raising): what the developer org has now against the target branch.
 *   startCompare  starts a Metadata API retrieve of the components compare can show (RlyRetrieve, as raising does)
 *   checkCompare  answers done = false until it finishes, then the files of each component, both sides (RlyCompareRun)
 * Callouts only, no DML. The page polls checkCompare every 2 seconds and diffs the texts in the browser.
 */
public with sharing class RlyCompareController {

    /**
     * @description Starts the retrieve of the components compare can show.
     * @param sourceOrgId the developer org
     * @param keys the components the release brings, Type:Name (up to 25)
     * @return the retrieve's id, or null when none of them needs retrieving
     */
    @AuraEnabled
    public static String startCompare(Id sourceOrgId, List<String> keys) {
        try {
            RlyHubGuard.requireHub();
            RlyCompareParts.checkKeys(keys);
            RLY_Org__c source = RlyRaiseRoute.source(sourceOrgId);
            Map<String, Set<String>> byType = new Map<String, Set<String>>();
            for (String k : keys) {
                String typeName = k.substringBefore(':');
                if (RlyCompareFiles.isSupported(typeName)) {
                    if (!byType.containsKey(typeName)) {
                        byType.put(typeName, new Set<String>());
                    }
                    byType.get(typeName).add(k.substringAfter(':'));
                }
            }
            return byType.isEmpty() ? null : RlyRetrieve.start(source, byType);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Checks a compare.
     * @param jobJson {retrieveId, sourceOrgId, keys, deleted, targetBranch, pendingPaths}
     * @return done = false while the retrieve runs; then the components and their files
     */
    @AuraEnabled
    public static RlyCompareRun.Result checkCompare(String jobJson) {
        try {
            RlyHubGuard.requireHub();
            RlyCompareRun.Job job = String.isBlank(jobJson) ? null : (RlyCompareRun.Job) JSON.deserialize(jobJson, RlyCompareRun.Job.class);
            return RlyCompareRun.check(job);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
