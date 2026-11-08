/**
 * @description Install Release Relay update: starting its steps (RlyRelayUpdatePrepare makes the update). Every run
 * starts through RlyGit.startPipeline, so it is signed with the run-signing key like every other run the hub starts.
 *
 * A check (mode hub) reserves a request id the way the hub's own runs do (a prefix and the hub's clock in
 * milliseconds; REL- because the pipeline takes REL ids for hub and merge runs, and 13 digits never meet a release's
 * REL-00042), copies the zip as .relay-inbox/<id>.zip onto feature/rly-update-<id> made from the target, and starts
 * the check: validateMerged, selfUpdate, the tests, the run token. The test org's target is its install branch
 * rly-<its Git environment>-install; production's is release-relay-hub (the pipeline's own self-update branch).
 * An install (mode merge) merges its check's pull request with that check's id, pinned to the head the check validated
 * (expectHead) and quick deploying that check's validation (validationAttempt).
 * Callouts always come before the caller's save.
 */
public with sharing class RlyRelayUpdateRuns {

    /** @description Production's target: the branch the pipeline lets the hub update itself from. */
    public static final String PROD_TARGET = 'release-relay-hub';
    private static final Pattern ENV_PATTERN = Pattern.compile('[A-Za-z0-9._-]{1,80}');

    /**
     * @description Starts a step of the current update (callouts only; the caller saves the update afterwards).
     * @param u the current update
     * @param key the step
     * @return the started step (also put on the update)
     */
    public static RlyRelayUpdateState.Step start(RLY_Relay_Update__c u, String key) {
        if (u == null) {
            throw new RlyReleaseException('Prepare the update first: enter its branch and title.');
        }
        Map<String, RlyRelayUpdateState.Step> steps = RlyRelayUpdateState.read(u);
        if (!RlyRelayUpdateState.canStart(steps, key)) {
            throw new RlyReleaseException('This step can\'t start now: each step starts once the one before it has passed, and only while no step runs.');
        }
        RlyGit g = git();
        RlyRelayUpdateState.Step s = RlyRelayUpdateState.isCheck(key) ? startCheck(g, u, key) : startInstall(g, u, steps.get(RlyRelayUpdateState.checkOf(key)));
        s.status = RlyRelayUpdateState.RUNNING;
        s.startedAt = System.now();
        s.startedBy = UserInfo.getName();
        steps.put(key, s);
        RlyRelayUpdateState.write(u, steps);
        return s;
    }

    /**
     * @description The pipeline's run title for a step (the newest run with it is the step's run).
     * @param s the step
     * @param key the step's key
     * @return the title
     */
    public static String runTitle(RlyRelayUpdateState.Step s, String key) {
        return 'Release Relay ' + s.requestId + ' (' + (RlyRelayUpdateState.isCheck(key) ? 'hub' : 'merge') + ')';
    }

    /**
     * @description The hub's Git connection as a provider.
     * @return the provider
     */
    public static RlyGit git() {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null) {
            throw new RlyReleaseException('Save the Git connection first (Connection & route).');
        }
        return RlyGit.forConnection(conn);
    }

    /**
     * @description A stage on the route, by id.
     * @param orgId the org record's id
     * @return the stage
     */
    public static RLY_Org__c stage(String orgId) {
        for (RLY_Org__c o : RlyReleaseStore.pipelineOrgs(new Set<String>{ 'Stage' })) {
            if (String.isNotBlank(orgId) && String.valueOf(o.Id).left(15) == orgId.left(15)) {
                return o;
            }
        }
        throw new RlyReleaseException('Pick the org to test the update in (a stage on the route).');
    }

    /**
     * @description The hub org (production) on the route.
     * @return the hub
     */
    public static RLY_Org__c hub() {
        List<RLY_Org__c> hubs = RlyReleaseStore.pipelineOrgs(new Set<String>{ 'Hub' });
        if (hubs.isEmpty()) {
            throw new RlyReleaseException('Register the hub (production) on the Orgs section first.');
        }
        return hubs[0];
    }

    /**
     * @description An org's Git environment, checked.
     * @param org the org
     * @return the environment name
     */
    public static String environmentOf(RLY_Org__c org) {
        String env = org == null || org.Git_Environment__c == null ? '' : org.Git_Environment__c.trim();
        if (!ENV_PATTERN.matcher(env).matches()) {
            throw new RlyReleaseException('Set ' + (org == null ? 'the org' : org.Name) + '\'s Git environment on the Orgs section first.');
        }
        return env;
    }

    private static RlyRelayUpdateState.Step startCheck(RlyGit g, RLY_Relay_Update__c u, String key) {
        Boolean inTestOrg = key == RlyRelayUpdateState.TEST_CHECK;
        RLY_Org__c org = inTestOrg ? stage(u.Test_Org__c) : hub();
        RlyRelayUpdateState.Step s = new RlyRelayUpdateState.Step();
        s.environment = environmentOf(org);
        s.requestId = 'REL-' + String.valueOf(System.now().getTime());
        s.branch = 'feature/rly-update-' + s.requestId.toLowerCase();
        s.target = inTestOrg ? 'rly-' + s.environment.toLowerCase() + '-install' : PROD_TARGET;
        s.token = RlyPipelineRun.newToken();
        RlyRelayUpdateGit.ZipFile z = new RlyRelayUpdateGit.ZipFile();
        z.path = u.Zip_Path__c;
        z.sha = u.Zip_Sha__c;
        z.commitSha = u.Zip_Commit__c;
        new RlyRelayUpdateGit(g).copyTo(z, s);
        g.startPipeline(inputs(u, s, 'hub'));
        return s;
    }

    private static RlyRelayUpdateState.Step startInstall(RlyGit g, RLY_Relay_Update__c u, RlyRelayUpdateState.Step check) {
        RlyRelayUpdateState.Step s = new RlyRelayUpdateState.Step();
        s.requestId = check.requestId;
        s.branch = check.branch;
        s.target = check.target;
        s.environment = check.environment;
        s.token = RlyPipelineRun.newToken();
        s.checkToken = check.token;
        s.head = check.head;
        g.startPipeline(inputs(u, s, 'merge'));
        return s;
    }

    private static Map<String, String> inputs(RLY_Relay_Update__c u, RlyRelayUpdateState.Step s, String mode) {
        return new Map<String, String>{
            'request_id' => s.requestId, 'mode' => mode, 'environment' => s.environment, 'target_environment' => s.environment,
            'branch' => s.branch, 'target' => s.target, 'title' => (s.requestId + ': ' + u.Title__c).left(200),
            'components' => mode == 'hub' && u.Components__c != null ? u.Components__c : '', 'deletions' => '',
            'options' => JSON.serialize(options(u, s))
        };
    }

    private static Map<String, Object> options(RLY_Relay_Update__c u, RlyRelayUpdateState.Step s) {
        Map<String, Object> o = new Map<String, Object>{ 'hub' => true, 'validateMerged' => true, 'selfUpdate' => true,
            'tests' => String.isBlank(u.Tests__c) ? new List<String>() : u.Tests__c.split(','), 'attempt' => s.token,
            'by' => UserInfo.getName().left(80) };
        if (String.isNotBlank(s.checkToken)) {
            o.put('validationAttempt', s.checkToken);
        }
        if (String.isNotBlank(s.head)) {
            o.put('expectHead', s.head);
        }
        return o;
    }
}
