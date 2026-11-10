/**
 * @description Sync status: the tab's data (RlySyncController.board): the route orgs from the top down with their latest
 * check, the route's pairs, the latest route check and the latest installed packages.
 */
public with sharing class RlySyncBoard {

    /** @description An org card. */
    public class OrgCard {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Developer, Stage or Hub. */
        @AuraEnabled public String role;
        /** @description Its branch. */
        @AuraEnabled public String branch;
        /** @description The pipeline signs in to it (stages and the hub). */
        @AuraEnabled public Boolean signIn = false;
        /** @description Its latest check, or null. */
        @AuraEnabled public RlySyncResult.View check;
    }

    /** @description A pair of the route. */
    public class PairInfo {
        /** @description The higher org. */
        @AuraEnabled public Id higherId;
        /** @description Its name. */
        @AuraEnabled public String higherName;
        /** @description Its branch. */
        @AuraEnabled public String higherBranch;
        /** @description The lower org. */
        @AuraEnabled public Id lowerId;
        /** @description Its name. */
        @AuraEnabled public String lowerName;
        /** @description Its branch. */
        @AuraEnabled public String lowerBranch;
        /** @description The pipeline can deploy to the lower org (else back promote updates its branch only). */
        @AuraEnabled public Boolean lowerSignIn = false;
    }

    /** @description The tab's data. */
    public class Board {
        /** @description Back promote and push are offered (admins). */
        @AuraEnabled public Boolean canPromote = false;
        /** @description The route orgs from the top down. */
        @AuraEnabled public List<OrgCard> orgs = new List<OrgCard>();
        /** @description The route's pairs from the top down. */
        @AuraEnabled public List<PairInfo> pairs = new List<PairInfo>();
        /** @description The latest route check, or null. */
        @AuraEnabled public RlySyncResult.View route;
        /** @description The latest packages, or null. */
        @AuraEnabled public RlySyncPackages.Packages packages;
    }

    /**
     * @description The tab's data.
     * @return the board
     */
    public static Board build() {
        Board b = new Board();
        b.canPromote = RlyOrgController.isAdmin();
        List<RLY_Org__c> orgs = RlySyncStore.orgs();
        Latest latest = new Latest(RlySyncStore.latest());
        for (RLY_Org__c o : RlySyncRoute.topDown(orgs)) {
            b.orgs.add(card(o, latest.byOrg.get(o.Id)));
        }
        for (RlySyncRoute.Pair p : RlySyncRoute.pairs(orgs)) {
            b.pairs.add(pair(p));
        }
        b.route = latest.route == null ? null : RlySyncResult.view(latest.route);
        b.packages = latest.packages == null ? null : RlySyncPackages.saved(RlySyncStore.bySyncId(latest.packages.Sync_Id__c));
        return b;
    }

    /**
     * @description The first stage (lowest order), else the hub.
     * @param orgs the registered orgs
     * @return the org
     */
    public static RLY_Org__c firstStage(List<RLY_Org__c> orgs) {
        RLY_Org__c out;
        for (RLY_Org__c o : RlySyncRoute.topDown(orgs)) {
            if (o.Role__c == 'Stage' || (o.Role__c == 'Hub' && out == null)) {
                out = o;
            }
        }
        if (out == null) {
            throw new RlyReleaseException('Register a stage or the hub first (Pipeline tab).');
        }
        return out;
    }

    /** @description The newest check of each org, the newest route check and the newest packages. */
    private class Latest {
        /** @description The newest check of each org. */
        public Map<Id, RLY_Sync_Check__c> byOrg = new Map<Id, RLY_Sync_Check__c>();
        /** @description The newest route check. */
        public RLY_Sync_Check__c route;
        /** @description The newest packages. */
        public RLY_Sync_Check__c packages;

        /**
         * @description Sorts the checks (newest first).
         * @param checks the checks
         */
        public Latest(List<RLY_Sync_Check__c> checks) {
            for (RLY_Sync_Check__c c : checks) {
                add(c);
            }
        }

        private void add(RLY_Sync_Check__c c) {
            if (c.Kind__c == RlySyncStore.KIND_ORG) {
                if (c.Org__c != null && !byOrg.containsKey(c.Org__c)) {
                    byOrg.put(c.Org__c, c);
                }
            } else if (c.Kind__c == RlySyncStore.KIND_ROUTE) {
                route = route == null ? c : route;
            } else {
                packages = packages == null ? c : packages;
            }
        }
    }

    private static OrgCard card(RLY_Org__c o, RLY_Sync_Check__c check) {
        OrgCard c = new OrgCard();
        c.orgId = o.Id;
        c.name = o.Name;
        c.role = o.Role__c;
        c.branch = o.Branch__c == null ? null : o.Branch__c.trim();
        c.signIn = RlySyncRoute.hasSignIn(o);
        c.check = check == null ? null : RlySyncResult.view(check);
        return c;
    }

    private static PairInfo pair(RlySyncRoute.Pair p) {
        PairInfo x = new PairInfo();
        x.higherId = p.higher.Id;
        x.higherName = p.higher.Name;
        x.higherBranch = p.higher.Branch__c.trim();
        x.lowerId = p.lower.Id;
        x.lowerName = p.lower.Name;
        x.lowerBranch = p.lower.Branch__c.trim();
        x.lowerSignIn = RlySyncRoute.hasSignIn(p.lower);
        return x;
    }

}
