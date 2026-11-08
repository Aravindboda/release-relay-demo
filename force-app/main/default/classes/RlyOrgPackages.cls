/**
 * @description Build 55, package-aware releases: which org has which managed package. Each registered org keeps its
 * installed packages as last read (RLY_Org__c.Packages__c, JSON [{ns, name, version}], with Packages_Checked__c) and the
 * namespaces an admin marked "treat as not installed" (Packages_Off__c). A package counts by its namespace; packages
 * without one aren't tracked. An org whose packages were never read is treated as having every package (nothing is
 * kept back or left out for it), so a hub that never read its packages behaves as before.
 *
 * Every pipeline run the hub starts for a release gets options.packages (RlyPipelineOptions.forMode → addTo):
 *   known          every namespace in any org on the route (after the marks)
 *   sourceMissing  raise or add changes (mode hub): the namespaces the source org lacks (the pipeline puts their
 *                  references back from the target branch)
 *   targetMissing  the namespaces the run's target org lacks (the pipeline leaves their references and components out
 *                  of that org's deploy; Git keeps them)
 * No known namespace: no packages option (the pipeline behaves exactly as before).
 */
public with sharing class RlyOrgPackages {

    /** @description The options key. */
    public static final String OPTION = 'packages';
    /** @description Most characters of Packages_Off__c. */
    public static final Integer OFF_MAX = 4096;
    private static final Pattern NS_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,14}$');

    /** @description One installed package. */
    public class Installed {
        /** @description The namespace (lower case). */
        @AuraEnabled public String ns;
        /** @description The package's name. */
        @AuraEnabled public String name;
        /** @description The version, for example 2.14. */
        @AuraEnabled public String version;
    }

    /**
     * @description Whether a text is a package namespace.
     * @param ns the text
     * @return true for a namespace
     */
    public static Boolean isNamespace(String ns) {
        return String.isNotBlank(ns) && NS_PATTERN.matcher(ns.trim()).matches();
    }

    /**
     * @description The org's installed packages as last read.
     * @param o the org, with Packages__c
     * @return the packages (empty before the first read)
     */
    public static List<Installed> installedOf(RLY_Org__c o) {
        if (o == null || String.isBlank(o.Packages__c)) {
            return new List<Installed>();
        }
        try {
            List<Installed> out = (List<Installed>) JSON.deserialize(o.Packages__c, List<Installed>.class);
            return out == null ? new List<Installed>() : out;
        } catch (JSONException e) {
            return new List<Installed>();
        }
    }

    /**
     * @description The namespaces an admin marked "treat as not installed" in the org.
     * @param o the org, with Packages_Off__c
     * @return lower-case namespaces
     */
    public static Set<String> offOf(RLY_Org__c o) {
        Set<String> out = new Set<String>();
        if (o == null || String.isBlank(o.Packages_Off__c)) {
            return out;
        }
        for (String ns : o.Packages_Off__c.split(',')) {
            if (isNamespace(ns)) {
                out.add(ns.trim().toLowerCase());
            }
        }
        return out;
    }

    /**
     * @description Whether the org's packages have been read.
     * @param o the org, with Packages_Checked__c and Packages__c
     * @return true once read
     */
    public static Boolean isChecked(RLY_Org__c o) {
        return o != null && o.Packages_Checked__c != null && o.Packages__c != null;
    }

    /**
     * @description The namespaces the org has: installed and not marked "treat as not installed".
     * @param o the org
     * @return lower-case namespaces
     */
    public static Set<String> hasOf(RLY_Org__c o) {
        Set<String> out = new Set<String>();
        Set<String> off = offOf(o);
        for (Installed p : installedOf(o)) {
            if (isNamespace(p.ns) && !off.contains(p.ns.toLowerCase())) {
                out.add(p.ns.toLowerCase());
            }
        }
        return out;
    }

    /**
     * @description Every namespace some org has (after the marks).
     * @param orgs the orgs
     * @return lower-case namespaces
     */
    public static Set<String> knownOf(List<RLY_Org__c> orgs) {
        Set<String> out = new Set<String>();
        for (RLY_Org__c o : orgs) {
            out.addAll(hasOf(o));
        }
        return out;
    }

    /**
     * @description What an org lacks of the known namespaces; nothing for an org never read.
     * @param o the org, or null
     * @param known the known namespaces
     * @return lower-case namespaces, sorted
     */
    public static List<String> missingIn(RLY_Org__c o, Set<String> known) {
        List<String> out = new List<String>();
        if (!isChecked(o)) {
            return out;
        }
        Set<String> has = hasOf(o);
        for (String ns : known) {
            if (!has.contains(ns)) {
                out.add(ns);
            }
        }
        out.sort();
        return out;
    }

    /**
     * @description Adds options.packages for a release's run, when any org has a package.
     * @param rel the release, with Source_Org__c and Target_Org__c
     * @param mode the run's mode (hub, promote, check, resolve, merge or sync)
     * @param options the run's options
     */
    public static void addTo(RLY_Release__c rel, String mode, Map<String, Object> options) {
        Map<String, Object> p = optionsFor(rel, mode, RlyOrgPackageStore.orgs());
        if (p != null) {
            options.put(OPTION, p);
        }
    }

    /**
     * @description options.packages for a release's run: known, sourceMissing (mode hub only: a raise or added changes)
     * and targetMissing.
     * @param rel the release, with Source_Org__c and Target_Org__c
     * @param mode the run's mode
     * @param orgs the registered orgs with their package fields
     * @return the option, or null when no org has a package
     */
    public static Map<String, Object> optionsFor(RLY_Release__c rel, String mode, List<RLY_Org__c> orgs) {
        Set<String> known = knownOf(orgs);
        if (known.isEmpty() || rel == null) {
            return null;
        }
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>(orgs);
        List<String> knownList = new List<String>(known);
        knownList.sort();
        return new Map<String, Object>{
            'known' => knownList,
            'sourceMissing' => mode == 'hub' ? missingIn(byId.get(rel.Source_Org__c), known) : new List<String>(),
            'targetMissing' => missingIn(byId.get(rel.Target_Org__c), known)
        };
    }
}
