/**
 * @description Switch now's conditions on the Migration tab (build 46): the dry run passed; the run copied everything
 * (or the importer's copy is verified) and every ref matches; the new connection is checked; every org is in sync with its
 * new branch (or the differences are accepted with a reason); no release is open on the current connection. Also the
 * checklists. No callouts.
 */
public with sharing class RlyMigrationGate {

    /**
     * @description The new and old setup checklists.
     * @param c the migration, connections, orgs and state
     * @return the section
     */
    public static RlyMigrationView.Setup setup(RlyMigrationViews.Context c) {
        RLY_Git_Connection__c current = c.current;
        RLY_Git_Connection__c target = c.target;
        List<RLY_Org__c> orgs = c.orgs;
        RlyMigrationState state = c.state;
        RlyMigrationView.Setup s = new RlyMigrationView.Setup();
        RlyMigrationChecklist.NewSetup n = new RlyMigrationChecklist.NewSetup();
        n.target = target;
        n.environments = RlyMigrationViews.environments(orgs);
        for (RLY_Org__c o : orgs) {
            n.prodBranch = o.Role__c == 'Hub' ? o.Branch__c : n.prodBranch;
        }
        s.newItems = RlyMigrationChecklist.newSetup(n, state);
        s.oldItems = RlyMigrationChecklist.oldSetup(current, state);
        s.optionalNames = RlyMigrationSecrets.optionalNames(target.Provider__c,
            RlyMigrationStore.resourceText(RlyMigrationSecrets.resourceOf(target.Provider__c)));
        s.tokenHint = RlyMigrationChecklist.tokenHint(current, target);
        for (RlyMigrationChecklist.Item i : s.newItems) {
            s.newDone += i.done ? 1 : 0;
        }
        for (RlyMigrationChecklist.Item i : s.oldItems) {
            s.oldDone += i.done ? 1 : 0;
        }
        return s;
    }

    /**
     * @description What Switch now needs.
     * @param c the migration and its state
     * @param v the view built so far
     * @return the section
     */
    public static RlyMigrationView.Gate of(RlyMigrationViews.Context c, RlyMigrationView.View v) {
        RLY_Migration__c m = c.m;
        RlyMigrationState state = c.state;
        RlyMigrationView.Gate g = new RlyMigrationView.Gate();
        g.acceptReason = state.acceptReason;
        g.switchedOn = m.Switched_On__c;
        g.conditions.add(dryCondition(v));
        g.conditions.add(copiedCondition(m, v));
        g.conditions.add(condition('The new connection is checked', v.target != null && v.target.status == 'Connected',
            v.target == null ? null : v.target.statusMessage));
        g.conditions.add(orgsCondition(v, state));
        g.conditions.add(openCondition(v));
        g.ready = m.Status__c == RlyMigrationStore.OPEN;
        for (RlyMigrationView.Condition c : g.conditions) {
            g.ready = g.ready && c.ok;
        }
        return g;
    }

    private static RlyMigrationView.Condition dryCondition(RlyMigrationView.View v) {
        return condition('Dry run passed', v.run.dry != null && v.run.dry.ready, v.run.dry == null ? 'Run the dry run.' : null);
    }

    // The importer's copy is verified by its dry run; lift and fresh need the run itself.
    private static RlyMigrationView.Condition copiedCondition(RLY_Migration__c m, RlyMigrationView.View v) {
        Boolean importer = m.Method__c == RlyMigrationMethods.IMPORTER;
        Boolean copied = v.moved.allMatch && v.run.result != null && (importer || v.run.result.status == RlyMigrationRun.SUCCEEDED);
        return condition(importer ? 'Verified: every branch and tag matches' : 'The run copied everything and every ref matches',
            copied, v.moved.matched);
    }

    private static RlyMigrationView.Condition orgsCondition(RlyMigrationView.View v, RlyMigrationState state) {
        List<String> differ = new List<String>();
        for (RlyMigrationView.OrgRow o : v.orgs) {
            if (o.status != RlyMigrationSync.IN_SYNC) {
                differ.add(o.name + ': ' + o.status);
            }
        }
        Boolean accepted = String.isNotBlank(state.acceptReason);
        return condition('Every org is in sync with its new branch' + (accepted && !differ.isEmpty() ? ' (differences accepted)' : ''),
            differ.isEmpty() || accepted, differ.isEmpty() ? null : String.join(differ, ' · '));
    }

    private static RlyMigrationView.Condition openCondition(RlyMigrationView.View v) {
        List<String> open = new List<String>();
        for (RlyMigrationView.OpenRelease r : v.holds.open) {
            open.add(r.name + ' (' + r.status + ')');
        }
        return condition('No open releases on ' + (v.current == null ? 'the current connection' : v.current.providerLabel),
            open.isEmpty(), open.isEmpty() ? null : String.join(open, ', ') + ': finish or close them first.');
    }

    private static RlyMigrationView.Condition condition(String label, Boolean ok, String detail) {
        RlyMigrationView.Condition c = new RlyMigrationView.Condition();
        c.label = label;
        c.ok = ok == true;
        c.detail = detail;
        return c;
    }
}
