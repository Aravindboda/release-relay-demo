/**
 * @description Several Git connections (build 45): one route per connection, each a lane on the Pipeline tab. A lane
 * is the connection's developer orgs, then its stages in order, then the hub, which ends every route. Each lane gets
 * its own warnings (RlyRouteRules), plus one when the connection has no stage org.
 */
public with sharing class RlyRouteLanes {

    /** @description One connection's route. */
    public class Lane {
        /** @description The connection, or null when the hub has none. */
        @AuraEnabled public Id connectionId;
        /** @description The provider and repository, for example GitLab group/project. */
        @AuraEnabled public String label;
        /** @description The provider's name, for example GitLab. */
        @AuraEnabled public String provider;
        /** @description The main connection. */
        @AuraEnabled public Boolean isMain = false;
        /** @description Its developer orgs. */
        @AuraEnabled public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        /** @description Its stages in route order, the hub last. */
        @AuraEnabled public List<RLY_Org__c> stages = new List<RLY_Org__c>();
        /** @description What's missing from this route. */
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    /**
     * @description The lanes: one per connection (the main one first), or one lane without a connection.
     * @param conns the connections, the main one first
     * @param developers the developer orgs
     * @param stages the stages and the hub
     * @return the lanes
     */
    public static List<Lane> build(List<RLY_Git_Connection__c> conns, List<RLY_Org__c> developers, List<RLY_Org__c> stages) {
        List<Lane> out = new List<Lane>();
        Orgs orgs = new Orgs();
        orgs.mainId = conns.isEmpty() ? null : conns[0].Id;
        orgs.developers = developers;
        orgs.stages = stages;
        if (conns.isEmpty()) {
            out.add(lane(null, orgs));
            return out;
        }
        for (RLY_Git_Connection__c c : conns) {
            Lane l = lane(c, orgs);
            if (c.Active__c == true || !l.developers.isEmpty() || l.stages.size() > 1) {
                out.add(l);
            }
        }
        return out;
    }

    /**
     * @description Every lane's warnings, each once; with several lanes each starts with the connection's provider.
     * @param lanes the lanes
     * @return the warnings
     */
    public static List<String> allWarnings(List<Lane> lanes) {
        List<String> out = new List<String>();
        for (Lane l : lanes) {
            for (String w : l.warnings) {
                String text = lanes.size() > 1 && l.provider != null ? l.provider + ': ' + w : w;
                if (!out.contains(text)) {
                    out.add(text);
                }
            }
        }
        return out;
    }

    // The orgs every lane is built from.
    private class Orgs {
        public Id mainId;
        public List<RLY_Org__c> developers;
        public List<RLY_Org__c> stages;
    }

    private static Lane lane(RLY_Git_Connection__c c, Orgs orgs) {
        Lane l = new Lane();
        Id laneId = c == null ? null : c.Id;
        if (c != null) {
            l.connectionId = c.Id;
            l.isMain = c.Id == orgs.mainId;
            l.label = RlyPromoteConnection.nameOf(c);
            l.provider = RlyGitName.labelFor(c);
        }
        l.developers = onLane(orgs.developers, laneId, orgs.mainId);
        l.stages = RlyRouteRules.ordered(onLane(orgs.stages, laneId, orgs.mainId));
        l.warnings = RlyRouteRules.warnings(l.developers, l.stages);
        if (c != null && !hasStage(l.stages) && !l.developers.isEmpty()) {
            l.warnings.add((l.provider == null ? c.Provider__c : l.provider) + ' has no stage org: its developer orgs have nowhere to release to.');
        }
        return l;
    }

    // The orgs on the lane's connection; the hub is on every lane.
    private static List<RLY_Org__c> onLane(List<RLY_Org__c> orgs, Id laneId, Id mainId) {
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Hub' || RlyConnectionRoutes.connectionIdOf(o, mainId) == laneId) {
                out.add(o);
            }
        }
        return out;
    }

    private static Boolean hasStage(List<RLY_Org__c> stages) {
        for (RLY_Org__c o : stages) {
            if (o.Role__c == 'Stage') {
                return true;
            }
        }
        return false;
    }
}
