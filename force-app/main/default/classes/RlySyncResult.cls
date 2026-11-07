/**
 * @description Sync status: reads a check's result from the results branch (pipeline files v23) and keeps the check's
 * status and counts current.
 *   read  results/SYN-…/drift.json (Org) or route.json (Route) once it is there and from this check's run (attempt =
 *         the check's token); while it isn't, the run's link and state; a run that ended without it fails the check
 *   file  results/SYN-…/f/n.json when a component's file is opened: both copies, or a unified diff for a large file
 */
public with sharing class RlySyncResult {

    /** @description One file of a component. */
    public class SyncFile {
        /** @description The repo path. */
        @AuraEnabled public String path;
        /** @description new, deleted or changed. */
        @AuraEnabled public String status;
        /** @description Its number, to open it (null: nothing to show). */
        @AuraEnabled public Integer n;
        /** @description text or patch. */
        @AuraEnabled public String kind;
        /** @description Why there's nothing to show. */
        @AuraEnabled public String reason;
    }

    /** @description One component that differs. */
    public class SyncComponent {
        /** @description Type:Name. */
        @AuraEnabled public String key;
        /** @description The type. */
        @AuraEnabled public String type;
        /** @description The name. */
        @AuraEnabled public String name;
        /** @description onlyInOrg, onlyOnBranch or different (Org); onlyInHigher or different (Route). */
        @AuraEnabled public String status;
        /** @description Who changed it last in the org, when the pipeline knows. */
        @AuraEnabled public String lastChangedBy;
        /** @description When it changed last in the org. */
        @AuraEnabled public String lastChangedAt;
        /** @description Route: the lower branch changed the same file too. */
        @AuraEnabled public Boolean lowerChangedToo = false;
        /** @description Route: the release or commit it came from. */
        @AuraEnabled public String cameFrom;
        /** @description Its files. */
        @AuraEnabled public List<SyncFile> files = new List<SyncFile>();
    }

    /** @description Route: one pair. */
    public class SyncPair {
        /** @description The higher branch. */
        @AuraEnabled public String higher;
        /** @description The lower branch. */
        @AuraEnabled public String lower;
        /** @description How many components the higher branch has that the lower one doesn't. */
        @AuraEnabled public Integer count = 0;
        /** @description Those components. */
        @AuraEnabled public List<SyncComponent> components = new List<SyncComponent>();
    }

    /** @description A check as the page shows it. */
    public class View {
        /** @description The check's id. */
        @AuraEnabled public String syncId;
        /** @description Org, Route or Packages. */
        @AuraEnabled public String kind;
        /** @description Running, Succeeded or Failed. */
        @AuraEnabled public String status;
        /** @description The result is there (or the check failed). */
        @AuraEnabled public Boolean done = false;
        /** @description Why it failed. */
        @AuraEnabled public String message;
        /** @description The run on GitHub. */
        @AuraEnabled public String runUrl;
        /** @description The run's GitHub state while it goes. */
        @AuraEnabled public String runStatus;
        /** @description When the check started. */
        @AuraEnabled public Datetime checkedAt;
        /** @description Its run has started (a developer org's check starts once its parts are sent). */
        @AuraEnabled public Boolean started = false;
        /** @description Org checks: the org. */
        @AuraEnabled public Id orgId;
        /** @description Org checks: the branch. */
        @AuraEnabled public String branch;
        /** @description Org: onlyInOrg, onlyOnBranch, different. */
        @AuraEnabled public Map<String, Integer> counts = new Map<String, Integer>();
        /** @description The result was cut at the pipeline's limit. */
        @AuraEnabled public Boolean truncated = false;
        /** @description Org: the components that differ. */
        @AuraEnabled public List<SyncComponent> components = new List<SyncComponent>();
        /** @description Route: the pairs. */
        @AuraEnabled public List<SyncPair> pairs = new List<SyncPair>();
    }

    /**
     * @description Reads a check: its result once it's there, else the run's state.
     * @param syncId the check
     * @return the check
     */
    public static View read(String syncId) {
        RlySyncRuns.checkId(syncId);
        RLY_Sync_Check__c check = RlySyncStore.bySyncId(syncId);
        if (check == null) {
            throw new RlyReleaseException('That check isn\'t here any more: check again.');
        }
        View v = view(check);
        if (check.Kind__c == RlySyncStore.KIND_PACKAGES) {
            v.done = true;
            return v;
        }
        if (check.Status__c == RlySyncStore.FAILED || (check.Status__c == RlySyncStore.RUNNING && String.isBlank(check.Run_Title__c))) {
            v.done = check.Status__c == RlySyncStore.FAILED;
            return v;
        }
        RlyGit git = RlyComparePipelineInput.gitHubFor(check.Org__c); // build 45: an org check reads the org's repository
        Map<String, Object> result = RlySyncParse.parsed(git.getFileRaw('results/' + syncId + '/' + fileOf(check) + '.json', RlyPipelineRun.RESULTS_BRANCH));
        Boolean fromThisRun = result != null && check.Token__c != null && check.Token__c.equals(String.valueOf(result.get('attempt')));
        if (!fromThisRun) {
            watchRun(git, check, v);
            return v;
        }
        fill(v, check, result);
        return v;
    }

    /**
     * @description One file of a check's result.
     * @param syncId the check
     * @param n the file's number
     * @return the file
     */
    public static RlyCompareFiles.FileDiff file(String syncId, Integer n) {
        RlySyncRuns.checkId(syncId);
        if (n == null || n < 1 || n > 100000) {
            throw new RlyReleaseException('That file isn\'t part of the check.');
        }
        RLY_Sync_Check__c check = RlySyncStore.bySyncId(syncId);
        Map<String, Object> f = RlySyncParse.parsed(RlyComparePipelineInput.gitHubFor(check == null ? null : check.Org__c).getFileRaw('results/' + syncId + '/f/' + n + '.json',
            RlyPipelineRun.RESULTS_BRANCH));
        if (f == null) {
            throw new RlyReleaseException('That file isn\'t on the results branch any more: check again.');
        }
        RlyCompareFiles.FileDiff d = new RlyCompareFiles.FileDiff();
        d.n = n;
        d.path = RlySyncParse.text(f.get('path'));
        d.left = RlySyncParse.text(f.get('left'));
        d.right = RlySyncParse.text(f.get('right'));
        d.patch = RlySyncParse.text(f.get('patch'));
        d.status = d.patch != null ? RlyCompareFiles.CHANGED : RlyCompareParts.statusOf(d.left, d.right);
        return d;
    }

    /**
     * @description A check as saved (no result read).
     * @param check the check
     * @return the view
     */
    public static View view(RLY_Sync_Check__c check) {
        View v = new View();
        v.syncId = check.Sync_Id__c;
        v.kind = check.Kind__c;
        v.status = check.Status__c;
        v.message = check.Message__c;
        v.runUrl = check.Run_Url__c;
        v.checkedAt = check.Checked_At__c;
        v.started = String.isNotBlank(check.Run_Title__c);
        v.orgId = check.Org__c;
        v.branch = check.Branch__c;
        Map<String, Object> counts = RlySyncParse.parsed(check.Counts__c);
        for (String k : counts == null ? new Set<String>() : counts.keySet()) {
            v.counts.put(k, RlySyncParse.toInt(counts.get(k)));
        }
        return v;
    }

    // While the result isn't there: the run's link and state; a run that ended without it fails the check.
    private static void watchRun(RlyGit git, RLY_Sync_Check__c check, View v) {
        RlyGit.Run run = git.findRun(check.Run_Title__c);
        if (run == null) {
            return;
        }
        v.runUrl = run.url;
        v.runStatus = run.status;
        RLY_Sync_Check__c row = new RLY_Sync_Check__c(Sync_Id__c = check.Sync_Id__c, Run_Url__c = run.url);
        if (run.completed()) {
            v.done = true;
            v.status = RlySyncStore.FAILED;
            v.message = 'The check\'s run ended without writing its result. Open the run for the reason.';
            row.Status__c = v.status;
            row.Message__c = v.message;
        }
        RlySyncStore.save(row);
    }

    // The result's components (Org) or pairs (Route); the check gets its status and counts.
    private static void fill(View v, RLY_Sync_Check__c check, Map<String, Object> result) {
        v.done = true;
        v.runUrl = result.get('runUrl') == null ? v.runUrl : String.valueOf(result.get('runUrl'));
        Boolean ok = String.valueOf(result.get('status')) == RlySyncStore.SUCCEEDED;
        v.status = ok ? RlySyncStore.SUCCEEDED : RlySyncStore.FAILED;
        v.message = ok ? null : (result.get('message') == null ? 'The check failed. Open the run for the reason.' : String.valueOf(result.get('message')));
        v.truncated = result.get('truncated') == true;
        if (check.Kind__c == RlySyncStore.KIND_ROUTE) {
            RlySyncParse.readPairs(v, result);
        } else {
            RlySyncParse.readComponents(v, result);
        }
        String counts = JSON.serialize(v.counts);
        RlySyncStore.save(new RLY_Sync_Check__c(Sync_Id__c = check.Sync_Id__c, Status__c = v.status,
            Message__c = v.message == null ? null : v.message.left(4000), Run_Url__c = v.runUrl == null ? null : v.runUrl.left(255),
            Counts__c = counts.length() > 255 ? null : counts));
    }

    private static String fileOf(RLY_Sync_Check__c check) {
        return check.Kind__c == RlySyncStore.KIND_ROUTE ? 'route' : 'drift';
    }

}
