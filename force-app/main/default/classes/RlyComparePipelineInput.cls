/**
 * @description Compare in the pipeline: checks what the page sends (RlyComparePipeline) and the Git connection it
 * needs (connected, on GitHub: the other providers have no compare job yet).
 */
public with sharing class RlyComparePipelineInput {

    private static final Pattern COMPARE_ID = Pattern.compile('^(CMP|SYN)-\\d{13}$');
    private static final Pattern KEY = Pattern.compile('^[A-Za-z]{2,80}:[^,:\\r\\n]{1,255}$');
    private static final Integer MAX_INPUT = 60000;

    /**
     * @description Checks a compare's id.
     * @param compareId CMP- and 13 digits
     */
    public static void checkId(String compareId) {
        if (String.isBlank(compareId) || !COMPARE_ID.matcher(compareId).matches()) {
            throw new RlyReleaseException('A compare id is CMP- (or SYN- for a sync check) and 13 digits.');
        }
    }

    /**
     * @description Checks a part: its id, number and retrieve.
     * @param part the part
     */
    public static void checkPart(RlyComparePipeline.Part part) {
        Boolean numbered = part != null && part.n != null && part.n >= 1 && part.n <= RlyComparePipeline.MAX_PARTS;
        if (!numbered || String.isBlank(part.retrieveId)) {
            throw new RlyReleaseException('That part of the compare isn\'t valid.');
        }
        checkId(part.compareId);
    }

    /**
     * @description Checks a compare before its run starts: id, components (Type:Name, 1 to MAX_KEYS) and parts.
     * @param job the compare
     */
    public static void checkRun(RlyComparePipeline.RunJob job) {
        if (job == null) {
            throw new RlyReleaseException('Nothing to compare.');
        }
        checkId(job.compareId);
        List<String> keys = orEmpty(job.keys);
        List<String> all = new List<String>(keys);
        all.addAll(orEmpty(job.deleted));
        if (all.isEmpty() || all.size() > RlyComparePipeline.MAX_KEYS) {
            throw new RlyReleaseException('Compare 1 to ' + RlyComparePipeline.MAX_KEYS + ' components in the pipeline.');
        }
        checkKeys(all);
        checkParts(job.parts, keys.isEmpty());
        if (RlyComparePipeline.joined(keys).length() > MAX_INPUT || RlyComparePipeline.joined(job.deleted).length() > MAX_INPUT) {
            throw new RlyReleaseException('Too many components for one compare in the pipeline: split the release.');
        }
    }

    /**
     * @description The hub's Git connection, checked: connected, on GitHub.
     * @return the provider
     */
    public static RlyGit gitHub() {
        return gitHubFor(null);
    }

    /**
     * @description An org's Git connection, checked: connected, on GitHub (build 45: the org's own repository).
     * @param orgId the org (blank: the hub's main connection)
     * @return the provider
     */
    public static RlyGit gitHubFor(Id orgId) {
        RLY_Git_Connection__c conn = orgId == null ? RlyReleaseStore.git() : RlyReleaseStore.gitForOrg(orgId);
        if (conn == null || conn.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        if (conn.Provider__c != 'GitHub') {
            throw new RlyReleaseException(RlyComparePipeline.GITHUB_ONLY);
        }
        return RlyGit.forConnection(conn);
    }

    // Each component is Type:Name, as the pipeline reads it.
    private static void checkKeys(List<String> keys) {
        for (String k : keys) {
            if (k == null || !KEY.matcher(k).matches()) {
                throw new RlyReleaseException('"' + k + '" isn\'t Type:Name.');
            }
        }
    }

    // Parts sent: at least one when the release brings components (deletions alone need none).
    private static void checkParts(Integer parts, Boolean onlyDeletions) {
        Boolean ok = parts != null && parts >= 0 && parts <= RlyComparePipeline.MAX_PARTS && (parts > 0 || onlyDeletions);
        if (!ok) {
            throw new RlyReleaseException('Send every part of the compare first.');
        }
    }

    private static List<String> orEmpty(List<String> values) {
        return values == null ? new List<String>() : values;
    }
}
