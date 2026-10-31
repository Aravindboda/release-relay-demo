/**
 * @description Hotfixes: a release raised from a stage org (for example SIT) straight to its next stop on the route
 * (the next stage by Stage_Order__c, or the hub). Only users with the RLY_Hotfix custom permission may raise them.
 * A hotfix branch (hotfix/rel-xxxxx) starts from the target's branch, so its pull request carries only the hotfix.
 */
public with sharing class RlyHotfix {

    /** @description The custom permission hotfixes need. */
    public static final String PERMISSION = 'RLY_Hotfix';

    /** @description A stage org a hotfix can be raised from, with where it goes. No sign-in fields. */
    public class StageSource {
        /** @description The stage org. */
        @AuraEnabled public Id id;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Its branch. */
        @AuraEnabled public String branch;
        /** @description Its last sign-in check. */
        @AuraEnabled public String status;
        /** @description Whether it has source tracking. */
        @AuraEnabled public String sourceTracking;
        /** @description Its Salesforce environment (Developer, Developer_Pro, Partial_Copy, Full_Copy or Production). */
        @AuraEnabled public String environment;
        /** @description The next stop's name. */
        @AuraEnabled public String targetName;
        /** @description The next stop's branch. */
        @AuraEnabled public String targetBranch;
        /** @description The next stop's Git environment. */
        @AuraEnabled public String targetEnvironment;
    }

    /**
     * @description Whether the current user may raise hotfixes.
     * @return true with the RLY_Hotfix custom permission
     */
    public static Boolean allowed() {
        return FeatureManagement.checkPermission(PERMISSION);
    }

    /**
     * @description Whether a release is a hotfix (raised from a stage org).
     * @param rel the release, with Source_Org__r.Role__c
     * @return true for hotfixes
     */
    public static Boolean isHotfix(RLY_Release__c rel) {
        return rel != null && rel.Source_Org__r != null && rel.Source_Org__r.Role__c == 'Stage';
    }

    /**
     * @description The next stop after a stage on the route: the next stage, or else the hub.
     * @param stageId the stage org
     * @param routeOrgs the stages and the hub, by name
     * @return the next stop, or null when there is none
     */
    public static RLY_Org__c nextStop(Id stageId, List<RLY_Org__c> routeOrgs) {
        List<RLY_Org__c> route = RlyRouteRules.ordered(routeOrgs);
        for (Integer i = 0; i < route.size() - 1; i++) {
            if (route[i].Id == stageId) {
                return route[i + 1];
            }
        }
        return null;
    }

    /**
     * @description The stage orgs a hotfix can be raised from, each with its next stop.
     * @param routeOrgs the stages and the hub, by name
     * @return the stage sources, in route order
     */
    public static List<StageSource> stageSources(List<RLY_Org__c> routeOrgs) {
        List<StageSource> out = new List<StageSource>();
        List<RLY_Org__c> route = RlyRouteRules.ordered(routeOrgs);
        for (Integer i = 0; i < route.size() - 1; i++) {
            if (route[i].Role__c == 'Stage') {
                out.add(toSource(route[i], route[i + 1]));
            }
        }
        return out;
    }

    private static StageSource toSource(RLY_Org__c stage, RLY_Org__c nextOrg) {
        StageSource s = new StageSource();
        s.id = stage.Id;
        s.name = stage.Name;
        s.branch = stage.Branch__c;
        s.status = stage.Status__c;
        s.sourceTracking = stage.Source_Tracking__c;
        s.environment = stage.Environment__c;
        s.targetName = nextOrg.Name;
        s.targetBranch = nextOrg.Branch__c;
        s.targetEnvironment = nextOrg.Git_Environment__c;
        return s;
    }
}
