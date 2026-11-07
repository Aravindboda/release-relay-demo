/**
 * @description The Migration tab from the org checks on (build 46): each org against its branch in the new repository
 * (RlyMigrationSync), accepting listed differences with a reason, Switch now (the whole hub at once, through
 * RlyGitConnections.switchTo, with the hub-wide settings carried over to the new connection), Finish (the Migration report
 * PDF in the migration's Files) and Cancel before the switch. Callouts first, one save at the end; each action is logged.
 */
public with sharing class RlyMigrationSwitch {

    /**
     * @description Starts an org's check against its new branch, and keeps it on the migration.
     * @param m the migration
     * @param orgId the org
     * @return the check (mode parts: the page sends the developer org's components)
     */
    public static RlySyncRuns.Started beginOrgCheck(RLY_Migration__c m, Id orgId) {
        RlyMigrationGuard.requireOpen(m);
        RlySyncRuns.Started s = RlyMigrationSync.start(m, orgId);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        RlyMigrationState.OrgCheck c = new RlyMigrationState.OrgCheck();
        c.syncId = s.syncId;
        c.mode = s.mode;
        c.status = RlyMigrationSync.RUNNING;
        c.stamp = System.now();
        state.orgChecks.put(String.valueOf(orgId), c);
        m.Step__c = 6;
        state.log('Orgs in sync', 'Started ' + s.syncId + ' (' + s.mode + ')');
        RlyMigrationGuard.save(m, state);
        return s;
    }

    /**
     * @description Reads an org's check and keeps the outcome (In sync, Differs or Failed).
     * @param m the migration
     * @param orgId the org
     */
    public static void refreshOrgCheck(RLY_Migration__c m, Id orgId) {
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        RlyMigrationState.OrgCheck previous = state.orgChecks.get(String.valueOf(orgId));
        if (previous == null || String.isBlank(previous.syncId)) {
            throw new RlyReleaseException('Check that org first.');
        }
        RlyMigrationState.OrgCheck latest = RlyMigrationSync.checkOf(RlyMigrationSync.read(m, previous.syncId), previous.mode);
        state.orgChecks.put(String.valueOf(orgId), latest);
        if (latest.status != previous.status && latest.status != RlyMigrationSync.RUNNING) {
            state.log('Orgs in sync', latest.syncId + ': ' + latest.status + (String.isBlank(latest.detail) ? '' : ' (' + latest.detail + ')'));
        }
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Accepts the listed differences with a reason (blank clears the acceptance).
     * @param m the migration
     * @param reason why the differences are fine
     */
    public static void accept(RLY_Migration__c m, String reason) {
        RlyMigrationGuard.requireOpen(m);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.acceptReason = String.isBlank(reason) ? null : reason.trim().left(1000);
        state.log('Orgs in sync', state.acceptReason == null ? 'Acceptance cleared' : 'Accepted the differences: ' + state.acceptReason);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Switches the whole hub to the new connection, once every condition holds.
     * @param m the migration
     */
    public static void switchHub(RLY_Migration__c m) {
        RlyMigrationGuard.requireOpen(m);
        RlyMigrationView.View v = RlyMigrationViews.build(m);
        if (!v.gate.ready) {
            List<String> missing = new List<String>();
            for (RlyMigrationView.Condition c : v.gate.conditions) {
                if (!c.ok) {
                    missing.add(c.label);
                }
            }
            throw new RlyReleaseException('Not yet: ' + String.join(missing, '; ') + '.');
        }
        RLY_Git_Connection__c current = RlyGitConnections.byId(m.Current_Connection__c);
        RlyMigrationStore.saveConnection(new RLY_Git_Connection__c(Id = m.New_Connection__c, Code_Scan__c = current.Code_Scan__c,
            Back_Promote__c = current.Back_Promote__c, Retention_Days__c = current.Retention_Days__c,
            Archive_Nightly__c = current.Archive_Nightly__c));
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        String reason = 'Migration ' + m.Migration_Id__c + ' (' + m.Method__c + ')'
            + (String.isBlank(state.acceptReason) ? '' : '; differences accepted: ' + state.acceptReason);
        RlyGitConnections.switchTo(m.New_Connection__c, reason);
        m.Status__c = RlyMigrationStore.SWITCHED;
        m.Switched_On__c = System.now();
        m.Step__c = 8;
        state.log('Switch now', 'Switched the hub from ' + v.current.providerLabel + ' to ' + v.target.providerLabel + ': ' + reason);
        RlyMigrationGuard.save(m, state);
    }

    /**
     * @description Finishes the migration: the Migration report as a PDF in its Files.
     * @param m the migration (switched)
     */
    public static void finish(RLY_Migration__c m) {
        if (m.Status__c != RlyMigrationStore.SWITCHED) {
            throw new RlyReleaseException('Switch first: the report comes after the switch.');
        }
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.log('Finish', 'Saved the Migration report');
        m.State__c = state.toJson();
        RlyMigrationView.View v = RlyMigrationViews.build(m);
        String title = 'Migration report ' + m.Migration_Id__c + ' ' + System.now().format('yyyy-MM-dd HH:mm');
        m.Report_File__c = RlyMigrationStore.saveFile(m.Id, title, Blob.toPdf(RlyMigrationReport.html(m, v)));
        m.Status__c = RlyMigrationStore.FINISHED;
        m.Finished_On__c = System.now();
        RlyMigrationStore.save(m);
    }

    /**
     * @description Cancels a migration before the switch (the new connection stays, inactive).
     * @param m the migration
     */
    public static void cancel(RLY_Migration__c m) {
        RlyMigrationGuard.requireOpen(m);
        RlyMigrationState state = RlyMigrationState.of(m.State__c);
        state.log('Cancel', 'Cancelled before the switch');
        m.Status__c = RlyMigrationStore.CANCELLED;
        RlyMigrationGuard.save(m, state);
    }
}
