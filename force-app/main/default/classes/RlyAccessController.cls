/**
 * @description Roles and access on the Pipeline tab (build 49): the "Production approval needs the add-on" setting
 * (RlyProdApproval) with who holds the Production Approver add-on, and the admins' banner while it is off.
 */
public with sharing class RlyAccessController {

    /**
     * @description The production approval setting.
     * @return the view
     */
    @AuraEnabled
    public static RlyProdApproval.View prodApproval() {
        try {
            return RlyProdApproval.view();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Something went wrong: ');
        }
    }

    /**
     * @description Turns production approval's add-on rule on or off (admins).
     * @param state On (approving production needs the add-on) or Off
     * @return the view as saved
     */
    @AuraEnabled
    public static RlyProdApproval.View saveProdApproval(String state) {
        try {
            RlyHubGuard.requireHub();
            return RlyProdApproval.save(state);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Something went wrong: ');
        }
    }
}
