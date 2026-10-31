/**
 * @description Where a release comes from and goes to. A developer org (with its own branch) releases into the first
 * stage; a stage org (a hotfix, with the RLY_Hotfix permission) releases into its next stop on the route.
 */
public with sharing class RlyRaiseRoute {

    /**
     * @description The source org, checked: a developer org with its branch, or a stage org for a hotfix.
     * @param sourceOrgId the source org
     * @return the org, with its sign-in fields
     */
    public static RLY_Org__c source(Id sourceOrgId) {
        RLY_Org__c source = RlyReleaseStore.org(sourceOrgId);
        if (source != null && source.Role__c == 'Stage') {
            requireHotfix();
            return source;
        }
        if (source == null || source.Role__c != 'Developer') {
            throw new RlyReleaseException('Pick a registered developer org.');
        }
        if (String.isBlank(source.Branch__c)) {
            throw new RlyReleaseException('Give ' + source.Name + ' its own branch on the Pipeline tab (for example dev1) '
                + 'so its releases merge instead of overwrite.');
        }
        return source;
    }

    /**
     * @description Refuses a hotfix to users without the RLY_Hotfix custom permission.
     */
    public static void requireHotfix() {
        if (!RlyHotfix.allowed()) {
            throw new RlyReleaseException('Raising a hotfix from a stage org needs the Release Relay Hotfix permission.');
        }
    }

    /**
     * @description Where the release goes: the first stage, or a hotfix's next stop.
     * @param source the checked source org
     * @return the target org, with its branch
     */
    public static RLY_Org__c target(RLY_Org__c source) {
        return source.Role__c == 'Stage' ? nextStop(source) : firstStage();
    }

    private static RLY_Org__c firstStage() {
        RLY_Org__c target = RlyReleaseStore.firstStage();
        if (target == null || String.isBlank(target.Branch__c)) {
            throw new RlyReleaseException('No stage to release into yet: register SIT with its branch on the Pipeline tab.');
        }
        return target;
    }

    private static RLY_Org__c nextStop(RLY_Org__c source) {
        RLY_Org__c target = RlyHotfix.nextStop(source.Id, RlyReleaseStore.routeOrgs());
        if (target == null) {
            throw new RlyReleaseException(source.Name + ' has no next stop on the route to send a hotfix to.');
        }
        if (String.isBlank(target.Branch__c)) {
            throw new RlyReleaseException(target.Name + ' has no branch: set it on the Pipeline tab.');
        }
        return target;
    }
}
