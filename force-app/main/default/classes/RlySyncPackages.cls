/**
 * @description Sync status: the managed packages installed in each route org (Tooling API InstalledSubscriberPackage,
 * read by the hub with each org's sign-in) and, before an uninstall, the org's own components that still use a package
 * (Tooling API MetadataComponentDependency). Release Relay never installs or uninstalls a package: the page turns these
 * into a release with a Managed package manual step. Callouts, then one save.
 */
public with sharing class RlySyncPackages {

    private static final Pattern NAMESPACE_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,14}$');
    /** @description Most dependency rows read. */
    public static final Integer MAX_USES = 2000;

    /** @description One package across the orgs. */
    public class PackageRow {
        /** @description The namespace. */
        @AuraEnabled public String namespace;
        /** @description The package's name. */
        @AuraEnabled public String name;
        /** @description The version per org name (missing: not installed). */
        @AuraEnabled public Map<String, String> versions = new Map<String, String>();
    }

    /** @description The packages of every route org. */
    public class Packages {
        /** @description The orgs read, from the top down. */
        @AuraEnabled public List<String> orgs = new List<String>();
        /** @description Orgs that couldn't be read, with why (org name => reason). */
        @AuraEnabled public Map<String, String> errors = new Map<String, String>();
        /** @description The packages, by name. */
        @AuraEnabled public List<PackageRow> packages = new List<PackageRow>();
        /** @description When they were read. */
        @AuraEnabled public Datetime checkedAt;
    }

    /** @description One own component that uses a package. */
    public class Use {
        /** @description Type:Name. */
        @AuraEnabled public String key;
        /** @description The type. */
        @AuraEnabled public String type;
        /** @description The name. */
        @AuraEnabled public String name;
        /** @description What of the package it uses. */
        @AuraEnabled public String uses;
    }

    /** @description What uses a package in an org. */
    public class Usage {
        /** @description The org read. */
        @AuraEnabled public String org;
        /** @description The components (each once). */
        @AuraEnabled public List<Use> uses = new List<Use>();
        /** @description Salesforce answered more than MAX_USES rows, or refused the query (say so). */
        @AuraEnabled public String note;
    }

    /**
     * @description Reads every route org's installed packages and saves them as the latest Packages check. A hub has at
     * most RlyOrgController.MAX_ORGS orgs, so one request reads them all (one query for their sign-ins, two callouts each).
     * Build 55: the read is gather (callouts) then save (the check, and each org's Packages__c).
     * @param orgs the route orgs from the top down
     * @return the packages
     */
    public static Packages read(List<RLY_Org__c> orgs) {
        Packages p = gather(orgs);
        saveRead(p, orgs);
        return p;
    }

    /**
     * @description Build 55: reads every org's installed packages (callouts only, no DML): one query per org, after its
     * sign-in (a token signed in earlier in the request is reused): at most 2 × RlyOrgController.MAX_ORGS callouts.
     * @param orgs the orgs from the top down
     * @return the packages
     */
    public static Packages gather(List<RLY_Org__c> orgs) {
        if (orgs.size() > RlyOrgController.MAX_ORGS) {
            throw new RlyReleaseException(RlyOrgController.TOO_MANY_ORGS);
        }
        Packages p = new Packages();
        p.checkedAt = System.now();
        Map<String, PackageRow> byNamespace = new Map<String, PackageRow>();
        Map<Id, RLY_Org__c> signIns = RlyReleaseStore.orgs(new Map<Id, RLY_Org__c>(orgs).keySet());
        for (RLY_Org__c o : orgs) {
            p.orgs.add(o.Name);
            try {
                addOrg(byNamespace, o.Name, RlyOrgSession.getJson(signIns.get(o.Id), RlyOrgSession.toolingQueryPath(
                    'SELECT SubscriberPackage.Name, SubscriberPackage.NamespacePrefix, SubscriberPackageVersion.MajorVersion, '
                    + 'SubscriberPackageVersion.MinorVersion, SubscriberPackageVersion.PatchVersion FROM InstalledSubscriberPackage')));
            } catch (Exception e) {
                p.errors.put(o.Name, e.getMessage().left(300));
            }
        }
        List<String> names = new List<String>(byNamespace.keySet());
        names.sort();
        for (String ns : names) {
            p.packages.add(byNamespace.get(ns));
        }
        return p;
    }

    /**
     * @description Build 55: saves a read (DML only): the latest Packages check, and each org read without an error gets
     * its packages (RlyOrgPackageRows.fromRead).
     * @param p the read
     * @param orgs the orgs read
     */
    public static void saveRead(Packages p, List<RLY_Org__c> orgs) {
        String summary = JSON.serialize(p);
        String syncId = RlySyncRuns.newId('SYN-');
        RlySyncStore.save(new RLY_Sync_Check__c(Sync_Id__c = syncId, Kind__c = RlySyncStore.KIND_PACKAGES,
            Status__c = RlySyncStore.SUCCEEDED, Checked_At__c = p.checkedAt, Summary__c = summary.left(131072),
            Counts__c = JSON.serialize(new Map<String, Integer>{ 'packages' => p.packages.size(), 'errors' => p.errors.size() })));
        RlyOrgPackageStore.save(RlyOrgPackageRows.fromRead(p, orgs));
    }

    /**
     * @description The latest Packages check, as saved.
     * @param check the check (Kind Packages), or null
     * @return the packages, or null
     */
    public static Packages saved(RLY_Sync_Check__c check) {
        if (check == null || String.isBlank(check.Summary__c)) {
            return null;
        }
        try {
            return (Packages) JSON.deserialize(check.Summary__c, Packages.class);
        } catch (JSONException e) {
            return null;
        }
    }

    /**
     * @description The org's own components that use a package (where Salesforce reports it).
     * @param org the org to read
     * @param namespace the package's namespace
     * @return the components
     */
    public static Usage usage(RLY_Org__c org, String namespace) {
        if (String.isBlank(namespace) || !NAMESPACE_PATTERN.matcher(namespace).matches()) {
            throw new RlyReleaseException('That isn\'t a package namespace.');
        }
        Usage u = new Usage();
        u.org = org.Name;
        Map<String, Use> byKey = new Map<String, Use>();
        try {
            Map<String, Object> page = (Map<String, Object>) RlyOrgSession.getJson(RlyReleaseStore.org(org.Id), RlyOrgSession.toolingQueryPath(
                'SELECT MetadataComponentName, MetadataComponentType, MetadataComponentNamespace, RefMetadataComponentName, '
                + 'RefMetadataComponentType FROM MetadataComponentDependency WHERE RefMetadataComponentNamespace = \'' + namespace
                + '\' LIMIT ' + MAX_USES));
            for (Object o : page.get('records') instanceof List<Object> ? (List<Object>) page.get('records') : new List<Object>()) {
                addUse(byKey, (Map<String, Object>) o, namespace);
            }
            if (page.get('done') == false) {
                u.note = 'More than ' + MAX_USES + ' references: only the first are listed.';
            }
        } catch (Exception e) {
            u.note = 'Salesforce didn\'t list what uses the package (' + e.getMessage().left(200)
                + '). The check-only run still finds anything left.';
        }
        u.uses = byKey.values();
        return u;
    }

    // The org's packages into the rows (one row per namespace).
    private static void addOrg(Map<String, PackageRow> byNamespace, String orgName, Object answer) {
        Map<String, Object> page = (Map<String, Object>) answer;
        for (Object o : page.get('records') instanceof List<Object> ? (List<Object>) page.get('records') : new List<Object>()) {
            Map<String, Object> r = (Map<String, Object>) o;
            Map<String, Object> pkg = r.get('SubscriberPackage') instanceof Map<String, Object> ? (Map<String, Object>) r.get('SubscriberPackage') : new Map<String, Object>();
            Map<String, Object> ver = r.get('SubscriberPackageVersion') instanceof Map<String, Object> ? (Map<String, Object>) r.get('SubscriberPackageVersion') : new Map<String, Object>();
            String ns = pkg.get('NamespacePrefix') == null ? String.valueOf(pkg.get('Name')) : String.valueOf(pkg.get('NamespacePrefix'));
            if (!byNamespace.containsKey(ns)) {
                PackageRow row = new PackageRow();
                row.namespace = pkg.get('NamespacePrefix') == null ? null : ns;
                row.name = String.valueOf(pkg.get('Name'));
                byNamespace.put(ns, row);
            }
            byNamespace.get(ns).versions.put(orgName, versionOf(ver));
        }
    }

    private static String versionOf(Map<String, Object> ver) {
        String v = String.valueOf(ver.get('MajorVersion')) + '.' + String.valueOf(ver.get('MinorVersion'));
        Object patch = ver.get('PatchVersion');
        return patch == null || String.valueOf(patch) == '0' ? v : v + '.' + String.valueOf(patch);
    }

    // An own component (not the package's) that uses the package, each once.
    private static void addUse(Map<String, Use> byKey, Map<String, Object> r, String namespace) {
        String ownNs = r.get('MetadataComponentNamespace') == null ? '' : String.valueOf(r.get('MetadataComponentNamespace'));
        if (ownNs == namespace) {
            return;
        }
        Use u = new Use();
        u.type = String.valueOf(r.get('MetadataComponentType'));
        u.name = String.valueOf(r.get('MetadataComponentName'));
        u.key = u.type + ':' + u.name;
        u.uses = String.valueOf(r.get('RefMetadataComponentType')) + ' ' + String.valueOf(r.get('RefMetadataComponentName'));
        if (!byKey.containsKey(u.key)) {
            byKey.put(u.key, u);
        }
    }
}
