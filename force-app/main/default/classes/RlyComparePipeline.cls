/**
 * @description Compare in the pipeline (build 36, pipeline files v22): for a release too big for Compare in the hub, or
 * with files too large for it. The developer org has no Git sign-in, so the hub retrieves the components in parts of up
 * to RlyCompareFiles.MAX_COMPONENTS (startPart) and commits each part's zip to the results branch as it comes, never
 * decoded here (stagePart: compare-inbox/CMP-…/n.zip). Then the pipeline runs in mode compare (run): it converts the
 * parts, compares them with the target branch in Git and writes small result files that RlyComparePipelineResult reads.
 * Every call does one small piece, so none comes near the callout, heap or time limits. Callouts only, no DML.
 */
public with sharing class RlyComparePipeline {

    /** @description Where the parts wait on the results branch. */
    public static final String INBOX = 'compare-inbox/';
    /** @description Most components one compare in the pipeline takes. */
    public static final Integer MAX_KEYS = 1000;
    /** @description Most parts one compare sends. */
    public static final Integer MAX_PARTS = 200;
    /** @description Asked of a connection that isn't GitHub. */
    public static final String GITHUB_ONLY = 'Compare in the pipeline needs the GitHub pipeline files (version 22 or later).';


    /** @description One part: the retrieve the page started and where its zip goes. */
    public class Part {
        /** @description The compare's id, CMP- and 13 digits. */
        public String compareId;
        /** @description The part's number, from 1. */
        public Integer n;
        /** @description The part's retrieve. */
        public String retrieveId;
        /** @description The developer org. */
        public Id sourceOrgId;
    }

    /** @description Where a part is. */
    public class PartState {
        /** @description Its zip is on the results branch (false: the retrieve is still running). */
        @AuraEnabled public Boolean done = false;
        /** @description The retrieve's problems (fileName: problem). */
        @AuraEnabled public List<String> problems = new List<String>();
    }

    /** @description What starting the pipeline needs. */
    public class RunJob {
        /** @description The compare's id. */
        public String compareId;
        /** @description The developer org. */
        public Id sourceOrgId;
        /** @description The branch to compare with (blank: the first stage's). */
        public String targetBranch;
        /** @description What the release brings, Type:Name. */
        public List<String> keys;
        /** @description What it deletes, Type:Name. */
        public List<String> deleted;
        /** @description How many parts were sent. */
        public Integer parts;
        /** @description Sync status: the whole developer org against its own branch (components may be empty). */
        public Boolean full;
        /** @description Sync status: the org check the result is for (SYN-…), with full. */
        public String syncId;
        /** @description Sync status: the check's token, echoed in the result (blank: a new one). */
        public String attempt;
        /** @description Sync status: the source folders read, folder => type (only those can be only on the branch). */
        public Map<String, String> folders;
        /** @description Build 50: components compare leaves out (static resources, profiles): linked, never sent. */
        public List<String> notCompared;
    }

    /** @description The started run. */
    public class Started {
        /** @description The token the result echoes. */
        @AuraEnabled public String token;
        /** @description The run's title on GitHub. */
        @AuraEnabled public String runTitle;
        /** @description The developer org's name. */
        @AuraEnabled public String sourceName;
        /** @description The target org's name. */
        @AuraEnabled public String targetName;
        /** @description The branch compared with. */
        @AuraEnabled public String targetBranch;
        /** @description Build 50: each left-out component's file on the branch, Type:Name => link. */
        @AuraEnabled public Map<String, String> gitUrls = new Map<String, String>();
    }

    /**
     * @description Starts one part's retrieve: every component in it, of any type (the pipeline converts them all).
     * @param sourceOrgId the developer org
     * @param keys the part's components, Type:Name (up to RlyCompareFiles.MAX_COMPONENTS)
     * @return the retrieve's id
     */
    public static String startPart(Id sourceOrgId, List<String> keys) {
        RlyCompareParts.checkKeys(keys);
        RLY_Org__c source = RlyRaiseRoute.source(sourceOrgId);
        Map<String, Set<String>> byType = new Map<String, Set<String>>();
        for (String k : keys) {
            String typeName = k.substringBefore(':');
            if (!byType.containsKey(typeName)) {
                byType.put(typeName, new Set<String>());
            }
            byType.get(typeName).add(k.substringAfter(':'));
        }
        return RlyRetrieve.start(source, byType);
    }

    /**
     * @description Checks a part's retrieve; once it's done, commits its zip (as the org sent it) to the results branch.
     * @param part the part
     * @return done = false while the retrieve runs
     */
    public static PartState stagePart(Part part) {
        RlyComparePipelineInput.checkPart(part);
        RlyGit git = gitHub();
        RLY_Org__c source = RlyRaiseRoute.source(part.sourceOrgId);
        RlyRetrieve.RetrieveStatus st = RlyRetrieve.check(source, part.retrieveId);
        PartState state = new PartState();
        if (!st.done) {
            return state;
        }
        if (!st.success || String.isBlank(st.zipBase64)) {
            throw new RlyReleaseException(source.Name + '\'s copy couldn\'t be retrieved: ' + (st.message == null ? '' : st.message));
        }
        state.problems = st.problems;
        git.putFile(new RlyGitFile(INBOX + part.compareId + '/' + part.n + '.zip', RlyPipelineRun.RESULTS_BRANCH)
            .withContent(st.zipBase64, part.compareId + ' part ' + part.n + ' from ' + source.Name));
        st.zipBase64 = null;
        state.done = true;
        return state;
    }

    /**
     * @description Starts the pipeline in mode compare once every part is on the results branch.
     * @param job the compare
     * @return the run's token and title
     */
    public static Started run(RunJob job) {
        if (job != null && job.full == true) {
            RlySyncRuns.checkWhole(job);
        } else {
            RlyComparePipelineInput.checkRun(job);
        }
        RlyGit git = gitHub();
        RLY_Org__c source = RlyRaiseRoute.source(job.sourceOrgId);
        Boolean whole = job.full == true;
        RLY_Org__c target = whole ? source : RlyCompareTarget.of(source, job.targetBranch);
        Started s = new Started();
        s.token = String.isNotBlank(job.attempt) ? job.attempt : RlyPipelineRun.newToken();
        s.runTitle = runTitle(job.compareId);
        s.sourceName = source.Name;
        s.targetName = target.Name;
        s.targetBranch = target.Branch__c.trim();
        if (!whole) {
            linkLeftOut(job, git, s);
        }
        Map<String, Object> options = new Map<String, Object>{ 'hub' => true, 'label' => source.Name.left(40),
            'attempt' => s.token, 'batches' => job.parts };
        if (whole) {
            options.put('full', true);
            options.put('syncId', job.syncId);
            options.put('folders', job.folders);
        }
        git.startPipeline(new Map<String, String>{
            'request_id' => job.compareId, 'mode' => 'compare',
            'environment' => String.isBlank(source.Git_Environment__c) ? '' : source.Git_Environment__c,
            'target_environment' => '', 'branch' => '', 'target' => s.targetBranch,
            'title' => ((whole ? 'Org vs branch: ' : 'Compare ') + source.Name + ' with ' + s.targetBranch).left(200),
            'components' => joined(job.keys), 'deletions' => joined(job.deleted), 'options' => JSON.serialize(options)
        });
        return s;
    }

    // Build 50: static resources and profiles never go to the pipeline's compare; the page links to their files instead.
    private static void linkLeftOut(RunJob job, RlyGit git, Started s) {
        job.keys = withoutLeftOut(job.keys);
        job.deleted = withoutLeftOut(job.deleted);
        List<RlyCompareFiles.ComponentDiff> links = new List<RlyCompareFiles.ComponentDiff>();
        List<String> asked = job.notCompared == null ? new List<String>() : job.notCompared;
        for (Integer i = 0; i < asked.size() && i < MAX_KEYS; i++) {
            RlyCompareFiles.ComponentDiff c = new RlyCompareFiles.ComponentDiff();
            c.key = asked[i];
            links.add(c);
        }
        new RlyCompareBranch(git, git.connection().Source_Path__c, s.targetBranch).linkLeftOut(links);
        for (RlyCompareFiles.ComponentDiff c : links) {
            if (c.gitUrl != null) {
                s.gitUrls.put(c.key, c.gitUrl);
            }
        }
    }

    private static List<String> withoutLeftOut(List<String> keys) {
        List<String> out = new List<String>();
        for (String k : keys == null ? new List<String>() : keys) {
            if (!RlyCompareFiles.isLeftOut(k.substringBefore(':'))) {
                out.add(k);
            }
        }
        return out;
    }

    /**
     * @description The run's title on GitHub (the workflow's run-name).
     * @param compareId the compare's id
     * @return Release Relay CMP-… (compare)
     */
    public static String runTitle(String compareId) {
        return 'Release Relay ' + compareId + ' (compare)';
    }

    /**
     * @description Checks a compare's id (RlyComparePipelineInput).
     * @param compareId CMP- and 13 digits
     */
    public static void checkId(String compareId) {
        RlyComparePipelineInput.checkId(compareId);
    }

    /**
     * @description The hub's Git connection, checked: connected, on GitHub.
     * @return the provider
     */
    public static RlyGit gitHub() {
        return RlyComparePipelineInput.gitHub();
    }

    /**
     * @description A list joined with commas.
     * @param values the values (null: none)
     * @return the text
     */
    public static String joined(List<String> values) {
        return String.join(values == null ? new List<String>() : values, ',');
    }

}
