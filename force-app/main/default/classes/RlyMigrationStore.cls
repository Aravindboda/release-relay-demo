/**
 * @description Data access for the Migration tab (build 46): migrations, the new connection, the registered orgs, a
 * release found by its number, the packaged pipeline file and the report's file. Migrations, connections and orgs are
 * shared hub records: read and written in system mode, after the controller's admin check.
 */
public with sharing class RlyMigrationStore {

    /** @description An open migration. */
    public static final String OPEN = 'Open';
    /** @description Switched to the new connection, checklists still going. */
    public static final String SWITCHED = 'Switched';
    /** @description Finished: the report is saved. */
    public static final String FINISHED = 'Finished';
    /** @description Cancelled before the switch. */
    public static final String CANCELLED = 'Cancelled';

    /**
     * @description The migration still going (open or switched), the newest.
     * @return the migration, or null
     */
    public static RLY_Migration__c current() {
        List<RLY_Migration__c> rows = new SystemAccess().readGoing();
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description One migration.
     * @param migrationId the record
     * @return the migration, or null
     */
    public static RLY_Migration__c byId(Id migrationId) {
        List<RLY_Migration__c> rows = new SystemAccess().readOne(migrationId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves a migration (insert or update).
     * @param row the fields to save
     */
    public static void save(RLY_Migration__c row) {
        new SystemAccess().upsertMigration(row);
    }

    /**
     * @description Saves the new connection (insert or update); a new one is saved inactive.
     * @param row the fields to save
     */
    public static void saveConnection(RLY_Git_Connection__c row) {
        new SystemAccess().upsertConnection(row);
    }

    /**
     * @description The registered orgs (no sign-in fields), by name.
     * @return the orgs
     */
    public static List<RLY_Org__c> orgs() {
        return new SystemAccess().readOrgs();
    }

    /**
     * @description The packaged content of a static resource.
     * @param name the static resource
     * @return its text, or blank
     */
    public static String resourceText(String name) {
        List<StaticResource> rows = new SystemAccess().readResource(name);
        return rows.isEmpty() ? '' : rows[0].Body.toString();
    }

    /** @description System-mode reads and writes. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyMigrationStore.current.
         * @return the rows
         */
        public List<RLY_Migration__c> readGoing() {
            return [SELECT Id, Name, Migration_Id__c, Current_Connection__c, New_Connection__c, Status__c, Step__c, Method__c, Run_Id__c,
                           Run_Kind__c, Run_Status__c, Run_Token__c, Run_Url__c, Dry_Run__c, Result__c, State__c, Switched_On__c,
                           Finished_On__c, Report_File__c, CreatedDate, CreatedBy.Name
                    FROM RLY_Migration__c WHERE Status__c IN (:OPEN, :SWITCHED) WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
        }

        /**
         * @description See RlyMigrationStore.byId.
         * @param migrationId the record
         * @return the rows
         */
        public List<RLY_Migration__c> readOne(Id migrationId) {
            return [SELECT Id, Name, Migration_Id__c, Current_Connection__c, New_Connection__c, Status__c, Step__c, Method__c, Run_Id__c,
                           Run_Kind__c, Run_Status__c, Run_Token__c, Run_Url__c, Dry_Run__c, Result__c, State__c, Switched_On__c,
                           Finished_On__c, Report_File__c, CreatedDate, CreatedBy.Name
                    FROM RLY_Migration__c WHERE Id = :migrationId WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description See RlyMigrationStore.save.
         * @param row the fields to save
         */
        public void upsertMigration(RLY_Migration__c row) {
            upsert as system row;
        }

        /**
         * @description See RlyMigrationStore.saveConnection.
         * @param row the fields to save
         */
        public void upsertConnection(RLY_Git_Connection__c row) {
            upsert as system row;
            RlyReleaseStore.forgetGit();
        }

        /**
         * @description See RlyMigrationStore.orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Git_Environment__c, Stage_Order__c, Status__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Stage_Order__c ASC NULLS FIRST, Name LIMIT 200];
        }

        /**
         * @description See RlyMigrationStore.resourceText.
         * @param name the static resource
         * @return the rows
         */
        public List<StaticResource> readResource(String name) {
            return [SELECT Body FROM StaticResource WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
        }
    }
}
