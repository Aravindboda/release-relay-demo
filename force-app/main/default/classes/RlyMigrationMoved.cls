/**
 * @description What moved, on the Migration tab and in the report (build 46): each branch and tag with its commit in the
 * current and the new repository and a match mark, the Release Relay branches first with their role (the pipeline branch,
 * each org's branch, results, snapshots) and a link to each in the new repository; and what didn't move (open pull or
 * merge requests, run history, comments, secrets, protected branches, environments, webhooks). No callouts.
 */
public with sharing class RlyMigrationMoved {

    private static final Integer MAX_ROWS = 300;
    private static final List<String> STAYS = new List<String>{ 'Pipeline run history', 'Comments and reviews',
        'Secrets and variables (enter them again: Do in the new setup)', 'Protected-branch rules', 'Environments and their approvals',
        'Webhooks and integrations' };

    /**
     * @description What moved (each ref with both commits, its role and its link) and what didn't.
     * @param c the migration, connections, orgs and state
     * @return the section
     */
    public static RlyMigrationView.Moved of(RlyMigrationViews.Context c) {
        RLY_Migration__c m = c.m;
        RLY_Git_Connection__c target = c.target;
        RlyMigrationState state = c.state;
        RlyMigrationView.Moved mv = new RlyMigrationView.Moved();
        mv.stays = STAYS;
        mv.requests = state.requests;
        mv.fresh = m.Method__c == RlyMigrationMethods.FRESH;
        Map<String, Object> result = RlySyncParse.parsed(m.Result__c);
        if (result == null || target == null) {
            return mv;
        }
        mv.counts = RlyMigrationSummary.counts(result);
        Tally t = new Tally(RlyGit.forConnection(target), roles(c.current, c.orgs));
        for (Object o : result.get('refs') instanceof List<Object> ? (List<Object>) result.get('refs') : new List<Object>()) {
            t.add(RlyMigrationSummary.refRow((Map<String, Object>) o));
        }
        List<RlyMigrationView.RefRow> ordered = t.ordered();
        for (Integer i = 0; i < Math.min(ordered.size(), MAX_ROWS); i++) {
            mv.rows.add(ordered[i]);
        }
        Integer refsTotal = RlyMigrationSummary.toInt(result.get('refsTotal'), t.total + t.skipped) - t.skipped;
        mv.more = Math.max(0, refsTotal + t.skipped - mv.rows.size());
        mv.matched = t.matching + ' of ' + refsTotal + ' match';
        mv.allMatch = t.total > 0 && t.matching == t.total && refsTotal == t.total;
        return mv;
    }

    /** @description The refs counted: the Release Relay branches first, each with its role and link. */
    private class Tally {
        private final RlyGit targetGit;
        private final Map<String, String> roles;
        private final List<RlyMigrationView.RefRow> named = new List<RlyMigrationView.RefRow>();
        private final List<RlyMigrationView.RefRow> others = new List<RlyMigrationView.RefRow>();
        /** @description Refs counted (the results branch moving on left out). */
        public Integer total = 0;
        /** @description Refs that match. */
        public Integer matching = 0;
        /** @description Results-branch differences left out. */
        public Integer skipped = 0;

        /**
         * @description A tally for the new repository.
         * @param targetGit the new connection's provider (for the links)
         * @param roles branch name to its Release Relay role
         */
        public Tally(RlyGit targetGit, Map<String, String> roles) {
            this.targetGit = targetGit;
            this.roles = roles;
        }

        /**
         * @description Counts a ref and gives it its role and link.
         * @param row the ref
         */
        public void add(RlyMigrationView.RefRow row) {
            row.role = row.kind == 'branch' ? roles.get(row.name) : null;
            row.url = row.kind == 'branch' && row.match ? targetGit.branchUrl(row.name) : null;
            (row.role == null ? others : named).add(row);
            if (!row.match && row.name == RlyPipelineRun.RESULTS_BRANCH) {
                skipped++; // the results branch moves on with every run (the migrate job's too): never a difference
                return;
            }
            total++;
            matching += row.match ? 1 : 0;
        }

        /**
         * @description The refs, the Release Relay branches first.
         * @return the rows
         */
        public List<RlyMigrationView.RefRow> ordered() {
            List<RlyMigrationView.RefRow> out = new List<RlyMigrationView.RefRow>(named);
            out.addAll(others);
            return out;
        }
    }

    private static Map<String, String> roles(RLY_Git_Connection__c current, List<RLY_Org__c> orgs) {
        Map<String, String> out = new Map<String, String>{ RlyPipelineRun.RESULTS_BRANCH => 'results',
            RlyRollbackPlan.SNAPSHOT_BRANCH => 'rollback snapshots' };
        for (RLY_Org__c o : orgs) {
            if (String.isNotBlank(o.Branch__c)) {
                out.put(o.Branch__c.trim(), o.Role__c == 'Hub' ? o.Name + ' (hub)' : o.Name + '\'s branch');
            }
        }
        if (current != null && String.isNotBlank(current.Pipeline_Branch__c)) {
            out.put(current.Pipeline_Branch__c.trim(), 'pipeline branch');
        }
        return out;
    }
}
