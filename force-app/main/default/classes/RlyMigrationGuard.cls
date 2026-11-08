/**
 * @description The Migration tab's controllers' shared checks (build 46): admins only, in the hub; the migration
 * loaded; the view built again after an action; errors the page can show.
 */
public with sharing class RlyMigrationGuard {

    /**
     * @description Loads a migration for an action (admins, in the hub).
     * @param migrationId the migration
     * @return the migration
     */
    public static RLY_Migration__c load(Id migrationId) {
        guard();
        RLY_Migration__c m = RlyMigrationStore.byId(migrationId);
        if (m == null) {
            throw new RlyReleaseException('That migration isn\'t there any more.');
        }
        return m;
    }

    /**
     * @description The view after an action (the connections read again).
     * @param migrationId the migration
     * @return the view
     */
    public static RlyMigrationView.View view(Id migrationId) {
        RlyGitConnections.forget();
        return RlyMigrationViews.build(RlyMigrationStore.byId(migrationId));
    }

    /**
     * @description Refuses outside the hub and for anyone but an admin.
     */
    public static void guard() {
        RlyHubGuard.requireHub();
        requireAdmin();
    }

    /**
     * @description Refuses anyone but a Release Relay admin.
     */
    public static void requireAdmin() {
        RlyReleaseAccess.requireAdmin('Moving to another Git provider is for Release Relay admins.');
    }

    /**
     * @description Saves the migration with its state.
     * @param m the migration
     * @param state its state
     */
    public static void save(RLY_Migration__c m, RlyMigrationState state) {
        m.State__c = state.toJson();
        RlyMigrationStore.save(m);
    }

    /**
     * @description The migration's new connection, or an error when none is configured.
     * @param m the migration
     * @return the connection
     */
    public static RLY_Git_Connection__c requireTarget(RLY_Migration__c m) {
        RLY_Git_Connection__c t = RlyGitConnections.byId(m.New_Connection__c);
        if (t == null) {
            throw new RlyReleaseException('Configure the new connection first.');
        }
        return t;
    }

    /**
     * @description Refuses a migration that has already switched, finished or been cancelled.
     * @param m the migration
     */
    public static void requireOpen(RLY_Migration__c m) {
        if (m.Status__c != RlyMigrationStore.OPEN) {
            throw new RlyReleaseException('This migration is ' + m.Status__c.toLowerCase() + ': that step is closed.');
        }
    }
}
