/**
 * @description Compare on Review: one check of a compare. While the developer org's retrieve runs it answers done = false;
 * when it has finished it reads the zip (RlyCompareZip) and, for each file, the target branch's copy (RlyCompareBranch).
 * It stays under the callout budget and TEXT_BUDGET characters: files it couldn't read yet come back pending with
 * more = true, and the page asks again with just those paths (pendingPaths), which reads only the branch. Deletions need
 * no retrieve: their files are read from the branch. Flows also get their versions in the target org when it can be read.
 * No DML.
 */
public with sharing class RlyCompareRun {

    /** @description Most callouts one check makes (Apex allows 100). */
    public static final Integer CALL_BUDGET = 90;
    /** @description Most characters of file text one answer carries. */
    public static final Integer TEXT_BUDGET = 2000000;
    /** @description Most paths one follow-up check takes. */
    public static final Integer MAX_PENDING = 500;
    /** @description The callout budget in force (tests lower it to see files left pending). */
    public static Integer callBudget = CALL_BUDGET;

    /** @description What the page sends: the retrieve, the components and the branch. */
    public class Job {
        /** @description The retrieve's async id, or blank when nothing needs retrieving (deletions only). */
        public String retrieveId;
        /** @description The developer org. */
        public Id sourceOrgId;
        /** @description The components the release brings, Type:Name. */
        public List<String> keys;
        /** @description The components the release deletes, Type:Name. */
        public List<String> deleted;
        /** @description The branch to compare with (blank: the first stage's). */
        public String targetBranch;
        /** @description A follow-up: only these paths' branch copies are read. */
        public List<String> pendingPaths;
    }

    /** @description What a check answers. */
    public class Result {
        /** @description The retrieve has finished (false: ask again). */
        @AuraEnabled public Boolean done = true;
        /** @description Some files are still pending: ask again with their paths. */
        @AuraEnabled public Boolean more = false;
        /** @description The developer org's name. */
        @AuraEnabled public String sourceName;
        /** @description The target org's name. */
        @AuraEnabled public String targetName;
        /** @description The branch compared with. */
        @AuraEnabled public String targetBranch;
        /** @description When the developer org's copy was read. */
        @AuraEnabled public Datetime readAt;
        /** @description The components, in the order asked (first check). */
        @AuraEnabled public List<RlyCompareFiles.ComponentDiff> components = new List<RlyCompareFiles.ComponentDiff>();
        /** @description A follow-up's files: path, left, and status unsupported or pending (the page has the right side). */
        @AuraEnabled public List<RlyCompareFiles.FileDiff> fetched = new List<RlyCompareFiles.FileDiff>();
        /** @description The retrieve's problems (fileName: problem). */
        @AuraEnabled public List<String> problems = new List<String>();
        /** @description The flows' versions in the target org, when it could be read. */
        @AuraEnabled public List<RlyFlowVersions.FlowInfo> targetFlows = new List<RlyFlowVersions.FlowInfo>();
    }

    /**
     * @description Checks a compare.
     * @param job what the page sent
     * @return where it is, and the files once read
     */
    public static Result check(Job job) {
        Result r = new Result();
        RLY_Org__c source = prepare(job, r);
        RlyCompareBranch branch = branchReader(r);
        if (job.pendingPaths != null && !job.pendingPaths.isEmpty()) {
            if (job.pendingPaths.size() > MAX_PENDING) {
                throw new RlyReleaseException('Ask for up to ' + MAX_PENDING + ' files at a time.');
            }
            r.fetched = branch.readPaths(job.pendingPaths);
            r.more = branch.more;
            return r;
        }
        Map<String, List<RlyCompareFiles.FileDiff>> fromZip = String.isBlank(job.retrieveId)
            ? new Map<String, List<RlyCompareFiles.FileDiff>>() : retrieved(source, job.retrieveId, r);
        if (!r.done) {
            return r;
        }
        r.readAt = System.now();
        for (String key : orEmpty(job.keys)) {
            r.components.add(RlyCompareParts.brought(key, fromZip.get(key.toLowerCase()), r));
        }
        for (String key : orEmpty(job.deleted)) {
            r.components.add(RlyCompareParts.removed(key, branch));
        }
        readFlows(r, job);
        branch.readAll(r.components);
        r.more = branch.more;
        return r;
    }

    // Checks the job and names the source, target and branch on the answer.
    private static RLY_Org__c prepare(Job job, Result r) {
        if (job == null) {
            throw new RlyReleaseException('Nothing to compare.');
        }
        List<String> asked = new List<String>(orEmpty(job.keys));
        asked.addAll(orEmpty(job.deleted));
        RlyCompareParts.checkKeys(asked);
        RLY_Org__c source = RlyRaiseRoute.source(job.sourceOrgId);
        RLY_Org__c target = targetOf(job, source);
        r.sourceName = source.Name;
        r.targetName = target.Name;
        r.targetBranch = target.Branch__c.trim();
        return source;
    }

    private static RlyCompareBranch branchReader(Result r) {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null || conn.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        return new RlyCompareBranch(RlyGit.forConnection(conn), conn.Source_Path__c, r.targetBranch);
    }

    // The first stage, or the route org whose branch the page asked for (the same branch, written exactly).
    private static RLY_Org__c targetOf(Job job, RLY_Org__c source) {
        RLY_Org__c firstStage = RlyRaiseRoute.target(source);
        String asked = String.isBlank(job.targetBranch) ? firstStage.Branch__c.trim() : job.targetBranch.trim();
        if (asked.equals(firstStage.Branch__c.trim())) {
            return firstStage;
        }
        for (RLY_Org__c o : RlyReleaseStore.routeOrgs()) {
            if (String.isNotBlank(o.Branch__c) && asked.equals(o.Branch__c.trim())) {
                return o;
            }
        }
        throw new RlyReleaseException('Compare with the branch of a stage or the hub.');
    }

    // The zip's files once the retrieve has finished; done = false on the answer while it runs.
    private static Map<String, List<RlyCompareFiles.FileDiff>> retrieved(RLY_Org__c source, String retrieveId, Result r) {
        RlyRetrieve.RetrieveStatus st = RlyRetrieve.check(source, retrieveId);
        if (!st.done) {
            r.done = false;
            return null;
        }
        if (!st.success) {
            throw new RlyReleaseException(source.Name + '\'s copy couldn\'t be retrieved: ' + st.message);
        }
        r.problems = st.problems;
        Map<String, List<RlyCompareFiles.FileDiff>> out = RlyCompareZip.read(st.zipBase64, source.Name);
        st.zipBase64 = null;
        return out;
    }

    // The flows' versions in the target org (shown above a flow's diff); left out when the org can't be read.
    private static void readFlows(Result r, Job job) {
        List<String> names = new List<String>();
        for (String key : orEmpty(job.keys)) {
            if (key.substringBefore(':') == 'Flow') {
                names.add(key.substringAfter(':'));
            }
        }
        if (names.isEmpty()) {
            return;
        }
        try {
            r.targetFlows = RlyFlowVersions.read(RlyReleaseStore.org(targetId(r)), names);
        } catch (Exception e) {
            r.targetFlows = new List<RlyFlowVersions.FlowInfo>();
        }
    }

    // The route org on the compared branch.
    private static Id targetId(Result r) {
        for (RLY_Org__c o : RlyReleaseStore.routeOrgs()) {
            if (o.Name == r.targetName && String.isNotBlank(o.Branch__c) && r.targetBranch.equals(o.Branch__c.trim())) {
                return o.Id;
            }
        }
        return null;
    }

    private static List<String> orEmpty(List<String> values) {
        return values == null ? new List<String>() : values;
    }
}
