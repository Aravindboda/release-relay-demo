/**
 * @description Reads and saves the Credentials dashboard (build 49): RLY_Credential_Status__c rows, upserted by Key__c,
 * and the registered orgs with their sign-in fields. Shared hub records, read and saved in system mode in the private
 * inner class; RlyCredentialCheck decides what is saved, always after its callouts.
 */
public with sharing class RlyCredentialStore {

    /**
     * @description Every row, by kind and name.
     * @return the rows
     */
    public static List<RLY_Credential_Status__c> rows() {
        return new Data().readRows();
    }

    /**
     * @description Every row by its key.
     * @return key to row
     */
    public static Map<String, RLY_Credential_Status__c> byKey() {
        Map<String, RLY_Credential_Status__c> out = new Map<String, RLY_Credential_Status__c>();
        for (RLY_Credential_Status__c r : rows()) {
            out.put(r.Key__c, r);
        }
        return out;
    }

    /**
     * @description Every registered org with its sign-in fields.
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> orgs() {
        return new Data().readOrgs();
    }

    /**
     * @description Whether a Named Credential exists in the hub.
     * @param developerName its API name
     * @return true when it exists
     */
    public static Boolean hasNamedCredential(String developerName) {
        return new Data().countNamedCredentials(developerName) > 0;
    }

    /**
     * @description Whether a user with this username is active in the hub (the hub's own integration user).
     * @param username the username
     * @return true, false, or null when there is no such user
     */
    public static Boolean hubUserActive(String username) {
        List<User> rows = new Data().readUser(username);
        return rows.isEmpty() ? null : rows[0].IsActive;
    }

    /**
     * @description Saves the rows (by Key__c) and removes the ones gone. No callout may follow in the same request.
     * @param upserts the rows to save
     * @param removals the rows to remove
     */
    public static void save(List<RLY_Credential_Status__c> upserts, List<RLY_Credential_Status__c> removals) {
        Data data = new Data();
        if (upserts != null && !upserts.isEmpty()) {
            data.upsertRows(upserts);
        }
        if (removals != null && !removals.isEmpty()) {
            data.deleteRows(removals);
        }
    }

    /** @description Credential rows, orgs and users, in system mode. */
    private without sharing class Data {

        /**
         * @description See RlyCredentialStore.rows.
         * @return the rows
         */
        public List<RLY_Credential_Status__c> readRows() {
            return [SELECT Id, Name, Key__c, Kind__c, Org__c, Org__r.Name, Expires_On__c, Days_Left__c, Status__c, Message__c,
                           Last_Checked__c, Last_OK__c
                    FROM RLY_Credential_Status__c WITH SYSTEM_MODE ORDER BY Kind__c, Name LIMIT 1000];
        }

        /**
         * @description See RlyCredentialStore.orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Client_Id__c, Consumer_Key__c, Certificate__c,
                           Status__c, Last_Checked__c, Slack_Channel__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Named Credentials with this name.
         * @param developerName the name
         * @return how many
         */
        public Integer countNamedCredentials(String developerName) {
            return [SELECT COUNT() FROM NamedCredential WHERE DeveloperName = :developerName WITH SYSTEM_MODE];
        }

        /**
         * @description The hub user with this username.
         * @param username the username
         * @return the user, or none
         */
        public List<User> readUser(String username) {
            return [SELECT Id, IsActive FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
        }

        /**
         * @description Upserts by Key__c.
         * @param rows the rows
         */
        public void upsertRows(List<RLY_Credential_Status__c> rows) {
            Database.upsert(rows, RLY_Credential_Status__c.Key__c, true, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description Deletes rows.
         * @param rows the rows
         */
        public void deleteRows(List<RLY_Credential_Status__c> rows) {
            delete as system rows;
        }
    }
}
