/**
 * @description Builds the Migration tab's view (build 46) from the saved migration, the connections and the registered
 * orgs, without callouts: what the current connection holds, the methods for the pair, the dry run and the run, What
 * moved (each ref with both commits and its Release Relay role), the checklists, each org's check and what Switch now
 * needs.
 */
public with sharing class RlyMigrationViews {

    /** @description What the parts of the view are built from. */
    public class Context {
        /** @description The migration. */
        public RLY_Migration__c m;
        /** @description The current connection. */
        public RLY_Git_Connection__c current;
        /** @description The new connection, or null. */
        public RLY_Git_Connection__c target;
        /** @description The registered orgs with a branch. */
        public List<RLY_Org__c> orgs;
        /** @description The migration's state. */
        public RlyMigrationState state;
    }

    /**
     * @description The view of a migration, or of the start when there is none.
     * @param m the migration, or null
     * @return the view
     */
    public static RlyMigrationView.View build(RLY_Migration__c m) {
        RlyMigrationView.View v = new RlyMigrationView.View();
        RlyMigrationState state = RlyMigrationState.of(m == null ? null : m.State__c);
        RLY_Git_Connection__c current = RlyGitConnections.byId(m == null ? RlyGitConnections.activeId() : m.Current_Connection__c);
        RLY_Git_Connection__c target = m == null ? null : RlyGitConnections.byId(m.New_Connection__c);
        List<RLY_Org__c> orgs = RlySyncStore.orgs();
        v.current = conn(current);
        v.target = conn(target);
        v.log.isAdmin = RlyOrgController.isAdmin();
        v.holds = holds(current, orgs, state);
        v.orgs = orgRows(orgs, state);
        if (m == null) {
            return v;
        }
        v.id = m.Id;
        v.migrationId = m.Migration_Id__c;
        v.status = m.Status__c;
        v.step = m.Step__c == null ? 1 : m.Step__c.intValue();
        v.choose.method = m.Method__c;
        v.choose.methods = RlyMigrationMethods.forPair(current, target, state.targetBranches);
        Context c = new Context();
        c.m = m;
        c.current = current;
        c.target = target;
        c.orgs = orgs;
        c.state = state;
        v.run = runView(m);
        v.moved = RlyMigrationMoved.of(c);
        if (target != null) {
            v.setup = RlyMigrationGate.setup(c);
        }
        v.gate = RlyMigrationGate.of(c, v);
        v.log.events = events(state);
        v.cancelled = state.cancelled == null ? new List<RlyMigrationView.CancelledRelease>() : state.cancelled;
        v.log.finishedOn = m.Finished_On__c;
        v.log.reportUrl = String.isBlank(m.Report_File__c) ? null : '/sfc/servlet.shepherd/document/download/' + m.Report_File__c;
        return v;
    }

    /**
     * @description The Release Relay branches: the pipeline branch, each org's, results and snapshots.
     * @param current the current connection
     * @param orgs the registered orgs
     * @return the branches, each once, the pipeline branch first
     */
    public static List<String> namedBranches(RLY_Git_Connection__c current, List<RLY_Org__c> orgs) {
        List<String> out = new List<String>();
        addOnce(out, current == null || String.isBlank(current.Pipeline_Branch__c) ? 'main' : current.Pipeline_Branch__c.trim());
        for (RLY_Org__c o : orgs) {
            addOnce(out, o.Branch__c);
        }
        addOnce(out, RlyPipelineRun.RESULTS_BRANCH);
        addOnce(out, RlyRollbackPlan.SNAPSHOT_BRANCH);
        return out;
    }

    /**
     * @description The orgs' Git environments, each once.
     * @param orgs the registered orgs
     * @return the environments
     */
    public static List<String> environments(List<RLY_Org__c> orgs) {
        List<String> out = new List<String>();
        for (RLY_Org__c o : orgs) {
            addOnce(out, o.Git_Environment__c);
        }
        return out;
    }

    private static RlyMigrationView.Conn conn(RLY_Git_Connection__c c) {
        if (c == null) {
            return null;
        }
        RlyMigrationView.Conn out = new RlyMigrationView.Conn();
        out.id = c.Id;
        out.provider = c.Provider__c;
        out.providerLabel = RlyMigrationMethods.labelOf(c.Provider__c);
        out.repository = c.Repository__c;
        out.namedCredential = c.Named_Credential__c;
        out.pipelineFile = c.Pipeline__c;
        out.pipelineBranch = c.Pipeline_Branch__c;
        out.status = c.Status__c;
        out.statusMessage = c.Status_Message__c;
        out.active = c.Id == RlyGitConnections.activeId();
        try {
            out.webUrl = RlyGit.forConnection(c).webUrl();
        } catch (RlyGit.GitException e) {
            out.webUrl = null;
        }
        return out;
    }

    private static RlyMigrationView.Holds holds(RLY_Git_Connection__c current, List<RLY_Org__c> orgs, RlyMigrationState state) {
        RlyMigrationView.Holds h = new RlyMigrationView.Holds();
        h.branches = state.branches;
        h.more = state.moreBranches == true;
        h.readOn = state.branchesReadOn;
        h.targetCheck = state.targetCheck;
        h.targetBranches = state.targetBranches;
        h.orgs = orgRows(orgs, new RlyMigrationState());
        for (RLY_Release__c r : RlyGitConnections.openReleases(current == null ? null : current.Id)) {
            RlyMigrationView.OpenRelease o = new RlyMigrationView.OpenRelease();
            o.id = r.Id;
            o.name = r.Name;
            o.title = r.Title__c;
            o.status = r.Status__c;
            o.url = r.PR_URL__c;
            o.running = RlyStatusReader.OPEN_STATUSES.contains(r.Status__c);
            h.open.add(o);
        }
        return h;
    }

    private static List<RlyMigrationView.OrgRow> orgRows(List<RLY_Org__c> orgs, RlyMigrationState state) {
        List<RlyMigrationView.OrgRow> out = new List<RlyMigrationView.OrgRow>();
        for (RLY_Org__c o : orgs) {
            if (String.isBlank(o.Branch__c)) {
                continue;
            }
            RlyMigrationView.OrgRow r = new RlyMigrationView.OrgRow();
            r.id = o.Id;
            r.name = o.Name;
            r.role = o.Role__c;
            r.branch = o.Branch__c;
            r.how = RlySyncRoute.hasSignIn(o) ? 'read by the pipeline' : 'read by the hub, in parts';
            RlyMigrationState.OrgCheck c = state.orgChecks.get(String.valueOf(o.Id));
            r.status = c == null ? RlyMigrationSync.NOT_CHECKED : c.status;
            r.detail = c == null ? null : c.detail;
            r.syncId = c == null ? null : c.syncId;
            r.mode = c == null ? null : c.mode;
            out.add(r);
        }
        return out;
    }

    private static RlyMigrationView.RunView runView(RLY_Migration__c m) {
        RlyMigrationView.RunView r = new RlyMigrationView.RunView();
        r.kind = m.Run_Kind__c;
        r.status = m.Run_Status__c;
        r.runId = m.Run_Id__c;
        r.runUrl = m.Run_Url__c;
        r.running = RlyMigrationRun.isRunning(m.Run_Status__c);
        r.dry = RlyMigrationSummary.of(RlySyncParse.parsed(m.Dry_Run__c));
        r.result = RlyMigrationSummary.of(RlySyncParse.parsed(m.Result__c));
        return r;
    }

    private static List<RlyMigrationView.Event> events(RlyMigrationState state) {
        List<RlyMigrationView.Event> out = new List<RlyMigrationView.Event>();
        for (Integer i = state.events.size() - 1; i >= 0; i--) {
            RlyMigrationState.Event e = state.events[i];
            RlyMigrationView.Event x = new RlyMigrationView.Event();
            x.step = e.step;
            x.what = e.what;
            x.who = e.who;
            x.stamp = e.stamp;
            out.add(x);
        }
        return out;
    }

    private static void addOnce(List<String> values, String value) {
        if (String.isNotBlank(value) && !values.contains(value.trim())) {
            values.add(value.trim());
        }
    }
}
