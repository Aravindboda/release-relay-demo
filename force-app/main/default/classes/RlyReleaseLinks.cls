/**
 * @description What the release page shows about a release's links to others: hotfix and type, the releases a promotion
 * carries, the promotion carrying it, how the branches were merged back after the merge (Back_Merge_Result__c, stage
 * branches then developer branches), where a deploy to the hub was sent (back promote) and the second-approver state.
 */
public with sharing class RlyReleaseLinks {

    /**
     * @description Fills the page's link fields; a hub deploy whose back promote syncs are queued or running keeps the
     * page checking.
     * @param d the detail, with its release
     */
    public static void fill(RlyReleasesController.Detail d) {
        RLY_Release__c rel = d.release;
        d.isHotfix = RlyHotfix.isHotfix(rel);
        d.hotfixReason = rel.Hotfix_Reason__c;
        d.releaseType = RlyPromotion.typeOf(rel);
        for (RLY_Release__c r : RlyCarried.releases(rel)) {
            d.carried.add(toCarried(r));
        }
        d.promotedInId = rel.Promoted_In__c;
        d.promotedInName = rel.Promoted_In__r == null ? null : rel.Promoted_In__r.Name;
        d.backMerge = backMerge(rel.Back_Merge_Result__c);
        RlyBackPromoteSummary s = RlyBackPromoteSummary.forRelease(rel);
        d.backPromote = s.text;
        d.running = d.running || s.pending;
        d.needsSecondApprover = RlyTwoApprovers.waitsForSecond(rel);
        d.firstApprover = d.needsSecondApprover && rel.Approved_By__r != null ? rel.Approved_By__r.Name : null;
    }

    private static RlyReleasesController.CarriedRelease toCarried(RLY_Release__c r) {
        RlyReleasesController.CarriedRelease c = new RlyReleasesController.CarriedRelease();
        c.id = r.Id;
        c.name = r.Name;
        c.title = r.Title__c;
        c.isHotfix = r.Is_Hotfix__c == true;
        return c;
    }

    /**
     * @description The back-merge result, each branch marked Stage or Developer.
     * @param resultJson Back_Merge_Result__c
     * @return the branches (empty when there's none or it can't be read)
     */
    public static List<RlyReleasesController.BranchSync> backMerge(String resultJson) {
        List<RlyReleasesController.BranchSync> out = new List<RlyReleasesController.BranchSync>();
        List<Object> rows;
        try {
            rows = String.isBlank(resultJson) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(resultJson);
        } catch (Exception e) {
            return out;
        }
        Set<String> stages = new Set<String>(RlyPipelineOptions.stageBranches());
        for (Object o : rows) {
            Map<String, Object> m = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            RlyReleasesController.BranchSync b = new RlyReleasesController.BranchSync();
            b.branch = m.get('branch') == null ? null : String.valueOf(m.get('branch'));
            b.status = m.get('status') == null ? null : String.valueOf(m.get('status'));
            b.message = m.get('message') == null ? null : String.valueOf(m.get('message'));
            b.kind = stages.contains(b.branch) ? 'Stage' : 'Developer';
            out.add(b);
        }
        return out;
    }

    /**
     * @description The names of the releases these promotions carry.
     * @param rels the releases (promotions among them)
     * @return carried release Id to its number
     */
    public static Map<Id, String> carriedNames(List<RLY_Release__c> rels) {
        Set<Id> ids = new Set<Id>();
        for (RLY_Release__c r : rels) {
            ids.addAll(RlyCarried.ids(r));
        }
        Map<Id, String> out = new Map<Id, String>();
        for (RLY_Release__c r : RlyPromoteStore.byIds(ids)) {
            out.put(r.Id, r.Name);
        }
        return out;
    }
}
