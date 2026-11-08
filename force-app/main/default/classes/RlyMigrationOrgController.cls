/**
 * @description The Migration tab (build 46, rlyRepoMigration), from the checklists on: Done marks, moving between
 * steps, each org against its new branch (developer orgs in parts), accepting differences, Switch now, Finish (the
 * Migration report) and Cancel. Every action is for Release Relay admins in the hub.
 */
public with sharing class RlyMigrationOrgController {

    /**
     * @description Sets or clears a checklist item's Done mark.
     * @param migrationId the migration
     * @param key the item
     * @param value done, or anything else to clear it
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View markItem(Id migrationId, String key, String value) {
        try {
            RlyMigrationSteps.mark(RlyMigrationGuard.load(migrationId), key, value);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Moves the wizard to a step.
     * @param migrationId the migration
     * @param step 1 to 8
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View goToStep(Id migrationId, Integer step) {
        try {
            RlyMigrationSteps.goTo(RlyMigrationGuard.load(migrationId), step);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Starts an org's check against its branch in the new repository.
     * @param migrationId the migration
     * @param orgId the org
     * @return the check (mode parts: the page sends the developer org's components)
     */
    @AuraEnabled
    public static RlySyncRuns.Started startOrgCheck(Id migrationId, Id orgId) {
        try {
            return RlyMigrationSwitch.beginOrgCheck(RlyMigrationGuard.load(migrationId), orgId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Stages one part of a developer org on the new repository.
     * @param migrationId the migration
     * @param partJson {compareId, n, retrieveId, sourceOrgId}
     * @return done = false while the retrieve runs
     */
    @AuraEnabled
    public static RlyComparePipeline.PartState stageOrgPart(Id migrationId, String partJson) {
        try {
            return RlyMigrationSync.stagePart(RlyMigrationGuard.load(migrationId), partJson);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description A developer org's parts are sent: starts its compare in the new pipeline.
     * @param migrationId the migration
     * @param runJson {syncId, parts, types}
     * @return the run's title
     */
    @AuraEnabled
    public static String runOrgDeveloper(Id migrationId, String runJson) {
        try {
            return RlyMigrationSync.runDeveloper(RlyMigrationGuard.load(migrationId),
                (RlyMigrationSync.DeveloperRun) JSON.deserialize(runJson, RlyMigrationSync.DeveloperRun.class));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Reads an org's check.
     * @param migrationId the migration
     * @param orgId the org
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View readOrgCheck(Id migrationId, Id orgId) {
        try {
            RlyMigrationSwitch.refreshOrgCheck(RlyMigrationGuard.load(migrationId), orgId);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Accepts the listed differences with a reason (blank clears it).
     * @param migrationId the migration
     * @param reason why
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View acceptDifferences(Id migrationId, String reason) {
        try {
            RlyMigrationSwitch.accept(RlyMigrationGuard.load(migrationId), reason);
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Switches the whole hub to the new connection.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View switchNow(Id migrationId) {
        try {
            RlyMigrationSwitch.switchHub(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Finishes: the Migration report PDF in the migration's Files.
     * @param migrationId the migration
     * @return the view
     */
    @AuraEnabled
    public static RlyMigrationView.View finishMigration(Id migrationId) {
        try {
            RlyMigrationSwitch.finish(RlyMigrationGuard.load(migrationId));
            return RlyMigrationGuard.view(migrationId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Cancels before the switch.
     * @param migrationId the migration
     * @return the start view
     */
    @AuraEnabled
    public static RlyMigrationView.View cancelMigration(Id migrationId) {
        try {
            RlyMigrationSwitch.cancel(RlyMigrationGuard.load(migrationId));
            return RlyMigrationViews.build(null);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
