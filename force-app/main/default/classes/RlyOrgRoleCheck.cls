/**
 * @description The role rules for registering an org: Release Relay runs in one production org (role Hub), so there is
 * only one such org, it keeps that role, and its Salesforce environment is always Production.
 */
public with sharing class RlyOrgRoleCheck {

    /** @description The role of the production org Release Relay runs in. */
    public static final String ROLE_PRODUCTION_ORG = 'Hub';
    /** @description That org's Salesforce environment. */
    public static final String ENV_PRODUCTION = 'Production';

    /**
     * @description What stops this save, if anything: a second org with the role, or that org losing it.
     * @param input the details sent
     * @param saved the org as saved (null for a new org)
     * @return the problem as a sentence, or null when the save may go on
     */
    public static String problem(RLY_Org__c input, RLY_Org__c saved) {
        if (saved != null && saved.Role__c == ROLE_PRODUCTION_ORG && input.Role__c != ROLE_PRODUCTION_ORG) {
            return 'The hub keeps its role: there must always be one hub.';
        }
        String takenBy = input.Role__c == ROLE_PRODUCTION_ORG ? new Data().otherName(input.Id) : null;
        return takenBy == null ? null : takenBy + ' is already the hub. There is only one hub: edit ' + takenBy + ' instead.';
    }

    /**
     * @description The environment to save: Production for that org, else what was sent (blank as null).
     * @param input the details sent
     * @return the environment, or null
     */
    public static String environmentOf(RLY_Org__c input) {
        if (input.Role__c == ROLE_PRODUCTION_ORG) {
            return ENV_PRODUCTION;
        }
        return String.isBlank(input.Environment__c) ? null : input.Environment__c;
    }

    /** @description Registered orgs are shared records: read in system mode (callers check the admin permission). */
    private without sharing class Data {

        /**
         * @description The name of the org with the role when it isn't this one.
         * @param exceptId the org being saved, or null
         * @return its name, or null when there's none
         */
        public String otherName(Id exceptId) {
            List<RLY_Org__c> rows = [SELECT Name FROM RLY_Org__c WHERE Role__c = :ROLE_PRODUCTION_ORG AND Id != :exceptId WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0].Name;
        }
    }
}
