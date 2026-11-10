/**
 * @description Where a release comes from and goes to: a developer org (with its own branch) releases into the first
 * stage, hotfixes included. Build 55: a stage an admin switched to Can raise releases (RLY_Org__c.Can_Raise__c, for
 * changes that need a package the orgs below it lack) is a source too; its releases go to the next stop on the route
 * (the next stage, or the hub). Other stages can't be raised from: hotfixes are raised from a developer org.
 */
public with sharing class RlyRaiseRoute {

    /** @description What raising from a stage org says. */
    public static final String STAGE_RETIRED = 'Hotfixes are raised from a developer org now. Pick the developer org that has the fix.';

    /**
     * @description Whether releases can be raised from the org: a developer org, or a stage switched to Can raise releases.
     * @param o the org, with Role__c and Can_Raise__c
     * @return true for a source
     */
    public static Boolean canRaiseFrom(RLY_Org__c o) {
        return o != null && (o.Role__c == 'Developer' || (o.Role__c == 'Stage' && o.Can_Raise__c == true));
    }

    /**
     * @description The source org, checked: a developer org (or a stage that can raise releases) with its branch.
     * @param sourceOrgId the source org
     * @return the org, with its sign-in fields
     */
    public static RLY_Org__c source(Id sourceOrgId) {
        RLY_Org__c source = RlyReleaseStore.org(sourceOrgId);
        if (source != null && source.Role__c == 'Stage' && source.Can_Raise__c != true) {
            throw new RlyReleaseException(STAGE_RETIRED);
        }
        if (!canRaiseFrom(source)) {
            throw new RlyReleaseException('Pick a registered developer org.');
        }
        if (String.isBlank(source.Branch__c)) {
            throw new RlyReleaseException('Give ' + source.Name + ' its own branch on the Pipeline tab (for example dev1) '
                + 'so its releases merge instead of overwrite.');
        }
        return source;
    }

    /**
     * @description Where the release goes: the first stage; from a stage, the next stop on the route.
     * @param source the checked source org
     * @return the target org, with its branch
     */
    public static RLY_Org__c target(RLY_Org__c source) {
        RLY_Org__c target = source != null && source.Role__c == 'Stage' ? nextStop(source.Id) : RlyReleaseStore.firstStage();
        if (target == null || String.isBlank(target.Branch__c)) {
            throw new RlyReleaseException(source != null && source.Role__c == 'Stage'
                ? 'Nothing comes after ' + source.Name + ' on the route: register the next stage or the hub with its branch on the Pipeline tab.'
                : 'No stage to release into yet: register the first stage org with its branch on the Pipeline tab.');
        }
        return target;
    }

    /**
     * @description The stop after a stage on the route (stages in order, the hub last).
     * @param stageId the stage
     * @return the next stage or the hub, or null
     */
    public static RLY_Org__c nextStop(Id stageId) {
        List<RLY_Org__c> route = RlyRouteRules.ordered(RlyReleaseStore.routeOrgs());
        for (Integer i = 0; i + 1 < route.size(); i++) {
            if (route[i].Id == stageId) {
                return route[i + 1];
            }
        }
        return null;
    }
}
