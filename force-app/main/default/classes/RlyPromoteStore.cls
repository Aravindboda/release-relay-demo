/**
 * @description Data access for promotions and back promotes. Releases and registered orgs are shared hub records: the
 * flow reads and updates them for every Release Relay user, in system mode, in the private inner without sharing
 * class. Callers check who may do what first (RlyPromoteController, RlyBackPromote).
 */
public with sharing class RlyPromoteStore {

    /**
     * @description Releases deployed to these stages and waiting to be promoted: deployed, merged (or with manual steps
     * only: no merge commit), not carried by a promotion yet, not back promotes. Hotfixes first, then oldest deploy first.
     * @param stageIds the stage orgs
     * @return the releases
     */
    public static List<RLY_Release__c> readyIn(Set<Id> stageIds) {
        return new SystemAccess().queryReady(stageIds);
    }

    /**
     * @description Releases by Id, oldest deploy first.
     * @param ids the releases
     * @return the releases (those that exist)
     */
    public static List<RLY_Release__c> byIds(Set<Id> ids) {
        return ids.isEmpty() ? new List<RLY_Release__c>() : new SystemAccess().queryByIds(ids);
    }

    /**
     * @description The components of several releases.
     * @param releaseIds the releases
     * @return the items
     */
    public static List<RLY_Release_Item__c> itemsOf(Set<Id> releaseIds) {
        return new SystemAccess().queryItems(releaseIds);
    }

    /**
     * @description Saves a new promotion with its items and marks the releases it carries.
     * @param promotion the promotion
     * @param items its items (Release__c is set here)
     * @param carriedIds the releases it carries
     */
    public static void insertPromotion(RLY_Release__c promotion, List<RLY_Release_Item__c> items, Set<Id> carriedIds) {
        new SystemAccess().writePromotion(promotion, items, carriedIds);
    }

    /**
     * @description Frees the releases these promotions carried, so they can be promoted again.
     * @param promotionIds the promotions
     */
    public static void releaseCarried(Set<Id> promotionIds) {
        if (!promotionIds.isEmpty()) {
            new SystemAccess().freeCarried(promotionIds);
        }
    }

    /**
     * @description The registered back promote orgs, by name.
     * @return the orgs, without sign-in fields
     */
    public static List<RLY_Org__c> backPromoteOrgs() {
        return new SystemAccess().queryBackPromoteOrgs();
    }

    /**
     * @description The hub org (role Hub).
     * @return the hub, or null
     */
    public static RLY_Org__c hub() {
        return new SystemAccess().queryHub();
    }

    /**
     * @description Releases deployed to the hub (not back promotes), oldest deploy first.
     * @param hubId the hub org
     * @return up to 500 releases
     */
    public static List<RLY_Release__c> hubDeployed(Id hubId) {
        return new SystemAccess().queryHubDeployed(hubId);
    }

    /**
     * @description The latest back promote releases, newest first.
     * @return up to 200 releases
     */
    public static List<RLY_Release__c> latestSyncs() {
        return new SystemAccess().querySyncs();
    }

    /**
     * @description Back promote releases waiting to be started (Submitted) or running (Deploying).
     * @return up to 5 release Ids, oldest first
     */
    public static List<Id> openSyncIds() {
        List<Id> out = new List<Id>();
        for (RLY_Release__c r : new SystemAccess().openSyncs()) {
            out.add(r.Id);
        }
        return out;
    }

    /**
     * @description Saves new back promote releases.
     * @param syncs the releases
     */
    public static void insertSyncs(List<RLY_Release__c> syncs) {
        if (!syncs.isEmpty()) {
            new SystemAccess().insertRows(syncs);
        }
    }

    /**
     * @description Saves org fields (back promote settings and results).
     * @param orgs the rows to save
     */
    public static void saveOrgs(List<RLY_Org__c> orgs) {
        if (!orgs.isEmpty()) {
            new SystemAccess().updateOrgs(orgs);
        }
    }

    /**
     * @description Turns back promote on or off on the Git connection.
     * @param conn the connection row to save
     */
    public static void saveGit(RLY_Git_Connection__c conn) {
        new SystemAccess().updateGit(conn);
    }

    /** @description Shared hub records, read and written in system mode for the flow. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyPromoteStore.readyIn.
         * @param stageIds the stages
         * @return the releases
         */
        public List<RLY_Release__c> queryReady(Set<Id> stageIds) {
            return [SELECT Id, Name, Title__c, Target_Org__c, Is_Hotfix__c, Hotfix_Reason__c, Last_Synced__c, CreatedBy.Name,
                           Test_Classes__c, Component_Count__c, Merge_Commit__c, Deletion_Count__c, Manual_Only__c
                    FROM RLY_Release__c
                    WHERE Target_Org__c IN :stageIds AND Status__c = 'Deployed' AND (Merge_Commit__c != null OR Manual_Only__c = true)
                        AND Promoted_In__c = null AND Release_Type__c != 'Back_Promote'
                    WITH SYSTEM_MODE ORDER BY Is_Hotfix__c DESC, Last_Synced__c ASC LIMIT 500];
        }

        /**
         * @description See RlyPromoteStore.byIds.
         * @param ids the releases
         * @return the releases
         */
        public List<RLY_Release__c> queryByIds(Set<Id> ids) {
            return [SELECT Id, Name, Title__c, Target_Org__c, Is_Hotfix__c, Hotfix_Reason__c, Last_Synced__c, Test_Classes__c,
                           Merge_Commit__c, Promoted_In__c, Status__c, Release_Type__c, Deletions__c, Deletion_Count__c, Flow_Actions__c,
                           Manual_Only__c
                    FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE ORDER BY Last_Synced__c ASC LIMIT 500];
        }

        /**
         * @description See RlyPromoteStore.itemsOf.
         * @param releaseIds the releases
         * @return the items
         */
        public List<RLY_Release_Item__c> queryItems(Set<Id> releaseIds) {
            return [SELECT Id, Release__c, Metadata_Type__c, Component_Name__c, Change_Type__c, Source__c, Is_Deletion__c FROM RLY_Release_Item__c
                    WHERE Release__c IN :releaseIds WITH SYSTEM_MODE ORDER BY Metadata_Type__c, Component_Name__c LIMIT 5000];
        }

        /**
         * @description See RlyPromoteStore.insertPromotion.
         * @param promotion the promotion
         * @param items its items
         * @param carriedIds the releases it carries
         */
        public void writePromotion(RLY_Release__c promotion, List<RLY_Release_Item__c> items, Set<Id> carriedIds) {
            insert as system promotion;
            for (RLY_Release_Item__c i : items) {
                i.Release__c = promotion.Id;
            }
            insert as system items;
            List<RLY_Release__c> carried = new List<RLY_Release__c>();
            for (Id carriedId : carriedIds) {
                carried.add(new RLY_Release__c(Id = carriedId, Promoted_In__c = promotion.Id));
            }
            update as system carried;
        }

        /**
         * @description See RlyPromoteStore.releaseCarried.
         * @param promotionIds the promotions
         */
        public void freeCarried(Set<Id> promotionIds) {
            List<RLY_Release__c> rows = [SELECT Id FROM RLY_Release__c WHERE Promoted_In__c IN :promotionIds WITH SYSTEM_MODE LIMIT 500];
            for (RLY_Release__c r : rows) {
                r.Promoted_In__c = null;
            }
            update as system rows;
        }

        /**
         * @description See RlyPromoteStore.backPromoteOrgs.
         * @return the orgs
         */
        public List<RLY_Org__c> queryBackPromoteOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Git_Environment__c, Environment__c, Status__c, Back_Promote_When__c,
                           Back_Promote_Approval__c, Synced_On__c, Sync_Status__c, CreatedDate
                    FROM RLY_Org__c WHERE Role__c = 'Back_Promote' WITH SYSTEM_MODE ORDER BY Name LIMIT 50];
        }

        /**
         * @description See RlyPromoteStore.hub.
         * @return the hub, or null
         */
        public RLY_Org__c queryHub() {
            List<RLY_Org__c> rows = [SELECT Id, Name, Branch__c, Git_Environment__c FROM RLY_Org__c WHERE Role__c = 'Hub'
                                     WITH SYSTEM_MODE ORDER BY Name LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description See RlyPromoteStore.hubDeployed.
         * @param hubId the hub
         * @return the releases
         */
        public List<RLY_Release__c> queryHubDeployed(Id hubId) {
            return [SELECT Id, Name, Last_Synced__c, Release_Type__c, Carried_Releases__c, Flow_Actions__c FROM RLY_Release__c
                    WHERE Target_Org__c = :hubId AND Status__c = 'Deployed' AND Release_Type__c != 'Back_Promote'
                    WITH SYSTEM_MODE ORDER BY Last_Synced__c ASC LIMIT 500];
        }

        /**
         * @description See RlyPromoteStore.latestSyncs.
         * @return the releases
         */
        public List<RLY_Release__c> querySyncs() {
            return [SELECT Id, Name, Status__c, Target_Org__c, Target_Org__r.Name, CreatedDate, Error_Message__c
                    FROM RLY_Release__c WHERE Release_Type__c = 'Back_Promote'
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description See RlyPromoteStore.openSyncIds.
         * @return the releases
         */
        public List<RLY_Release__c> openSyncs() {
            return [SELECT Id FROM RLY_Release__c WHERE Release_Type__c = 'Back_Promote' AND Status__c IN ('Submitted', 'Deploying')
                    WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 5];
        }

        /**
         * @description See RlyPromoteStore.insertSyncs.
         * @param rows the releases
         */
        public void insertRows(List<RLY_Release__c> rows) {
            insert as system rows;
        }

        /**
         * @description See RlyPromoteStore.saveOrgs.
         * @param rows the orgs
         */
        public void updateOrgs(List<RLY_Org__c> rows) {
            update as system rows;
        }

        /**
         * @description See RlyPromoteStore.saveGit.
         * @param conn the connection
         */
        public void updateGit(RLY_Git_Connection__c conn) {
            update as system conn;
        }
    }
}
