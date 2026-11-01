/**
 * @description The per-org settings saveOrg takes besides sign-in and approval (RlyOrgController): Hotfixes need two
 * approvers, the code scan choice (Follow the Git connection, Always scan or Don't scan: RlyScanRule), and a back
 * promote org's When and Approve before syncing. Only the fields the page sends are copied (the
 * Pipeline tab saves When and Approve before syncing with saveBackPromoteOrg), so an org saved without them keeps what
 * it has; a new back promote org syncs when an admin clicks Sync now.
 */
public with sharing class RlyOrgSettings {

    private static final String SCAN_KEY = 'Code_Scan__c';

    /**
     * @description Copies the two-approver, code scan and back promote settings the page sent onto the row to save. Only keys
     * present in the JSON count: a deserialized record can't tell a missing field from a default.
     * @param row the row to save
     * @param orgJson the JSON the page sent
     */
    public static void apply(RLY_Org__c row, String orgJson) {
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(orgJson);
        if (sent.containsKey('Hotfix_Two_Approvers__c')) {
            row.Hotfix_Two_Approvers__c = sent.get('Hotfix_Two_Approvers__c') == true;
        }
        Object whenValue = sent.get('Back_Promote_When__c');
        if (whenValue != null && String.isNotBlank(String.valueOf(whenValue))) {
            row.Back_Promote_When__c = String.valueOf(whenValue);
        } else if (sent.containsKey('Back_Promote_When__c') || (row.Id == null && row.Role__c == RlyBackPromote.ROLE)) {
            row.Back_Promote_When__c = RlyBackPromote.WHEN_MANUAL;
        }
        if (sent.containsKey('Back_Promote_Approval__c')) {
            row.Back_Promote_Approval__c = sent.get('Back_Promote_Approval__c') == true;
        }
        if (sent.containsKey(SCAN_KEY)) {
            row.Code_Scan__c = scanChoice(sent.get(SCAN_KEY));
        }
    }

    // Follow, On or Off; blank follows the Git connection.
    private static String scanChoice(Object value) {
        String choice = value == null ? '' : String.valueOf(value).trim();
        if (String.isBlank(choice)) {
            return RlyScanRule.FOLLOW;
        }
        if (!RlyScanRule.CHOICES.contains(choice)) {
            String message = 'Pick a code scan choice: Follow the Git connection, Always scan or Don\'t scan.';
            AuraHandledException e = new AuraHandledException(message);
            e.setMessage(message);
            throw e;
        }
        return choice;
    }
}
