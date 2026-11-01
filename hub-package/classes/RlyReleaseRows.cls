/**
 * @description Builds the release list's rows (RlyReleasesController.Row) for the Releases and Approvals tabs.
 */
public with sharing class RlyReleaseRows {

    /**
     * @description One row per release, with the release numbers a promotion carries.
     * @param rels the releases, as RlyReleaseStore or RlyReleaseQuery read them
     * @return the rows, in the same order
     */
    public static List<RlyReleasesController.Row> build(List<RLY_Release__c> rels) {
        List<RlyReleasesController.Row> out = new List<RlyReleasesController.Row>();
        Map<Id, String> names = RlyReleaseLinks.carriedNames(rels);
        for (RLY_Release__c r : rels) {
            RlyReleasesController.Row row = toRow(r);
            for (Id carriedId : RlyCarried.ids(r)) {
                if (names.containsKey(carriedId)) {
                    row.carried.add(names.get(carriedId));
                }
            }
            out.add(row);
        }
        return out;
    }

    private static RlyReleasesController.Row toRow(RLY_Release__c r) {
        RlyReleasesController.Row row = new RlyReleasesController.Row();
        row.id = r.Id;
        row.name = r.Name;
        row.title = r.Title__c;
        row.status = r.Status__c;
        row.source = r.Source_Org__r.Name;
        row.target = r.Target_Org__r.Name + ' · ' + r.Target_Branch__c;
        row.raisedBy = r.CreatedBy.Name;
        row.raisedOn = r.CreatedDate;
        row.components = r.Component_Count__c;
        row.scan = r.Scan_Status__c;
        row.validation = r.Validation_Status__c;
        row.hotfix = RlyHotfix.isHotfix(r);
        row.isHotfix = row.hotfix;
        row.hotfixReason = r.Hotfix_Reason__c;
        row.releaseType = RlyPromotion.typeOf(r);
        row.deletionCount = r.Deletion_Count__c == null ? 0 : r.Deletion_Count__c.intValue();
        row.raisedById = r.CreatedById;
        row.lastChecked = r.Last_Synced__c;
        return row;
    }
}
