/**
 * @description The org and branch a compare is with (RlyCompareRun in the hub, RlyComparePipeline in the pipeline): the
 * first stage, or the route org whose branch the page asked for, written exactly.
 */
public with sharing class RlyCompareTarget {

    /**
     * @description The org a compare is with.
     * @param source the developer org
     * @param targetBranch the branch asked for (blank: the first stage's)
     * @return the org, with its branch
     */
    public static RLY_Org__c of(RLY_Org__c source, String targetBranch) {
        RLY_Org__c firstStage = RlyRaiseRoute.target(source);
        String asked = String.isBlank(targetBranch) ? firstStage.Branch__c.trim() : targetBranch.trim();
        if (asked.equals(firstStage.Branch__c.trim())) {
            return firstStage;
        }
        for (RLY_Org__c o : RlyReleaseStore.routeOrgs()) {
            if (String.isNotBlank(o.Branch__c) && asked.equals(o.Branch__c.trim())) {
                return o;
            }
        }
        throw new RlyReleaseException('Compare with the branch of a stage or the hub.');
    }
}
