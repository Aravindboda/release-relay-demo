/**
 * @description The pipeline side of a release: its branch, the run title the pipeline gives each run, the
 * inputs a run starts with, and the result files each step writes to the results branch.
 */
public with sharing class RlyPipelineRun {

    /** @description The branch the pipeline writes result files to. */
    public static final String RESULTS_BRANCH = 'release-relay-results';
    /** @description Pending_Run__c of a check run started because the target moved after the checks passed (mode check). */
    public static final String RECHECK = 'recheck';

    /**
     * @description The release branch: feature/rel-00001, hotfix/rel-00001 for a hotfix, promote/rel-00001 for a promotion.
     * @param rel the release, with Release_Type__c and Is_Hotfix__c
     * @return the branch name
     */
    public static String branchName(RLY_Release__c rel) {
        String prefix = RlyHotfix.isHotfix(rel) ? 'hotfix/' : 'feature/';
        return (RlyPromotion.isPromotion(rel) ? 'promote/' : prefix) + rel.Name.toLowerCase();
    }

    /**
     * @description The title of the pipeline run the release is waiting for (a re-check runs in mode check).
     * @param rel the release, with Pending_Run__c
     * @return the run title
     */
    public static String runTitle(RLY_Release__c rel) {
        String runMode = rel.Pending_Run__c == RECHECK ? 'check' : rel.Pending_Run__c;
        return 'Release Relay ' + rel.Name + ' (' + runMode + ')';
    }

    /**
     * @description The pipeline's inputs; options (RlyPipelineOptions) carry the hub flag, the org label, the tests,
     * the scan switch, validateMerged, syncBranches and attempt; mode hub also sends the deletions. Each run gets a new token (Check_Token__c, saved by
     * the caller) that its result files echo as attempt.
     * @param rel the release
     * @param mode hub, promote, check, resolve, merge or sync
     * @param branch the release branch
     * @return the inputs
     */
    public static Map<String, String> inputs(RLY_Release__c rel, String mode, String branch) {
        rel.Check_Token__c = newToken();
        return new Map<String, String>{
            'request_id' => rel.Name, 'mode' => mode,
            'environment' => String.isBlank(rel.Source_Environment__c) ? 'release-relay' : rel.Source_Environment__c,
            'target_environment' => rel.Target_Environment__c == null ? '' : rel.Target_Environment__c,
            'branch' => branch, 'target' => rel.Target_Branch__c,
            'title' => (rel.Name + ': ' + rel.Title__c).left(200),
            'components' => components(rel, mode),
            'deletions' => deletions(rel, mode), 'options' => JSON.serialize(RlyPipelineOptions.forMode(rel, mode))
        };
    }

    /**
     * @description A new random run token.
     * @return 32 hex characters
     */
    public static String newToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }

    // hub: the release's deletions (Type:Name, comma separated); a promotion's are in its carried merge commits.
    private static String deletions(RLY_Release__c rel, String mode) {
        return mode == 'hub' ? String.join(RlyDeletions.of(rel), ',') : '';
    }

    // hub: the selected components (not the deletions); promote: the carried merge commits, oldest first; other modes: none.
    private static String components(RLY_Release__c rel, String mode) {
        if (mode == RlyPromotion.MODE) {
            return RlyCarried.mergeCommits(rel);
        }
        if (mode != 'hub') {
            return '';
        }
        List<String> names = new List<String>();
        for (RLY_Release_Item__c i : RlyReleaseStore.items(rel.Id)) {
            if (i.Is_Deletion__c != true) {
                names.add(i.Metadata_Type__c + ':' + i.Component_Name__c);
            }
        }
        return String.join(names, ',').left(60000);
    }

    /**
     * @description Finds the run the release is waiting for and links it on the release.
     * @param git the Git provider
     * @param rel the release
     * @return the run, or null when it hasn't started yet
     */
    public static RlyGit.Run findRun(RlyGit git, RLY_Release__c rel) {
        RlyGit.Run run = git.findRun(runTitle(rel));
        if (run != null) {
            rel.Run_ID__c = run.id.left(30);
            rel.Run_URL__c = run.url;
        }
        return run;
    }

    /**
     * @description A step's result file from the latest run: its attempt must be the release's token; a result without
     * attempt (an older pipeline script) must have finished after the latest run was requested.
     * @param git the Git provider
     * @param rel the release
     * @param step scan, validate, merge or deploy
     * @return the result, or null when there's none from the latest run
     */
    public static Map<String, Object> result(RlyGit git, RLY_Release__c rel, String step) {
        String raw = git.getFileRaw('results/' + rel.Name + '/' + step + '.json', RESULTS_BRANCH);
        if (String.isBlank(raw)) {
            return null;
        }
        Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(raw);
        return isFromEarlierRun(r, rel) ? null : r;
    }

    private static Boolean isFromEarlierRun(Map<String, Object> r, RLY_Release__c rel) {
        Object attempt = r.get('attempt');
        if (attempt != null && String.isNotBlank(rel.Check_Token__c)) {
            return !String.valueOf(attempt).equals(rel.Check_Token__c);
        }
        return finishedBeforeRequest(r, rel);
    }

    private static Boolean finishedBeforeRequest(Map<String, Object> r, RLY_Release__c rel) {
        Object finished = r.get('finishedAt');
        if (finished == null || rel.Checks_Requested__c == null) {
            return false;
        }
        Datetime at = (Datetime) JSON.deserialize('"' + String.valueOf(finished) + '"', Datetime.class);
        return at < rel.Checks_Requested__c.addMinutes(-2);
    }

    /**
     * @description A number from a result file.
     * @param o the value
     * @return the number, or null
     */
    public static Decimal toNumber(Object o) {
        return o == null ? null : Decimal.valueOf(String.valueOf(o));
    }
}
