/**
 * @description The options a pipeline run starts with (the options input, as JSON): the hub flag, the org label,
 * the test classes, the scan switch, validateMerged (hub, check and resolve: validate the release merged with the
 * target branch), attempt (the run's token, echoed in every result file) and syncBranches (the branches to update from the target after the merge: every developer branch
 * when the target is the first stage; for a hotfix, the source stage's branch and every developer branch).
 */
public with sharing class RlyPipelineOptions {

    private static final Set<String> VALIDATE_MERGED_MODES = new Set<String>{ 'hub', 'check', 'resolve' };

    /**
     * @description The options for a run of the release.
     * @param rel the release, with Target_Org__c and Test_Classes__c
     * @param mode hub, check, resolve or merge
     * @return the options
     */
    public static Map<String, Object> forMode(RLY_Release__c rel, String mode) {
        List<String> tests = String.isBlank(rel.Test_Classes__c) ? new List<String>() : rel.Test_Classes__c.split(',');
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'label' => rel.Org_Label__c, 'tests' => tests };
        if (String.isNotBlank(rel.Check_Token__c)) {
            options.put('attempt', rel.Check_Token__c);
        }
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn != null && conn.Code_Scan__c != true) {
            options.put('scan', 'off');
        }
        if (VALIDATE_MERGED_MODES.contains(mode)) {
            options.put('validateMerged', true);
        }
        if (mode == 'merge') {
            addSyncBranches(rel, options);
        }
        return options;
    }

    // A merge into the first stage brings the developer branches up to date; a hotfix also its source stage's branch.
    private static void addSyncBranches(RLY_Release__c rel, Map<String, Object> options) {
        List<String> branches = RlyHotfix.isHotfix(rel) ? hotfixBranches(rel)
            : isFirstStage(rel) ? RlyReleaseStore.developerBranches() : new List<String>();
        if (!branches.isEmpty()) {
            options.put('syncBranches', branches);
        }
    }

    private static Boolean isFirstStage(RLY_Release__c rel) {
        RLY_Org__c firstStage = RlyReleaseStore.firstStage();
        return firstStage != null && firstStage.Id == rel.Target_Org__c;
    }

    private static List<String> hotfixBranches(RLY_Release__c rel) {
        List<String> out = new List<String>();
        String stageBranch = rel.Source_Org__r.Branch__c;
        if (String.isNotBlank(stageBranch)) {
            out.add(stageBranch.trim());
        }
        for (String b : RlyReleaseStore.developerBranches()) {
            if (!out.contains(b)) {
                out.add(b);
            }
        }
        return out;
    }
}
