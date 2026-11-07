/**
 * @description Work items (build 40): every read and save of the work tracking settings (RLY_Work_Tracking__c, a
 * hierarchy custom setting: its org default row, read without a query), the tickets on releases (RLY_Work_Item__c)
 * and the release fields the work items read, in system mode: any Release Relay user sees the tickets of the releases
 * they can open, and only admins change the settings (checked by the callers).
 */
public with sharing class RlyWorkStore {

    /** @description Most work item rows one read takes (the Work items tab, newest first). */
    public static final Integer MAX_ROWS = 2000;

    /**
     * @description The settings (the org default row, no query), or null before an admin saved them.
     * @return the record
     */
    public static RLY_Work_Tracking__c trackingSettings() {
        return new SystemAccess().settings();
    }

    /**
     * @description Saves the settings (insert or update of the one record).
     * @param row the settings
     */
    public static void saveSettings(RLY_Work_Tracking__c row) {
        new SystemAccess().upsertSettings(row);
    }

    /**
     * @description A release's work item rows, by ticket.
     * @param releaseId the release
     * @return the rows
     */
    public static List<RLY_Work_Item__c> forRelease(Id releaseId) {
        return new SystemAccess().forReleases(new Set<Id>{ releaseId });
    }

    /**
     * @description Several releases' work item rows.
     * @param releaseIds the releases
     * @return the rows
     */
    public static List<RLY_Work_Item__c> forReleases(Set<Id> releaseIds) {
        return releaseIds == null || releaseIds.isEmpty() ? new List<RLY_Work_Item__c>() : new SystemAccess().forReleases(releaseIds);
    }

    /**
     * @description The newest work item rows with their releases (the Work items tab).
     * @return the rows, newest first
     */
    public static List<RLY_Work_Item__c> recent() {
        return new SystemAccess().recent();
    }

    /**
     * @description A release with the fields the work items read.
     * @param releaseId the release
     * @return the release, or null
     */
    public static RLY_Release__c release(Id releaseId) {
        List<RLY_Release__c> rows = new SystemAccess().releases(new Set<Id>{ releaseId });
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Saves work item rows (upsert by Key__c) and the release's ticket list.
     * @param rows the rows to keep
     * @param gone rows to remove (tickets taken off the release)
     * @param rel the release with Work_Items__c set, or null to leave it
     */
    public static void save(List<RLY_Work_Item__c> rows, List<RLY_Work_Item__c> gone, RLY_Release__c rel) {
        new SystemAccess().save(rows, gone, rel);
    }

    /** @description System-mode reads and writes. */
    private without sharing class SystemAccess {
        /**
         * @description The settings record.
         * @return the record, or null
         */
        public RLY_Work_Tracking__c settings() {
            RLY_Work_Tracking__c row = RLY_Work_Tracking__c.getOrgDefaults();
            return row == null || row.Id == null ? null : row;
        }

        /**
         * @description Inserts or updates the org default row.
         * @param row the settings
         */
        public void upsertSettings(RLY_Work_Tracking__c row) {
            RLY_Work_Tracking__c current = settings();
            if (current != null) {
                row.Id = current.Id;
                Database.update(row, true, AccessLevel.SYSTEM_MODE);
            } else {
                row.SetupOwnerId = UserInfo.getOrganizationId();
                Database.insert(row, true, AccessLevel.SYSTEM_MODE);
            }
        }

        /**
         * @description Rows of some releases.
         * @param releaseIds the releases
         * @return the rows
         */
        public List<RLY_Work_Item__c> forReleases(Set<Id> releaseIds) {
            return [SELECT Id, Release__c, Ticket__c, Key__c, Posted_State__c, Sync_Status__c, Sync_Message__c, Synced_On__c
                    FROM RLY_Work_Item__c WHERE Release__c IN :releaseIds WITH SYSTEM_MODE ORDER BY Ticket__c LIMIT :MAX_ROWS];
        }

        /**
         * @description The newest rows with their releases.
         * @return the rows
         */
        public List<RLY_Work_Item__c> recent() {
            return [SELECT Id, Release__c, Ticket__c, Key__c, Posted_State__c, Sync_Status__c, Sync_Message__c, Synced_On__c, CreatedDate,
                           Release__r.Name, Release__r.Title__c, Release__r.Status__c, Release__r.Release_Type__c, Release__r.Is_Hotfix__c,
                           Release__r.Target_Org__c, Release__r.Target_Org__r.Name, Release__r.Source_Org__r.Name, Release__r.Error_Message__c,
                           Release__r.Approval_Status__c, Release__r.Rollback_Status__c, Release__r.CreatedDate, Release__r.LastModifiedDate,
                           Release__r.CreatedBy.Name
                    FROM RLY_Work_Item__c WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT :MAX_ROWS];
        }

        /**
         * @description Releases with what the work items read.
         * @param ids the releases
         * @return the releases
         */
        public List<RLY_Release__c> releases(Set<Id> ids) {
            return [SELECT Id, Name, Title__c, Status__c, Release_Type__c, Is_Hotfix__c, Work_Items__c, Error_Message__c,
                           Approval_Status__c, Rollback_Status__c, Source_Org__c, Source_Org__r.Name, Target_Org__c, Target_Org__r.Name,
                           Target_Org__r.Role__c, Source_Branch__c
                    FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE LIMIT 200];
        }

        /**
         * @description Saves rows, removes the dropped ones and the release's list.
         * @param rows the rows
         * @param gone the dropped rows
         * @param rel the release, or null
         */
        public void save(List<RLY_Work_Item__c> rows, List<RLY_Work_Item__c> gone, RLY_Release__c rel) {
            if (gone != null && !gone.isEmpty()) {
                Database.delete(gone, true, AccessLevel.SYSTEM_MODE);
            }
            if (rows != null && !rows.isEmpty()) {
                Database.upsert(rows, RLY_Work_Item__c.Key__c, true, AccessLevel.SYSTEM_MODE);
            }
            if (rel != null) {
                Database.update(new RLY_Release__c(Id = rel.Id, Work_Items__c = rel.Work_Items__c), true, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
