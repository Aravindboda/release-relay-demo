/**
 * @description The pipeline side of a release: its branch, the run title the pipeline gives each run, the
 * inputs a run starts with, and the result files each step writes to the results branch.
 */
public with sharing class RlyPipelineRun {

    /** @description The branch the pipeline writes result files to. */
    public static final String RESULTS_BRANCH = 'release-relay-results';

    /**
     * @description The release branch, for example feature/rel-00001.
     * @param rel the release
     * @return the branch name
     */
    public static String branchName(RLY_Release__c rel) {
        return 'feature/' + rel.Name.toLowerCase();
    }

    /**
     * @description The title of the pipeline run the release is waiting for.
     * @param rel the release, with Pending_Run__c
     * @return the run title
     */
    public static String runTitle(RLY_Release__c rel) {
        return 'Release Relay ' + rel.Name + ' (' + rel.Pending_Run__c + ')';
    }

    /**
     * @description The pipeline's inputs; options carry the hub flag, the org label, the tests and the scan switch.
     * @param rel the release
     * @param mode hub, check or merge
     * @param branch the release branch
     * @return the inputs
     */
    public static Map<String, String> inputs(RLY_Release__c rel, String mode, String branch) {
        return new Map<String, String>{
            'request_id' => rel.Name, 'mode' => mode,
            'environment' => String.isBlank(rel.Source_Environment__c) ? 'release-relay' : rel.Source_Environment__c,
            'target_environment' => rel.Target_Environment__c == null ? '' : rel.Target_Environment__c,
            'branch' => branch, 'target' => rel.Target_Branch__c,
            'title' => (rel.Name + ': ' + rel.Title__c).left(200),
            'components' => mode == 'hub' ? components(rel) : '',
            'deletions' => '', 'options' => JSON.serialize(options(rel))
        };
    }

    private static Map<String, Object> options(RLY_Release__c rel) {
        List<String> tests = String.isBlank(rel.Test_Classes__c) ? new List<String>() : rel.Test_Classes__c.split(',');
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'label' => rel.Org_Label__c, 'tests' => tests };
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn != null && conn.Code_Scan__c != true) {
            options.put('scan', 'off');
        }
        return options;
    }

    private static String components(RLY_Release__c rel) {
        List<String> names = new List<String>();
        for (RLY_Release_Item__c i : RlyReleaseStore.items(rel.Id)) {
            names.add(i.Metadata_Type__c + ':' + i.Component_Name__c);
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
     * @description A step's result file, when it was written after the latest run was requested.
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
