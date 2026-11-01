/**
 * @description Hotfixes: an urgent release raised from a developer org (any sandbox type) with a required reason. It goes
 * to the first stage like any release (scan, check-only deploy, tests, approval), is listed first for approval and for
 * promotion, and can be promoted on its own. Only users with the RLY_Hotfix custom permission may flag one. Raising
 * from a stage org is retired: stage orgs aren't offered as sources any more.
 */
public with sharing class RlyHotfix {

    /** @description The custom permission flagging a hotfix needs. */
    public static final String PERMISSION = 'RLY_Hotfix';
    /** @description Longest hotfix reason. */
    public static final Integer REASON_LENGTH = 255;

    /** @description A stage org a hotfix could be raised from (retired: Start.stageSources is always empty). */
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
        /** @description Its Salesforce environment. */
        @AuraEnabled public String environment;
        /** @description The next stop's name. */
        @AuraEnabled public String targetName;
        /** @description The next stop's branch. */
        @AuraEnabled public String targetBranch;
        /** @description The next stop's Git environment. */
        @AuraEnabled public String targetEnvironment;
    }

    /**
     * @description Whether the current user may flag a release as a hotfix.
     * @return true with the RLY_Hotfix custom permission
     */
    public static Boolean allowed() {
        return FeatureManagement.checkPermission(PERMISSION);
    }

    /**
     * @description Whether a release is a hotfix.
     * @param rel the release, with Is_Hotfix__c
     * @return true for hotfixes
     */
    public static Boolean isHotfix(RLY_Release__c rel) {
        return rel != null && rel.Is_Hotfix__c == true;
    }

    /**
     * @description The checked reason of a request flagged as a hotfix: the flag needs the permission and a reason.
     * @param req the request
     * @return the trimmed reason (up to 255 characters), or null when the request isn't a hotfix
     */
    public static String reason(RlyRaiseService.RaiseRequest req) {
        if (req.isHotfix != true) {
            return null;
        }
        if (!allowed()) {
            throw new RlyReleaseException('Only users with the Hotfix permission can raise a hotfix.');
        }
        if (String.isBlank(req.hotfixReason)) {
            throw new RlyReleaseException('Say why this is a hotfix.');
        }
        return req.hotfixReason.trim().left(REASON_LENGTH);
    }

    /**
     * @description The next stop after a stage on the route: the next stage, or else the hub.
     * @param stageId the stage org
     * @param routeOrgs the stages and the hub
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
}
