/**
 * @description Sync status tab (rlySyncStatus): is each org the same as its branch, has everything a higher stage has
 * come back down the route, and which managed packages are installed where.
 *   board              the route orgs with their latest check, the latest route check, the latest packages
 *   startOrgCheck      an org against its branch (RlySyncRuns); a developer org is sent in parts by the page
 *                      under the check's id (RlyCompareController.startPipelinePart / stagePipelinePart), then
 *                      runDeveloperCheck
 *   startRouteCheck    each branch against the one below it
 *   readCheck          a check's result (RlySyncResult); syncFile one file's copies
 *   readPackages       every route org's installed packages (RlySyncPackages); packageUsage what uses one
 *   backPromotePicked / backPromoteAll / pushToOrg  (admins, like back promote; RlySyncPromote)
 * Every Release Relay user with the tab can read and start checks; Git calls need the Release Relay User principal.
 */
public with sharing class RlySyncController {

    /**
     * @description The tab's data.
     * @return the board
     */
    @AuraEnabled
    public static RlySyncBoard.Board board() {
        try {
            RlyHubGuard.requireHub();
            return RlySyncBoard.build();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Starts an org check.
     * @param orgId the route org
     * @return the check (mode parts: the page sends the developer org's components)
     */
    @AuraEnabled
    public static RlySyncRuns.Started startOrgCheck(Id orgId) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncRuns.startOrg(RlySyncRoute.find(RlySyncStore.orgs(), orgId));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description A developer org's check, once its parts are sent (under the check's id): starts the compare.
     * @param syncId the check
     * @param parts how many parts were sent
     * @param types the types the page listed
     * @return the run's title
     */
    @AuraEnabled
    public static String runDeveloperCheck(String syncId, Integer parts, List<String> types) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncRuns.runDeveloper(syncId, parts, types);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Starts the down-the-route check.
     * @return the check
     */
    @AuraEnabled
    public static RlySyncRuns.Started startRouteCheck() {
        try {
            RlyHubGuard.requireHub();
            return RlySyncRuns.startRoute(RlySyncStore.orgs());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description A check: its result once it's there.
     * @param syncId the check
     * @return the check
     */
    @AuraEnabled
    public static RlySyncResult.View readCheck(String syncId) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncResult.read(syncId);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description One file of a check's result.
     * @param syncId the check
     * @param n the file's number
     * @return the file
     */
    @AuraEnabled
    public static RlyCompareFiles.FileDiff syncFile(String syncId, Integer n) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncResult.file(syncId, n);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Reads every route org's installed packages.
     * @return the packages
     */
    @AuraEnabled
    public static RlySyncPackages.Packages readPackages() {
        try {
            RlyHubGuard.requireHub();
            return RlySyncPackages.read(RlySyncRoute.topDown(RlySyncStore.orgs()));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description What in an org still uses a package.
     * @param orgId the org to read (blank: the first stage, else the hub)
     * @param namespace the package's namespace
     * @return the components
     */
    @AuraEnabled
    public static RlySyncPackages.Usage packageUsage(Id orgId, String namespace) {
        try {
            RlyHubGuard.requireHub();
            List<RLY_Org__c> orgs = RlySyncStore.orgs();
            return RlySyncPackages.usage(orgId == null ? RlySyncBoard.firstStage(orgs) : RlySyncRoute.find(orgs, orgId), namespace);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Back promotes the picked components to the org below.
     * @param pickJson {higherOrgId, lowerOrgId, keys, paths}
     * @return the back promote release
     */
    @AuraEnabled
    public static Id backPromotePicked(String pickJson) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncPromote.backPromote(RlySyncPicks.parse(pickJson), RlySyncStore.orgs());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Back promotes everything the higher branch has to the org below.
     * @param higherOrgId the higher org
     * @param lowerOrgId the org below it
     * @return the back promote release
     */
    @AuraEnabled
    public static Id backPromoteAll(Id higherOrgId, Id lowerOrgId) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncPromote.backPromoteAll(higherOrgId, lowerOrgId, RlySyncStore.orgs());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Pushes the picked components from an org's branch to the org.
     * @param pickJson {higherOrgId: the org, keys, paths}
     * @return the release
     */
    @AuraEnabled
    public static Id pushToOrg(String pickJson) {
        try {
            RlyHubGuard.requireHub();
            return RlySyncPromote.push(RlySyncPicks.parse(pickJson), RlySyncStore.orgs());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
