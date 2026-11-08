/**
 * @description The Migration tab (build 46, rlyRepoMigration), up to the new setup: start from the active connection,
 * the new connection, the method, the dry run and the run, Update pipeline files and Check on the new connection.
 * RlyMigrationOrgController has the rest. Every action is for Release Relay admins in the hub and returns the view.
 */
public with sharing class RlyMigrationController {

    /**
     * @description The migration still going (or the start, when there is none).
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View getMigration() {
        try {
            RlyMigrationGuard.requireAdmin();
            return RlyMigrationViews.build(RlyMigrationStore.current());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Starts a migration from the active connection.
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View startMigration() {
        try {
            RlyMigrationGuard.guard();
            return RlyMigrationGuard.view(RlyMigrationSteps.start().Id);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Reads the current repository's branches again.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View readCurrent(Id migrationId) {
        try {
            RlyMigrationSteps.readCurrentBranches(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Saves the new connection (inactive until the switch).
     * @param migrationId the migration
     * @param connectionJson {Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c}
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View saveTarget(Id migrationId, String connectionJson) {
        try {
            RlyMigrationSteps.saveNewConnection(RlyMigrationGuard.load(migrationId), connectionJson);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Checks the new repository: reachable, empty or holding branches.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View checkTargetRepository(Id migrationId) {
        try {
            RlyMigrationSteps.checkNewRepository(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Picks how the repository moves.
     * @param migrationId the migration
     * @param method lift, importer or fresh
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View chooseMethod(Id migrationId, String method) {
        try {
            RlyMigrationSteps.choose(RlyMigrationGuard.load(migrationId), method);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Starts the dry run (or the importer's verify) or the run, in the current pipeline.
     * @param migrationId the migration
     * @param kind dry or run
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View startRun(Id migrationId, String kind) {
        try {
            RlyMigrationActions.dispatch(RlyMigrationGuard.load(migrationId), kind);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Reads the latest run (the page calls it every few seconds while it goes).
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View refreshRun(Id migrationId) {
        try {
            RlyMigrationActions.readRun(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Update pipeline files on the new connection.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View updatePipelineFiles(Id migrationId) {
        try {
            RlyMigrationActions.pushPipelineFiles(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Checks the new connection and saves its status.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View checkNewConnection(Id migrationId) {
        try {
            RlyMigrationActions.checkConnection(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
