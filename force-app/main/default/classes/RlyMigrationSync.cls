/**
 * @description "Check every org is in sync" on the Migration tab (build 46): Sync status's own Org vs branch checks
 * (build 38), run against the NEW connection before the switch. A stage or the hub is read by the drift job in the new
 * pipeline (its environment's sign-in there); a developer org is read by the hub in parts, which go to the new
 * repository's results branch. Each call names the new connection for its request (RlyComparePipelineInput.useConnection)
 * and then uses RlySyncRuns, RlyCompareController and RlySyncResult as they are.
 */
public with sharing class RlyMigrationSync {

    /** @description An org whose check hasn't run. */
    public static final String NOT_CHECKED = 'Not checked';
    /** @description A check that is going. */
    public static final String RUNNING = 'Running';
    /** @description The org is the same as its branch in the new repository. */
    public static final String IN_SYNC = 'In sync';
    /** @description Components differ. */
    public static final String DIFFERS = 'Differs';
    /** @description The check failed. */
    public static final String FAILED = 'Failed';

    /**
     * @description Starts an org's check against its branch in the new repository.
     * @param m the migration
     * @param orgId the org
     * @return the check; mode parts asks the page to send the developer org's components
     */
    public static RlySyncRuns.Started start(RLY_Migration__c m, Id orgId) {
        RlyComparePipelineInput.useConnection(newConnection(m));
        return RlySyncRuns.startOrg(RlySyncRoute.find(RlySyncStore.orgs(), orgId));
    }

    /**
     * @description Stages one part of a developer org on the new repository's results branch.
     * @param m the migration
     * @param partJson {compareId, n, retrieveId, sourceOrgId}
     * @return done = false while the retrieve runs
     */
    public static RlyComparePipeline.PartState stagePart(RLY_Migration__c m, String partJson) {
        RlyComparePipelineInput.useConnection(newConnection(m));
        return RlyCompareController.stagePipelinePart(partJson);
    }

    /** @description A developer org's parts, sent: what starts its compare. */
    public class DeveloperRun {
        /** @description The check (also the parts' id). */
        public String syncId;
        /** @description How many parts were sent. */
        public Integer parts;
        /** @description The types the page listed. */
        public List<String> types = new List<String>();
    }

    /**
     * @description A developer org's check, once its parts are sent: starts the compare in the new pipeline.
     * @param m the migration
     * @param r the check, its parts and the listed types
     * @return the run's title
     */
    public static String runDeveloper(RLY_Migration__c m, DeveloperRun r) {
        RlyComparePipelineInput.useConnection(newConnection(m));
        return RlySyncRuns.runDeveloper(r.syncId, r.parts, r.types);
    }

    /**
     * @description Reads a check in the new repository.
     * @param m the migration
     * @param syncId the check
     * @return the check
     */
    public static RlySyncResult.View read(RLY_Migration__c m, String syncId) {
        RlyComparePipelineInput.useConnection(newConnection(m));
        return RlySyncResult.read(syncId);
    }

    /**
     * @description An org's row from a check.
     * @param v the check
     * @param mode drift or parts
     * @return the row to keep
     */
    public static RlyMigrationState.OrgCheck checkOf(RlySyncResult.View v, String mode) {
        RlyMigrationState.OrgCheck c = new RlyMigrationState.OrgCheck();
        c.syncId = v.syncId;
        c.mode = mode;
        c.stamp = System.now();
        if (v.status == RlySyncStore.FAILED) {
            c.status = FAILED;
            c.detail = String.isBlank(v.message) ? 'The check failed.' : v.message.left(500);
        } else if (v.done != true || v.status != 'Succeeded') {
            c.status = RUNNING;
        } else {
            Integer n = total(v.counts);
            c.status = n == 0 ? IN_SYNC : DIFFERS;
            c.detail = n == 0 ? null : n + ' component(s) differ: ' + countText(v.counts);
        }
        return c;
    }

    // The new connection, checked: Sync status reads it only once it's Connected.
    private static RLY_Git_Connection__c newConnection(RLY_Migration__c m) {
        RLY_Git_Connection__c c = RlyGitConnections.byId(m.New_Connection__c);
        if (c == null || c.Status__c != 'Connected') {
            throw new RlyReleaseException('Check the new connection first (Do in the new setup): the org checks run in its pipeline.');
        }
        return c;
    }

    private static Integer total(Map<String, Integer> counts) {
        Integer n = 0;
        for (Integer count : counts.values()) {
            n += count == null ? 0 : count;
        }
        return n;
    }

    private static String countText(Map<String, Integer> counts) {
        List<String> parts = new List<String>();
        Map<String, String> words = new Map<String, String>{ 'onlyInOrg' => 'only in the org', 'onlyOnBranch' => 'only on the branch',
            'different' => 'different' };
        for (String k : words.keySet()) {
            Integer n = counts.get(k);
            if (n != null && n > 0) {
                parts.add(n + ' ' + words.get(k));
            }
        }
        return String.join(parts, ', ');
    }
}
