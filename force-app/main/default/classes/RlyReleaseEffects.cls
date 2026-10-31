/**
 * @description What follows from saving releases (RlyReleaseStore.saveAll), DML only: a promotion that is rejected,
 * fails or is closed frees the releases it carried (Promoted_In__c cleared, so they can be promoted again), and a back
 * promote sync keeps its org's Sync_Status__c and Synced_On__c (RlyBackPromoteRun.orgResult).
 */
public with sharing class RlyReleaseEffects {

    private static final Set<String> ENDS_PROMOTION = new Set<String>{ 'Rejected', 'Failed', 'Closed' };

    /**
     * @description Applies the effects of the saved releases.
     * @param rels the releases, as saved (with Release_Type__c)
     */
    public static void afterSave(List<RLY_Release__c> rels) {
        Set<Id> endedPromotions = new Set<Id>();
        Map<Id, RLY_Org__c> orgs = new Map<Id, RLY_Org__c>();
        for (RLY_Release__c rel : rels) {
            String relType = RlyPromotion.typeOf(rel);
            if (relType == RlyPromotion.TYPE_PROMOTION && ENDS_PROMOTION.contains(rel.Status__c)) {
                endedPromotions.add(rel.Id);
            } else if (relType == RlyPromotion.TYPE_BACK_PROMOTE) {
                RLY_Org__c o = RlyBackPromoteRun.orgResult(rel);
                if (o != null) {
                    orgs.put(o.Id, o);
                }
            }
        }
        RlyPromoteStore.releaseCarried(endedPromotions);
        RlyPromoteStore.saveOrgs(orgs.values());
    }
}
