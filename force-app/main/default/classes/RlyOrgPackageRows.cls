/**
 * @description Build 55: the org rows a package read or an admin's mark saves (RlyOrgPackageStore): each org's
 * installed packages after a read (RLY_Org__c.Packages__c, Packages_Checked__c) and its "treat as not installed" marks
 * (Packages_Off__c).
 */
public with sharing class RlyOrgPackageRows {

    /**
     * @description The org rows to save after a read of the installed packages: each org read without an error gets its
     * packages (namespaced ones) and the time; an org that couldn't be read keeps what it had.
     * @param p the read (RlySyncPackages)
     * @param orgs the orgs read
     * @return the rows (Id, Packages__c, Packages_Checked__c)
     */
    public static List<RLY_Org__c> fromRead(RlySyncPackages.Packages p, List<RLY_Org__c> orgs) {
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        if (p == null) {
            return out;
        }
        Set<String> readNames = new Set<String>(p.orgs);
        for (RLY_Org__c o : orgs) {
            if (o.Id != null && readNames.contains(o.Name) && !p.errors.containsKey(o.Name)) {
                out.add(new RLY_Org__c(Id = o.Id, Packages__c = JSON.serialize(packagesIn(p, o.Name)).left(32768),
                    Packages_Checked__c = p.checkedAt));
            }
        }
        return out;
    }

    // The namespaced packages of one org in a read, by namespace.
    private static List<RlyOrgPackages.Installed> packagesIn(RlySyncPackages.Packages p, String orgName) {
        List<RlyOrgPackages.Installed> out = new List<RlyOrgPackages.Installed>();
        for (RlySyncPackages.PackageRow row : p.packages) {
            if (RlyOrgPackages.isNamespace(row.namespace) && row.versions.containsKey(orgName)) {
                RlyOrgPackages.Installed i = new RlyOrgPackages.Installed();
                i.ns = row.namespace.toLowerCase();
                i.name = row.name;
                i.version = row.versions.get(orgName);
                out.add(i);
            }
        }
        return out;
    }

    /**
     * @description The org's row with a namespace marked "treat as not installed".
     * @param o the org, with Packages_Off__c
     * @param ns the namespace
     * @return the row to save
     */
    public static RLY_Org__c marked(RLY_Org__c o, String ns) {
        Set<String> marks = RlyOrgPackages.offOf(o);
        marks.add(ns.trim().toLowerCase());
        return withMarks(o, marks);
    }

    /**
     * @description The org's row with a namespace's mark taken off.
     * @param o the org, with Packages_Off__c
     * @param ns the namespace
     * @return the row to save
     */
    public static RLY_Org__c unmarked(RLY_Org__c o, String ns) {
        Set<String> marks = RlyOrgPackages.offOf(o);
        marks.remove(ns.trim().toLowerCase());
        return withMarks(o, marks);
    }

    private static RLY_Org__c withMarks(RLY_Org__c o, Set<String> marks) {
        List<String> sorted = new List<String>(marks);
        sorted.sort();
        String text = String.join(sorted, ',');
        if (text.length() > RlyOrgPackages.OFF_MAX) {
            throw new RlyReleaseException('Too many packages are marked in ' + o.Name + '.');
        }
        return new RLY_Org__c(Id = o.Id, Packages_Off__c = String.isBlank(text) ? null : text);
    }
}
