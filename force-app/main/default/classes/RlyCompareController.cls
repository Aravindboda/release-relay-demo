/**
 * @description Compare on Review (before raising): what the developer org has now against the target branch.
 *   startCompare  starts a Metadata API retrieve of the components compare can show (RlyRetrieve, as raising does)
 *   checkCompare  answers done = false until it finishes, then the files of each component, both sides (RlyCompareRun)
 * The page splits a release into parts of up to 5 components and runs up to 3 parts at once, so each call reads one
 * small zip; a part that fails is tried again on its own.
 * Compare in the pipeline (big releases, or files too large for the hub; RlyComparePipeline, RlyComparePipelineResult):
 *   startPipelinePart  starts one part's retrieve (any type)
 *   stagePipelinePart  once that retrieve is done, commits its zip to the results branch (not decoded here)
 *   runPipelineCompare starts the pipeline in mode compare
 *   checkPipelineCompare reads its result (components and file numbers)
 *   pipelineCompareFile  reads one file's copies when it's opened
 * Callouts only, no DML. The page polls with a CSS countdown (no timers) and diffs the texts in the browser.
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
            throw RlyReleaseException.toAura(e);
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
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Compare in the pipeline: starts one part's retrieve.
     * @param sourceOrgId the developer org
     * @param keys the part's components, Type:Name (up to 25)
     * @return the retrieve's id
     */
    @AuraEnabled
    public static String startPipelinePart(Id sourceOrgId, List<String> keys) {
        try {
            RlyHubGuard.requireHub();
            RlyComparePipeline.gitHub();
            return RlyComparePipeline.startPart(sourceOrgId, keys);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Compare in the pipeline: checks a part's retrieve and, once done, commits its zip.
     * @param partJson {compareId, n, retrieveId, sourceOrgId}
     * @return done = false while the retrieve runs
     */
    @AuraEnabled
    public static RlyComparePipeline.PartState stagePipelinePart(String partJson) {
        try {
            RlyHubGuard.requireHub();
            RlyComparePipeline.Part part = String.isBlank(partJson) ? null
                : (RlyComparePipeline.Part) JSON.deserialize(partJson, RlyComparePipeline.Part.class);
            return RlyComparePipeline.stagePart(part);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Compare in the pipeline: starts the run once every part is sent.
     * @param jobJson {compareId, sourceOrgId, targetBranch, keys, deleted, parts}
     * @return the run's token and title
     */
    @AuraEnabled
    public static RlyComparePipeline.Started runPipelineCompare(String jobJson) {
        try {
            RlyHubGuard.requireHub();
            RlyComparePipeline.RunJob job = String.isBlank(jobJson) ? null
                : (RlyComparePipeline.RunJob) JSON.deserialize(jobJson, RlyComparePipeline.RunJob.class);
            if (job != null) {
                job.full = false; // a whole-org check starts only from the Sync status tab (RlySyncRuns)
            }
            return RlyComparePipeline.run(job);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Compare in the pipeline: reads the result.
     * @param compareId the compare's id
     * @param token the run's token
     * @return done = false until it's there
     */
    @AuraEnabled
    public static RlyComparePipelineResult.Result checkPipelineCompare(String compareId, String token) {
        try {
            RlyHubGuard.requireHub();
            return RlyComparePipelineResult.check(compareId, token);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Compare in the pipeline: one file's copies.
     * @param compareId the compare's id
     * @param n the file's number
     * @return the file
     */
    @AuraEnabled
    public static RlyCompareFiles.FileDiff pipelineCompareFile(String compareId, Integer n) {
        try {
            RlyHubGuard.requireHub();
            return RlyComparePipelineResult.file(compareId, n);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
