/**
 * @description Sync status: starts the checks (pipeline files v23) and records each as a check (RLY_Sync_Check__c).
 *   startOrg    a stage or the hub (the pipeline signs in): mode drift compares the org with its branch
 *               a developer org: the page lists its components and sends them in parts (RlyComparePipeline), then
 *               runDeveloper starts mode compare with full = true, which writes the same result
 *   startRoute  mode routediff: each branch on the route against the one below it (Git only)
 * Callouts first, then one save.
 */
public with sharing class RlySyncRuns {

    private static final Pattern SYNC_ID_PATTERN = Pattern.compile('^SYN-\\d{13}$');

    /** @description A started check, for the page. */
    public class Started {
        /** @description The check's id. */
        @AuraEnabled public String syncId;
        /** @description drift (the pipeline reads the org), parts (the page sends the org in parts) or routediff. */
        @AuraEnabled public String mode;
        /** @description The org (org checks). */
        @AuraEnabled public Id orgId;
    }

    /**
     * @description Starts an org check.
     * @param org the route org
     * @return the check; mode parts asks the page to send the developer org's components
     */
    public static Started startOrg(RLY_Org__c org) {
        Started s = new Started();
        s.syncId = newId('SYN-');
        s.orgId = org.Id;
        RLY_Sync_Check__c check = newCheck(s.syncId, RlySyncStore.KIND_ORG);
        check.Org__c = org.Id;
        check.Branch__c = org.Branch__c.trim();
        if (RlySyncRoute.hasSignIn(org)) {
            s.mode = 'drift';
            check.Run_Title__c = runTitle(s.syncId, 'drift');
            Dispatch d = new Dispatch(s.syncId, 'drift', check.Branch__c);
            d.title = 'Org vs branch: ' + org.Name;
            d.environment = org.Git_Environment__c;
            d.options.put('label', org.Name.left(40));
            d.options.put('attempt', check.Token__c);
            RlyComparePipeline.gitHub().startPipeline(d.inputs());
        } else {
            s.mode = 'parts';
        }
        RlySyncStore.save(check);
        return s;
    }

    /**
     * @description A developer org's check, once its parts are on the results branch (compare-inbox/<syncId>/n.zip):
     * starts mode compare with full = true under the check's id; the pipeline writes the check's result.
     * @param syncId the check (also the parts' id)
     * @param parts how many parts were sent
     * @param types the types the page listed (only their folders can be only on the branch)
     * @return the run's title
     */
    public static String runDeveloper(String syncId, Integer parts, List<String> types) {
        RLY_Sync_Check__c check = requireRunning(syncId, RlySyncStore.KIND_ORG);
        RlyComparePipeline.RunJob job = new RlyComparePipeline.RunJob();
        job.compareId = syncId;
        job.sourceOrgId = check.Org__c;
        job.parts = parts;
        job.full = true;
        job.syncId = syncId;
        job.attempt = check.Token__c;
        job.folders = foldersOf(RlyPathRules.forOrg(RlyReleaseStore.org(check.Org__c)), types);
        RlyComparePipeline.Started started = RlyComparePipeline.run(job);
        RlySyncStore.save(new RLY_Sync_Check__c(Sync_Id__c = syncId, Run_Title__c = started.runTitle));
        return started.runTitle;
    }

    /**
     * @description The source folders of the listed types (folder => type); objects when CustomObject was listed.
     * @param rules the org's folder rules (RlyPathRules)
     * @param types the listed types
     * @return the folders
     */
    public static Map<String, String> foldersOf(List<RlyPathRules.Rule> rules, List<String> types) {
        Set<String> listed = new Set<String>(types == null ? new List<String>() : types);
        Map<String, String> out = new Map<String, String>();
        for (RlyPathRules.Rule r : rules) {
            if (listed.contains(r.type) && String.isNotBlank(r.dir) && out.size() < RlyPathRules.MAX_RULES) {
                out.put(r.dir, r.type);
            }
        }
        if (listed.contains('CustomObject')) {
            out.put(RlyPathRules.OBJECTS, 'CustomObject');
        }
        return out;
    }

    /**
     * @description Starts the down-the-route check: every pair of the route, from the top down.
     * @param orgs the registered orgs with a branch
     * @return the check
     */
    public static Started startRoute(List<RLY_Org__c> orgs) {
        List<RlySyncRoute.Pair> pairs = RlySyncRoute.pairs(orgs);
        if (pairs.isEmpty()) {
            throw new RlyReleaseException('The route needs at least two orgs with a branch (Pipeline tab).');
        }
        Started s = new Started();
        s.syncId = newId('SYN-');
        s.mode = 'routediff';
        RLY_Sync_Check__c check = newCheck(s.syncId, RlySyncStore.KIND_ROUTE);
        check.Run_Title__c = runTitle(s.syncId, 'routediff');
        List<String> route = new List<String>();
        List<Object> pairList = new List<Object>();
        for (RlySyncRoute.Pair p : pairs) {
            pairList.add(new List<String>{ p.higher.Branch__c.trim(), p.lower.Branch__c.trim() });
            addOnce(route, p.higher.Branch__c.trim());
        }
        addOnce(route, pairs[pairs.size() - 1].lower.Branch__c.trim());
        Dispatch d = new Dispatch(s.syncId, 'routediff', route[0]);
        d.title = 'Down the route';
        d.options.putAll(new Map<String, Object>{ 'route' => route, 'pairs' => pairList, 'attempt' => check.Token__c });
        RlyComparePipeline.gitHub().startPipeline(d.inputs());
        RlySyncStore.save(check);
        return s;
    }

    /**
     * @description The check, refused unless it is running and of this kind.
     * @param syncId the check
     * @param kind Org, Route or Packages
     * @return the check
     */
    public static RLY_Sync_Check__c requireRunning(String syncId, String kind) {
        checkId(syncId);
        RLY_Sync_Check__c check = RlySyncStore.bySyncId(syncId);
        if (check == null || check.Kind__c != kind || check.Status__c != RlySyncStore.RUNNING) {
            throw new RlyReleaseException('That check isn\'t running any more: check again.');
        }
        return check;
    }

    /**
     * @description Checks a whole-org compare for a check: its parts sent under the check's id, the folders read.
     * @param job the compare (full = true)
     */
    public static void checkWhole(RlyComparePipeline.RunJob job) {
        checkId(job.syncId);
        if (job.compareId != job.syncId) {
            throw new RlyReleaseException('A sync check sends its parts under its own id.');
        }
        if (!inRange(job.parts, 1, RlyComparePipeline.MAX_PARTS)) {
            throw new RlyReleaseException('Send every part of the org first.');
        }
        if (!inRange(job.folders == null ? 0 : job.folders.size(), 1, RlyPathRules.MAX_RULES)) {
            throw new RlyReleaseException('Say which folders were read (1 to ' + RlyPathRules.MAX_RULES + ').');
        }
    }

    private static Boolean inRange(Integer n, Integer low, Integer high) {
        return n != null && n >= low && n <= high;
    }

    /**
     * @description Checks a check's id.
     * @param syncId SYN- and 13 digits
     */
    public static void checkId(String syncId) {
        if (String.isBlank(syncId) || !SYNC_ID_PATTERN.matcher(syncId).matches()) {
            throw new RlyReleaseException('A sync check id is SYN- and 13 digits.');
        }
    }

    /**
     * @description The run's title on GitHub (the workflow's run-name).
     * @param requestId the request id
     * @param mode the mode
     * @return Release Relay <id> (<mode>)
     */
    public static String runTitle(String requestId, String mode) {
        return 'Release Relay ' + requestId + ' (' + mode + ')';
    }

    private static RLY_Sync_Check__c newCheck(String syncId, String kind) {
        return new RLY_Sync_Check__c(Sync_Id__c = syncId, Kind__c = kind, Status__c = RlySyncStore.RUNNING,
            Token__c = RlyPipelineRun.newToken(), Checked_At__c = System.now());
    }

    /** @description One run to start: the workflow inputs of a sync check. */
    private class Dispatch {
        private String syncId;
        private String mode;
        private String target;
        /** @description The run's title. */
        public String title = '';
        /** @description The GitHub environment (drift signs in through it). */
        public String environment = '';
        /** @description The options JSON's values. */
        public Map<String, Object> options = new Map<String, Object>{ 'hub' => true };

        /**
         * @description A run.
         * @param syncId the check
         * @param mode drift or routediff
         * @param target the branch
         */
        public Dispatch(String syncId, String mode, String target) {
            this.syncId = syncId;
            this.mode = mode;
            this.target = target;
        }

        /**
         * @description The workflow_dispatch inputs.
         * @return the inputs
         */
        public Map<String, String> inputs() {
            return new Map<String, String>{
                'request_id' => syncId, 'mode' => mode, 'environment' => String.isBlank(environment) ? '' : environment,
                'target_environment' => '', 'branch' => '', 'target' => target, 'title' => title.left(200),
                'components' => '', 'deletions' => '', 'options' => JSON.serialize(options)
            };
        }
    }

    /**
     * @description A new run id: the prefix and the time in milliseconds (sync checks SYN-, data runs DAT-).
     * @param prefix the prefix
     * @return the id
     */
    public static String newId(String prefix) {
        return prefix + String.valueOf(System.now().getTime()).leftPad(13, '0');
    }

    private static void addOnce(List<String> values, String value) {
        if (!values.contains(value)) {
            values.add(value);
        }
    }
}
