/**
 * @description Who may run a data set where (RlyDataRuns):
 *   Up (send up)            anyone who can use the Data view starts it; an approver (or admin) who didn't start it loads it
 *   Down / Refill (copy down) admins only, start and load; masking is on unless the admin turns it off
 *   the target              must have a GitHub sign-in (a stage org or the hub): the pipeline loads it
 *   the source              any registered org; a developer org's records are sent by the hub
 * Plus the run's status checks.
 */
public with sharing class RlyDataRules {

    /** @description The deployment team's custom permission. */
    public static final String DEPLOY_TEAM = RlyReleaseAccess.DEPLOY_TEAM;
    private static final Pattern RELEASE_PATTERN = Pattern.compile('^REL-\\d{5,10}$');

    /** @description A checked request: the set, its definition, the orgs. */
    public class Checked {
        /** @description The data set. */
        public RLY_Data_Set__c dataSet;
        /** @description Its definition. */
        public RlyDataSet.Definition definition;
        /** @description The source org. */
        public RLY_Org__c source;
        /** @description The target org. */
        public RLY_Org__c target;
        /** @description Mask personal data. */
        public Boolean mask = false;
        /** @description The linked release, or null. */
        public Id releaseId;
    }

    /**
     * @description Checks a new run's request (its shape is checked first: RlyDataRuns.start).
     * @param req the request
     * @return the checked request
     */
    public static Checked checkStart(RlyDataRuns.Request req) {
        Checked c = load(req.dataSetId, req.sourceOrgId, req.targetOrgId);
        checkDirection(req.direction, c.source, c.target);
        c.mask = req.direction == RlyDataRuns.UP ? req.mask == true : req.mask != false;
        c.releaseId = releaseOf(req.releaseName);
        return c;
    }

    /**
     * @description Each org's place on the route, from the top: the hub 0, the stages from the last down, every
     * developer org on the bottom step (build 59, D30).
     * @param orgs the pipeline's orgs
     * @return the place by org id
     */
    public static Map<Id, Integer> ranks(List<RLY_Org__c> orgs) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        Integer step = 0;
        for (RLY_Org__c o : RlySyncRoute.topDown(orgs)) {
            out.put(o.Id, step);
            if (o.Role__c != 'Developer') {
                step++;
            }
        }
        return out;
    }

    // Send up goes to an org higher on the route, Copy down to one lower: never the source's own step (Refill repeats a load).
    private static void checkDirection(String direction, RLY_Org__c source, RLY_Org__c target) {
        Map<Id, Integer> rank = ranks(RlyDataStore.orgs());
        Integer fromRank = rank.get(source.Id);
        Integer toRank = rank.get(target.Id);
        if (fromRank == null || toRank == null) {
            return;
        }
        if (direction == RlyDataRuns.UP && toRank >= fromRank) {
            throw new RlyReleaseException('Send up goes to an org higher on the route than ' + source.Name + '.');
        }
        if (direction == RlyDataRuns.DOWN && toRank <= fromRank) {
            throw new RlyReleaseException('Copy down goes to an org lower on the route than ' + source.Name + '.');
        }
    }

    /**
     * @description The checked set and orgs of an existing run.
     * @param run the run
     * @return the checked request
     */
    public static Checked forRun(RLY_Data_Run__c run) {
        Checked c = load(run.Data_Set__c, run.Source_Org__c, run.Target_Org__c);
        c.mask = run.Mask__c == true;
        c.releaseId = run.Release__c;
        return c;
    }

    /**
     * @description The run, refused unless it has this status.
     * @param runId the run id
     * @param status the status it must have
     * @return the run
     */
    public static RLY_Data_Run__c requireStatus(String runId, String status) {
        RLY_Data_Run__c run = String.isBlank(runId) ? null : RlyDataStore.run(runId);
        if (run == null) {
            throw new RlyReleaseException('That data run isn\'t there any more.');
        }
        if (run.Status__c != status) {
            throw new RlyReleaseException('The run is ' + run.Status__c + ', so it can\'t do that now.');
        }
        return run;
    }

    /**
     * @description Only the person who started a run sends its records.
     * @param run the run
     */
    public static void requireRequester(RLY_Data_Run__c run) {
        if (run.Requested_By__c != UserInfo.getUserId()) {
            throw new RlyReleaseException('Only the person who started the run sends its records.');
        }
    }

    /**
     * @description Whether the current user moves data both ways (copy down, refill): admins and, from build 49, the
     * deployment team.
     * @return true for them
     */
    public static Boolean mayMoveDown() {
        return RlyReleaseAccess.isDeployTeam();
    }

    /**
     * @description Whether the current user may load data sent up: an approver, the deployment team or an admin.
     * @return true for them
     */
    public static Boolean mayLoadUp() {
        return RlyReleaseAccess.isDeployTeam() || RlyReleaseAccess.isApprover();
    }

    /**
     * @description Who may load: Up, an approver, the deployment team or an admin who didn't start the run; Down and
     * Refill, an admin or the deployment team.
     * @param run the run
     */
    public static void requireLoader(RLY_Data_Run__c run) {
        if (run.Direction__c != RlyDataRuns.UP) {
            if (!mayMoveDown()) {
                throw new RlyReleaseException('Loading data copied down is for Release Relay admins and the deployment team.');
            }
            return;
        }
        if (!mayLoadUp()) {
            throw new RlyReleaseException('An approver or the deployment team loads data sent up, after reading the dry run.');
        }
        if (run.Requested_By__c == UserInfo.getUserId()) {
            throw new RlyReleaseException('Someone else approves the load: you started this run.');
        }
    }

    // The set, its definition and the two orgs; the target needs a sign-in.
    private static Checked load(Id dataSetId, Id sourceOrgId, Id targetOrgId) {
        Checked c = new Checked();
        c.dataSet = RlyDataStore.setById(dataSetId);
        if (c.dataSet == null) {
            throw new RlyReleaseException('That data set isn\'t there any more.');
        }
        c.definition = RlyDataSet.parse(c.dataSet.Definition__c);
        Map<Id, RLY_Org__c> orgs = new Map<Id, RLY_Org__c>(RlyDataStore.orgs());
        c.source = orgs.get(sourceOrgId);
        c.target = orgs.get(targetOrgId);
        if (c.source == null || c.target == null) {
            throw new RlyReleaseException('Pick registered orgs.');
        }
        if (!RlySyncRoute.hasSignIn(c.target)) {
            throw new RlyReleaseException(c.target.Name + ' has no sign-in in GitHub, so the pipeline can\'t load it. Data goes into a stage org or the hub.');
        }
        return c;
    }

    // The release by its number, or null when none was given.
    private static Id releaseOf(String releaseName) {
        if (String.isBlank(releaseName)) {
            return null;
        }
        String n = releaseName.trim().toUpperCase();
        RLY_Release__c rel = RELEASE_PATTERN.matcher(n).matches() ? RlyRunMonitorReleases.releaseByName(n) : null;
        if (rel == null) {
            throw new RlyReleaseException('There\'s no release ' + releaseName.trim() + '.');
        }
        return rel.Id;
    }
}
