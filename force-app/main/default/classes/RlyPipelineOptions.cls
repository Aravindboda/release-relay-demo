/**
 * @description The options a pipeline run starts with (the options input, as JSON): the hub flag, the org label,
 * production (the target is production by its org record: isProduction),
 * the test classes, the scan switch (the target org's code scan choice, RlyScanRule), validateMerged (hub, promote, check and resolve: validate the release merged with
 * the target branch), stageBranch (promote: the stage's branch, whose files the next stop gets), append and appendZip
 * (hub, adding changes to an open release: RlyAppendInputs), attempt (the run's token, echoed in every result file) and syncBranches (the branches to update
 * from the target after the merge: every developer branch when the target is the first stage; after a merge into the
 * hub, every stage branch in route order, then every developer branch: the back-merge).
 */
public with sharing class RlyPipelineOptions {

    private static final Set<String> VALIDATE_MERGED_MODES = new Set<String>{ 'hub', RlyPromotion.MODE, 'check', 'resolve' };

    /**
     * @description The options for a run of the release.
     * @param rel the release, with Target_Org__c and Test_Classes__c
     * @param mode hub, promote, check, resolve, merge or sync
     * @return the options
     */
    public static Map<String, Object> forMode(RLY_Release__c rel, String mode) {
        List<String> tests = RlyDeletions.withoutDeletedTests(
            String.isBlank(rel.Test_Classes__c) ? new List<String>() : rel.Test_Classes__c.split(','), rel);
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'label' => rel.Org_Label__c, 'production' => isProduction(rel) };
        if (!runsLocalTests(rel, tests)) {
            options.put('tests', tests);
        }
        if (String.isNotBlank(rel.Check_Token__c)) {
            options.put('attempt', rel.Check_Token__c);
        }
        RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
        if (conn != null && !RlyScanRule.isOn(conn, RlyScanRule.targetOf(rel))) {
            options.put('scan', 'off');
        }
        if (VALIDATE_MERGED_MODES.contains(mode)) {
            options.put('validateMerged', true);
        }
        addModeOptions(rel, mode, options);
        RlyRunPeople.addTo(rel, options);
        return options;
    }

    // merge: the branches to update; promote: the stage's branch (the next stop gets each file as it is there);
    // hub adding to an open release: append and the zip (RlyAppendRun).
    private static void addModeOptions(RLY_Release__c rel, String mode, Map<String, Object> options) {
        if (mode == 'merge') {
            addSyncBranches(rel, options);
        } else if (mode == RlyPromotion.MODE) {
            String stageBranch = stageBranchOf(rel);
            if (String.isNotBlank(stageBranch)) {
                options.put('stageBranch', stageBranch.trim());
            }
        } else if (mode == 'hub') {
            RlyAppendInputs.addOptions(rel, options);
        } else if (mode == 'sync') {
            RlySyncPaths.addOptions(rel, options);
        }
    }

    /**
     * @description The branch of a promotion's stage (its source org), read again when the release was read without it.
     * @param rel the promotion
     * @return the branch, or null
     */
    public static String stageBranchOf(RLY_Release__c rel) {
        RLY_Org__c stage = (RLY_Org__c) rel.getPopulatedFieldsAsMap().get('Source_Org__r');
        if ((stage == null || !stage.getPopulatedFieldsAsMap().containsKey('Branch__c')) && rel.Source_Org__c != null) {
            stage = RlyReleaseStore.org(rel.Source_Org__c);
        }
        return stage == null ? null : stage.Branch__c;
    }

    // Deleting Apex or deploying triggers switched off in production needs tests: without tests of its own, such a
    // release into production sends no tests list, so the pipeline runs the local tests (RunLocalTests). Elsewhere it
    // sends an empty list (NoTestRun); pipeline version 17 decides the same from options.production and the files.
    private static Boolean runsLocalTests(RLY_Release__c rel, List<String> tests) {
        return tests.isEmpty() && isProduction(rel)
            && (RlyDeletions.deletesApex(rel) || !RlyTestRule.inactiveTriggers(rel).isEmpty());
    }

    /**
     * @description Whether the release's target org is production, from its Release Relay org record: the hub (role
     * Hub), or an org whose Environment is Production. Not the org's IsSandbox: a Developer Edition org reports as
     * production but takes deploys without tests.
     * @param rel the release, with Target_Org__r.Role__c (and Target_Org__r.Environment__c when read)
     * @return true when the target is production
     */
    public static Boolean isProduction(RLY_Release__c rel) {
        if (isHub(rel)) {
            return true;
        }
        Object env = rel.Target_Org__r == null ? null : rel.Target_Org__r.getPopulatedFieldsAsMap().get('Environment__c');
        return env != null && String.valueOf(env) == RlyOrgRoleCheck.ENV_PRODUCTION;
    }

    // A merge into the first stage brings the developer branches up to date; a merge into the hub every stage branch
    // and then every developer branch (merged back down).
    private static void addSyncBranches(RLY_Release__c rel, Map<String, Object> options) {
        Id connectionId = RlyReleaseStore.gitFor(rel)?.Id; // build 45: only the branches of the release's repository
        if (RlyProdSync.isProdSync(rel)) {
            return; // keeping another repository's prod in step brings nothing back down
        }
        List<String> branches = isHub(rel) ? backMergeBranches(connectionId)
            : isFirstStage(rel, connectionId) ? RlyConnectionRoutes.developerBranchesFor(connectionId) : new List<String>();
        if (!branches.isEmpty()) {
            options.put('syncBranches', branches);
        }
    }

    private static Boolean isHub(RLY_Release__c rel) {
        return rel.Target_Org__r != null && rel.Target_Org__r.Role__c == 'Hub';
    }

    private static Boolean isFirstStage(RLY_Release__c rel, Id connectionId) {
        RLY_Org__c firstStage = RlyConnectionRoutes.firstStageFor(connectionId);
        return firstStage != null && firstStage.Id == rel.Target_Org__c;
    }

    /**
     * @description The stage branches in route order (the hub left out), each once.
     * @return the branch names
     */
    public static List<String> stageBranches() {
        return stageBranchesFor(null);
    }

    /**
     * @description One Git connection's stage branches in route order (the hub left out), each once (build 45).
     * @param connectionId the connection (blank: the main one)
     * @return the branch names
     */
    public static List<String> stageBranchesFor(Id connectionId) {
        List<String> out = new List<String>();
        for (RLY_Org__c o : RlyRouteRules.ordered(RlyConnectionRoutes.routeOrgsFor(connectionId))) {
            if (o.Role__c == 'Stage' && String.isNotBlank(o.Branch__c) && !out.contains(o.Branch__c.trim())) {
                out.add(o.Branch__c.trim());
            }
        }
        return out;
    }

    // The back-merge after a deploy to the hub: stage branches in route order, then developer branches.
    private static List<String> backMergeBranches(Id connectionId) {
        List<String> out = stageBranchesFor(connectionId);
        for (String b : RlyConnectionRoutes.developerBranchesFor(connectionId)) {
            if (!out.contains(b)) {
                out.add(b);
            }
        }
        return out;
    }
}
