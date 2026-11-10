/**
 * @description Build 55: the package matrix the Pipeline tab shows (RlyOrgPackagesController, rlyOrgPackages): packages
 * down, orgs across (developer orgs by name, then the stages in route order and the hub, then back promote orgs), each
 * cell the version installed, not installed, marked "treat as not installed", or not read yet; and per org whether
 * releases can be raised from it.
 */
public with sharing class RlyOrgPackageMatrix {

    /** @description One org column. */
    public class OrgColumn {
        /** @description The org. */
        @AuraEnabled public Id id;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Developer, Stage, Hub or Back_Promote. */
        @AuraEnabled public String role;
        /** @description When its packages were read, or null. */
        @AuraEnabled public Datetime checkedAt;
        /** @description Releases can be raised from it (developer orgs always; stages when switched on). */
        @AuraEnabled public Boolean canRaise = false;
        /** @description An admin may switch Can raise releases (a stage that isn't the last stop). */
        @AuraEnabled public Boolean canRaiseSwitch = false;
        /** @description Where its releases go (raise-able orgs), or null. */
        @AuraEnabled public String raisesInto;
    }

    /** @description One cell: a package in an org. */
    public class Cell {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description The version installed, or null. */
        @AuraEnabled public String version;
        /** @description Installed. */
        @AuraEnabled public Boolean installed = false;
        /** @description Marked "treat as not installed". */
        @AuraEnabled public Boolean off = false;
        /** @description The org's packages were never read. */
        @AuraEnabled public Boolean unknown = false;
    }

    /** @description One package row. */
    public class PackageRow {
        /** @description The namespace. */
        @AuraEnabled public String ns;
        /** @description The package's name. */
        @AuraEnabled public String name;
        /** @description One cell per org column, in column order. */
        @AuraEnabled public List<Cell> cells = new List<Cell>();
        /** @description The orgs (names) that don't have it, after the marks. */
        @AuraEnabled public List<String> missingIn = new List<String>();
    }

    /** @description The matrix. */
    public class Matrix {
        /** @description The org columns. */
        @AuraEnabled public List<OrgColumn> orgs = new List<OrgColumn>();
        /** @description The packages, by name. */
        @AuraEnabled public List<PackageRow> packages = new List<PackageRow>();
        /** @description The newest read. */
        @AuraEnabled public Datetime checkedAt;
        /** @description The viewer is an admin in the hub (Check now, marks, Can raise releases). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description What the last action did, or null. */
        @AuraEnabled public String message;
        /** @description Orgs that couldn't be read by the last Check now (name => why). */
        @AuraEnabled public Map<String, String> errors = new Map<String, String>();
    }

    /**
     * @description The matrix of these orgs.
     * @param orgs the registered orgs with their package fields
     * @return the matrix
     */
    public static Matrix build(List<RLY_Org__c> orgs) {
        Matrix m = new Matrix();
        m.isAdmin = RlyReleaseAccess.isAdmin() && RlyHubGuard.isHub();
        List<RLY_Org__c> ordered = columnsOf(orgs);
        Map<Id, RLY_Org__c> following = nextStops();
        Map<String, PackageRow> byNs = new Map<String, PackageRow>();
        for (RLY_Org__c o : ordered) {
            m.orgs.add(column(o, following.get(o.Id)));
            m.checkedAt = o.Packages_Checked__c != null && (m.checkedAt == null || o.Packages_Checked__c > m.checkedAt)
                ? o.Packages_Checked__c : m.checkedAt;
            for (RlyOrgPackages.Installed p : RlyOrgPackages.installedOf(o)) {
                if (RlyOrgPackages.isNamespace(p.ns) && !byNs.containsKey(p.ns.toLowerCase())) {
                    PackageRow row = new PackageRow();
                    row.ns = p.ns.toLowerCase();
                    row.name = p.name;
                    byNs.put(row.ns, row);
                }
            }
        }
        for (PackageRow row : byNs.values()) {
            fillCells(row, ordered);
        }
        m.packages = sortedRows(byNs.values());
        return m;
    }

    // Developer orgs by name, then the stages in route order and the hub, then back promote orgs.
    private static List<RLY_Org__c> columnsOf(List<RLY_Org__c> orgs) {
        List<RLY_Org__c> devs = new List<RLY_Org__c>();
        List<RLY_Org__c> stops = new List<RLY_Org__c>();
        List<RLY_Org__c> back = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Developer') {
                devs.add(o);
            } else if (RlyRouteRules.isStage(o)) {
                stops.add(o);
            } else {
                back.add(o);
            }
        }
        List<RLY_Org__c> out = new List<RLY_Org__c>(devs);
        out.addAll(RlyRouteRules.ordered(stops));
        out.addAll(back);
        return out;
    }

    // The stop after each stop on the route (key: the org).
    private static Map<Id, RLY_Org__c> nextStops() {
        Map<Id, RLY_Org__c> out = new Map<Id, RLY_Org__c>();
        List<RLY_Org__c> route = RlyRouteRules.ordered(RlyReleaseStore.routeOrgs());
        for (Integer i = 0; i + 1 < route.size(); i++) {
            out.put(route[i].Id, route[i + 1]);
        }
        return out;
    }

    private static OrgColumn column(RLY_Org__c o, RLY_Org__c next) {
        OrgColumn c = new OrgColumn();
        c.id = o.Id;
        c.name = o.Name;
        c.role = o.Role__c;
        c.checkedAt = RlyOrgPackages.isChecked(o) ? o.Packages_Checked__c : null;
        c.canRaise = RlyRaiseRoute.canRaiseFrom(o);
        c.canRaiseSwitch = o.Role__c == 'Stage' && next != null;
        c.raisesInto = o.Role__c == 'Stage' && next != null ? next.Name : null;
        return c;
    }

    private static void fillCells(PackageRow row, List<RLY_Org__c> ordered) {
        for (RLY_Org__c o : ordered) {
            Cell c = new Cell();
            c.orgId = o.Id;
            c.unknown = !RlyOrgPackages.isChecked(o);
            for (RlyOrgPackages.Installed p : RlyOrgPackages.installedOf(o)) {
                if (p.ns != null && p.ns.equalsIgnoreCase(row.ns)) {
                    c.installed = true;
                    c.version = p.version;
                }
            }
            c.off = RlyOrgPackages.offOf(o).contains(row.ns);
            if (!c.unknown && (!c.installed || c.off)) {
                row.missingIn.add(o.Name);
            }
            row.cells.add(c);
        }
    }

    private static List<PackageRow> sortedRows(List<PackageRow> rows) {
        Map<String, PackageRow> byKey = new Map<String, PackageRow>();
        for (PackageRow r : rows) {
            byKey.put((String.isBlank(r.name) ? r.ns : r.name).toLowerCase() + '|' + r.ns, r);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<PackageRow> out = new List<PackageRow>();
        for (String k : keys) {
            out.add(byKey.get(k));
        }
        return out;
    }

}
