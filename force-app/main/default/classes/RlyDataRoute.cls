/**
 * @description Data runs along the route (build 59, D30): each org's place from the top, and which way a run may go.
 */
public with sharing class RlyDataRoute {

    /**
     * @description Each org's place on the route, from the top: the hub 0, the stages from the last down, every
     * developer org on the bottom step (build 59, D30).
     * @param orgs the pipeline's orgs
     * @return the place by org id
     */
    public static Map<Id, Integer> ranks(List<RLY_Org__c> orgs) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        Integer step = 0;
        for (RLY_Org__c o : RlySyncRoute.topDown(orgs)) {
            out.put(o.Id, step);
            if (o.Role__c != 'Developer') {
                step++;
            }
        }
        return out;
    }

    /**
     * @description Send up goes to an org higher on the route, Copy down to one lower: never the source's own step
     * (Refill repeats a load).
     * @param direction Up, Down or Refill
     * @param source the source org
     * @param target the target org
     */
    public static void checkDirection(String direction, RLY_Org__c source, RLY_Org__c target) {
        Map<Id, Integer> rank = ranks(RlyDataStore.orgs());
        Integer fromRank = rank.get(source.Id);
        Integer toRank = rank.get(target.Id);
        if (fromRank == null || toRank == null) {
            return;
        }
        if (direction == RlyDataRuns.UP && toRank >= fromRank) {
            throw new RlyReleaseException('Send up goes to an org higher on the route than ' + source.Name + '.');
        }
        if (direction == RlyDataRuns.DOWN && toRank <= fromRank) {
            throw new RlyReleaseException('Copy down goes to an org lower on the route than ' + source.Name + '.');
        }
    }
}
