/**
 * @description Several Git connections (build 45): reads and saves how the other repositories' prod branches are kept in
 * step after a deploy to production (RlyProdSync). Releases are shared hub records: system mode, and only the two Prod
 * Sync fields are written here (the automatic releases are inserted through RlyReleaseStore).
 */
public with sharing class RlyProdSyncStore {

    /**
     * @description The deployed release with its entries.
     * @param releaseId the release
     * @return the release (Name, Title__c, Prod_Sync__c, deletions), or null
     */
    public static RLY_Release__c deployed(Id releaseId) {
        List<RLY_Release__c> rows = new SystemAccess().readDeployed(releaseId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description The automatic releases, by Id.
     * @param ids the releases
     * @return Id, Name, Status__c and Error_Message__c of each
     */
    public static Map<Id, RLY_Release__c> raised(Set<Id> ids) {
        return ids.isEmpty() ? new Map<Id, RLY_Release__c>() : new Map<Id, RLY_Release__c>(new SystemAccess().readRaised(ids));
    }

    /**
     * @description Saves the entries.
     * @param releaseId the deployed release
     * @param entriesJson the entries as JSON
     * @param state Prod_Sync_State__c
     */
    public static void saveEntries(Id releaseId, String entriesJson, String state) {
        new SystemAccess().saveRow(new RLY_Release__c(Id = releaseId, Prod_Sync__c = entriesJson.left(32000), Prod_Sync_State__c = state));
    }

    /** @description System-mode access to the releases. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyProdSyncStore.deployed.
         * @param releaseId the release
         * @return the rows
         */
        public List<RLY_Release__c> readDeployed(Id releaseId) {
            return [SELECT Id, Name, Title__c, Prod_Sync__c, Prod_Sync_State__c, Deletions__c, Deletion_Count__c, Release_Type__c
                    FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE];
        }

        /**
         * @description See RlyProdSyncStore.raised.
         * @param ids the releases
         * @return the rows
         */
        public List<RLY_Release__c> readRaised(Set<Id> ids) {
            return [SELECT Id, Name, Status__c, Error_Message__c FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE LIMIT 20];
        }

        /**
         * @description See RlyProdSyncStore.saveEntries.
         * @param row the row
         */
        public void saveRow(RLY_Release__c row) {
            update as system row;
        }
    }
}
