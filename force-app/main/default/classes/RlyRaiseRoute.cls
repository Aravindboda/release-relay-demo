/**
 * @description Where a release comes from and goes to: a developer org (with its own branch) releases into the first
 * stage, hotfixes included. Raising from a stage org is retired: hotfixes are raised from a developer org now.
 */
public with sharing class RlyRaiseRoute {

    /** @description What raising from a stage org says. */
    public static final String STAGE_RETIRED = 'Hotfixes are raised from a developer org now. Pick the developer org that has the fix.';

    /**
     * @description The source org, checked: a developer org with its branch.
     * @param sourceOrgId the source org
     * @return the org, with its sign-in fields
     */
    public static RLY_Org__c source(Id sourceOrgId) {
        RLY_Org__c source = RlyReleaseStore.org(sourceOrgId);
        if (source != null && source.Role__c == 'Stage') {
            throw new RlyReleaseException(STAGE_RETIRED);
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
     * @description Where the release goes: the first stage.
     * @param source the checked source org
     * @return the target org, with its branch
     */
    public static RLY_Org__c target(RLY_Org__c source) {
        RLY_Org__c target = RlyReleaseStore.firstStage();
        if (target == null || String.isBlank(target.Branch__c)) {
            throw new RlyReleaseException('No stage to release into yet: register the first stage org with its branch on the Pipeline tab.');
        }
        return target;
    }
}
