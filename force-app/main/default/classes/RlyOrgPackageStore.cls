/**
 * @description Build 55: data access for the orgs' installed packages (RLY_Org__c Packages__c, Packages_Checked__c,
 * Packages_Off__c) and the Can raise releases switch (Can_Raise__c). Registered orgs are shared hub records: every
 * Release Relay user's run reads them (the options a run starts with), so the read runs in system mode in the private
 * inner without sharing class, and a save writes only these fields.
 */
public with sharing class RlyOrgPackageStore {

    /** @description The roles of the orgs packages are read for: the route, its developer orgs and the back promote orgs. */
    public static final Set<String> ROLES = new Set<String>{ 'Developer', 'Stage', 'Hub', 'Back_Promote' };

    // Read once per transaction (a run's options, the matrix): saves empty it.
    private static List<RLY_Org__c> cached;

    /**
     * @description The registered orgs with their package fields (never the sign-in fields), by name.
     * @return the orgs
     */
    public static List<RLY_Org__c> orgs() {
        if (cached == null) {
            cached = new SystemAccess().readOrgs();
        }
        return cached;
    }

    /**
     * @description Saves the package fields and Can_Raise__c of these orgs (only the fields set on each row).
     * @param rows the org rows, each with its Id
     */
    public static void save(List<RLY_Org__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        List<RLY_Org__c> clean = new List<RLY_Org__c>();
        for (RLY_Org__c r : rows) {
            clean.add(onlyPackageFields(r));
        }
        new SystemAccess().updateRows(clean);
        cached = null;
    }

    // A row with the Id and only the fields this store writes, as set on the row.
    private static RLY_Org__c onlyPackageFields(RLY_Org__c r) {
        Map<String, Object> populated = r.getPopulatedFieldsAsMap();
        RLY_Org__c out = new RLY_Org__c(Id = r.Id);
        for (String f : new List<String>{ 'Packages__c', 'Packages_Checked__c', 'Packages_Off__c', 'Can_Raise__c' }) {
            if (populated.containsKey(f)) {
                out.put(f, populated.get(f));
            }
        }
        return out;
    }

    /** @description Registered orgs are shared hub records: read and written in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyOrgPackageStore.orgs.
         * @return the orgs, by name
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Status__c, Environment__c, Packages__c,
                           Packages_Checked__c, Packages_Off__c, Can_Raise__c
                    FROM RLY_Org__c WHERE Role__c IN :ROLES WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Updates the rows.
         * @param rows the rows
         */
        public void updateRows(List<RLY_Org__c> rows) {
            update as system rows;
        }
    }
}
