/**
 * @description Build 55: the Pipeline tab's package matrix (Orgs section, rlyOrgPackages; the view is
 * RlyOrgPackageMatrix). Admins press Check now (the same read as Sync status and the nightly pass: one query per org,
 * then the save), mark a package "treat as not installed" in an org (installed but unlicensed) or take the mark off,
 * and switch Can raise releases on a stage. Releases read the same fields (RlyOrgPackages) for every run's
 * options.packages.
 */
public with sharing class RlyOrgPackagesController {

    private static final String SWITCH_ON = 'on';
    private static final String SWITCH_OFF = 'off';

    /**
     * @description The matrix.
     * @return the matrix
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix matrix() {
        try {
            return RlyOrgPackageMatrix.build(RlyOrgPackageStore.orgs());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Reads every org's installed packages now (admins): one query per org, then the save.
     * @return the matrix, with what the read found
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix checkNow() {
        try {
            requireAdmin();
            List<RLY_Org__c> orgs = RlyOrgPackageStore.orgs();
            if (orgs.isEmpty()) {
                throw new RlyReleaseException('Register an org first.');
            }
            RlySyncPackages.Packages p = RlySyncPackages.read(RlySyncRoute.topDown(orgs));
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackageMatrix.build(RlyOrgPackageStore.orgs());
            m.errors = p.errors;
            m.message = 'Checked: ' + RlyOrgPackageNightly.summary(p) + '.';
            return m;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Marks a package "treat as not installed" in an org (admins).
     * @param orgId the org
     * @param namespace the package's namespace
     * @return the matrix
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix markNotInstalled(Id orgId, String namespace) {
        return mark(orgId, namespace, SWITCH_OFF);
    }

    /**
     * @description Takes the "treat as not installed" mark off a package in an org (admins).
     * @param orgId the org
     * @param namespace the package's namespace
     * @return the matrix
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix countInstalled(Id orgId, String namespace) {
        return mark(orgId, namespace, SWITCH_ON);
    }

    /**
     * @description Lets releases be raised from a stage (admins): they go to the next stop on the route.
     * @param orgId the stage
     * @return the matrix
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix allowRaising(Id orgId) {
        return raising(orgId, SWITCH_ON);
    }

    /**
     * @description Stops releases being raised from a stage (admins).
     * @param orgId the stage
     * @return the matrix
     */
    @AuraEnabled
    public static RlyOrgPackageMatrix.Matrix stopRaising(Id orgId) {
        return raising(orgId, SWITCH_OFF);
    }

    // SWITCH_OFF marks the package "treat as not installed"; SWITCH_ON takes the mark off.
    private static RlyOrgPackageMatrix.Matrix mark(Id orgId, String namespace, String how) {
        try {
            requireAdmin();
            if (!RlyOrgPackages.isNamespace(namespace)) {
                throw new RlyReleaseException('That isn\'t a package namespace.');
            }
            RLY_Org__c o = find(orgId);
            String ns = namespace.trim().toLowerCase();
            RlyOrgPackageStore.save(new List<RLY_Org__c>{ how == SWITCH_OFF ? RlyOrgPackageRows.marked(o, ns) : RlyOrgPackageRows.unmarked(o, ns) });
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackageMatrix.build(RlyOrgPackageStore.orgs());
            m.message = how == SWITCH_OFF ? ns + ' is treated as not installed in ' + o.Name + '.' : ns + ' counts as installed in ' + o.Name + ' again.';
            return m;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    // SWITCH_ON lets releases be raised from the stage; SWITCH_OFF stops it. Developer orgs always can; the hub is the last stop.
    private static RlyOrgPackageMatrix.Matrix raising(Id orgId, String how) {
        try {
            requireAdmin();
            RLY_Org__c o = find(orgId);
            if (o.Role__c != 'Stage') {
                throw new RlyReleaseException('Only a stage can be switched: developer orgs always raise releases, and the hub is the last stop.');
            }
            if (how == SWITCH_ON && RlyRaiseRoute.nextStop(o.Id) == null) {
                throw new RlyReleaseException('Nothing comes after ' + o.Name + ' on the route yet.');
            }
            RlyOrgPackageStore.save(new List<RLY_Org__c>{ new RLY_Org__c(Id = o.Id, Can_Raise__c = how == SWITCH_ON) });
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackageMatrix.build(RlyOrgPackageStore.orgs());
            m.message = how == SWITCH_ON ? 'Releases can be raised from ' + o.Name + '.' : o.Name + ' no longer raises releases.';
            return m;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    private static RLY_Org__c find(Id orgId) {
        for (RLY_Org__c o : RlyOrgPackageStore.orgs()) {
            if (o.Id == orgId) {
                return o;
            }
        }
        throw new RlyReleaseException('That org isn\'t registered.');
    }

    private static void requireAdmin() {
        RlyHubGuard.requireHub();
        RlyReleaseAccess.requireAdmin('Only a Release Relay admin can change this.');
    }
}
