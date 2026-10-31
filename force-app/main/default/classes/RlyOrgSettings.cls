/**
 * @description The per-org settings saveOrg takes besides sign-in and approval (RlyOrgController): Hotfixes need two
 * approvers, and a back promote org's When and Approve before syncing. Only the fields the page sends are copied (the
 * Pipeline tab saves When and Approve before syncing with saveBackPromoteOrg), so an org saved without them keeps what
 * it has; a new back promote org syncs when an admin clicks Sync now.
 */
public with sharing class RlyOrgSettings {

    /**
     * @description Copies the two-approver and back promote settings the page sent onto the row to save.
     * @param row the row to save
     * @param input what the page sent
     */
    public static void apply(RLY_Org__c row, RLY_Org__c input) {
        if (input.isSet('Hotfix_Two_Approvers__c')) {
            row.Hotfix_Two_Approvers__c = input.Hotfix_Two_Approvers__c == true;
        }
        if (input.isSet('Back_Promote_When__c')) {
            row.Back_Promote_When__c = String.isBlank(input.Back_Promote_When__c) ? RlyBackPromote.WHEN_MANUAL : input.Back_Promote_When__c;
        } else if (input.Id == null && input.Role__c == RlyBackPromote.ROLE) {
            row.Back_Promote_When__c = RlyBackPromote.WHEN_MANUAL;
        }
        if (input.isSet('Back_Promote_Approval__c')) {
            row.Back_Promote_Approval__c = input.Back_Promote_Approval__c == true;
        }
    }
}
