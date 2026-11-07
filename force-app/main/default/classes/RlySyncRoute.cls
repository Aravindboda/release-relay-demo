/**
 * @description Sync status: the route from the top down (the hub, then the stages from the last to the first, then the
 * developer orgs) and its pairs (each branch with the one below it; every developer org sits below the first stage). An
 * org has a pipeline sign-in when it is a stage or the hub with a Git environment: the pipeline checks those orgs itself;
 * developer orgs are read by the hub.
 */
public with sharing class RlySyncRoute {

    /** @description One pair: a higher org's branch over a lower one's. */
    public class Pair {
        /** @description The higher org. */
        public RLY_Org__c higher;
        /** @description The lower org. */
        public RLY_Org__c lower;

        /**
         * @description A pair.
         * @param higher the higher org
         * @param lower the lower org
         */
        public Pair(RLY_Org__c higher, RLY_Org__c lower) {
            this.higher = higher;
            this.lower = lower;
        }
    }

    /**
     * @description The route's orgs from the top down.
     * @param orgs the registered orgs with a branch (RlySyncStore.orgs)
     * @return the hub, the stages from the last to the first, then the developer orgs by name
     */
    public static List<RLY_Org__c> topDown(List<RLY_Org__c> orgs) {
        List<RLY_Org__c> hubs = new List<RLY_Org__c>();
        List<RLY_Org__c> devs = new List<RLY_Org__c>();
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Hub') {
                hubs.add(o);
            } else if (o.Role__c == 'Stage') {
                stages.add(o);
            } else {
                devs.add(o);
            }
        }
        List<RLY_Org__c> out = new List<RLY_Org__c>(hubs);
        out.addAll(byStageOrderDescending(stages));
        out.addAll(devs);
        return out;
    }

    /**
     * @description The route's pairs from the top down: hub over the last stage, each stage over the one before it, the
     * first stage (or the hub when there are no stages) over every developer org.
     * @param orgs the registered orgs with a branch
     * @return the pairs
     */
    public static List<Pair> pairs(List<RLY_Org__c> orgs) {
        List<RLY_Org__c> upper = new List<RLY_Org__c>();
        List<RLY_Org__c> devs = new List<RLY_Org__c>();
        for (RLY_Org__c o : topDown(orgs)) {
            if (o.Role__c == 'Developer') {
                devs.add(o);
            } else {
                upper.add(o);
            }
        }
        List<Pair> out = new List<Pair>();
        for (Integer i = 0; i + 1 < upper.size(); i++) {
            out.add(new Pair(upper[i], upper[i + 1]));
        }
        if (!upper.isEmpty()) {
            for (RLY_Org__c d : devs) {
                out.add(new Pair(upper[upper.size() - 1], d));
            }
        }
        return out;
    }

    /**
     * @description Whether the pipeline can sign in to an org (a stage or the hub with a Git environment).
     * @param org the org
     * @return true for stages and the hub with a Git environment
     */
    public static Boolean hasSignIn(RLY_Org__c org) {
        return org != null && (org.Role__c == 'Stage' || org.Role__c == 'Hub') && String.isNotBlank(org.Git_Environment__c);
    }

    /**
     * @description The route org with this Id.
     * @param orgs the orgs
     * @param orgId the Id (15 or 18 characters)
     * @return the org
     */
    public static RLY_Org__c find(List<RLY_Org__c> orgs, String orgId) {
        for (RLY_Org__c o : orgs) {
            if (String.isNotBlank(orgId) && (String.valueOf(o.Id) == orgId || String.valueOf(o.Id).left(15) == orgId)) {
                return o;
            }
        }
        throw new RlyReleaseException('Pick an org on the route.');
    }

    // Stages from the highest Stage_Order__c down (blank orders last), name breaking ties.
    private static List<RLY_Org__c> byStageOrderDescending(List<RLY_Org__c> stages) {
        List<RLY_Org__c> sorted = new List<RLY_Org__c>();
        for (RLY_Org__c s : stages) {
            Integer at = 0;
            while (at < sorted.size() && higherFirst(sorted[at], s)) {
                at++;
            }
            if (at == sorted.size()) {
                sorted.add(s);
            } else {
                sorted.add(at, s);
            }
        }
        return sorted;
    }

    // Whether a stays before b.
    private static Boolean higherFirst(RLY_Org__c a, RLY_Org__c b) {
        Decimal x = a.Stage_Order__c == null ? -1 : a.Stage_Order__c;
        Decimal y = b.Stage_Order__c == null ? -1 : b.Stage_Order__c;
        return x != y ? x > y : a.Name <= b.Name;
    }
}
