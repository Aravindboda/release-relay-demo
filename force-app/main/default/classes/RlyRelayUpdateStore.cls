/**
 * @description Install Release Relay update: its records, the org's own Release Relay test classes (the fallback when a
 * zip can't be read) and the settings log rows each start writes. Updates and log rows are shared hub records: read
 * and written in system mode in the private inner class, after the controller's admin check.
 */
public with sharing class RlyRelayUpdateStore {

    /** @description The Pipeline tab section the log rows are listed under. */
    public static final String SECTION = 'Advanced';
    /** @description Classes whose name starts with this and ends in Test are Release Relay's own tests. */
    public static final String CLASS_PREFIX = 'Rly';

    /**
     * @description The newest update.
     * @return it, or null when none was prepared yet
     */
    public static RLY_Relay_Update__c current() {
        List<RLY_Relay_Update__c> rows = new SystemAccess().readNewest();
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves an update (insert or update).
     * @param row the update
     */
    public static void save(RLY_Relay_Update__c row) {
        new SystemAccess().upsertUpdate(row);
    }

    /**
     * @description The org's Release Relay test classes (CLASS_PREFIX…Test), by name.
     * @return the class names
     */
    public static List<String> orgTestClasses() {
        List<String> out = new List<String>();
        for (ApexClass c : new SystemAccess().readTestClasses(CLASS_PREFIX + '%Test')) {
            if (c.Name.endsWith('Test')) {
                out.add(c.Name);
            }
        }
        return out;
    }

    /**
     * @description Logs a start in Recent changes to settings (section Advanced). Never stops the start.
     * @param what what was started, for example Install update · SIT check
     * @param detail the request id and branch
     * @return true when the row was written
     */
    public static Boolean logStart(String what, String detail) {
        try {
            new SystemAccess().insertLog(new RLY_Settings_Change__c(Section__c = SECTION, What__c = what.left(255),
                New_Value__c = detail == null ? null : detail.left(255), Changed_By__c = UserInfo.getName().left(121)));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** @description System-mode reads and writes. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyRelayUpdateStore.current.
         * @return the newest row, or none
         */
        public List<RLY_Relay_Update__c> readNewest() {
            return [SELECT Id, Name, Branch__c, Title__c, Test_Org__c, Test_Org__r.Name, Zip_Path__c, Zip_Sha__c, Zip_Commit__c, Tests__c,
                           Tests_From__c, Components__c, Steps__c, CreatedDate
                    FROM RLY_Relay_Update__c WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Name DESC LIMIT 1];
        }

        /**
         * @description Inserts or updates an update.
         * @param row the update
         */
        public void upsertUpdate(RLY_Relay_Update__c row) {
            upsert as system row;
        }

        /**
         * @description Apex classes in no namespace whose name matches a LIKE pattern.
         * @param likePattern the pattern
         * @return the classes, by name
         */
        public List<ApexClass> readTestClasses(String likePattern) {
            return [SELECT Name FROM ApexClass WHERE NamespacePrefix = null AND Name LIKE :likePattern WITH SYSTEM_MODE ORDER BY Name LIMIT 2000];
        }

        /**
         * @description Writes a log row.
         * @param row the row
         */
        public void insertLog(RLY_Settings_Change__c row) {
            insert as system row;
        }
    }
}
