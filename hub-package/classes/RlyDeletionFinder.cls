/**
 * @description Finds deletion candidates in a developer org without source tracking: the components on the org's own
 * branch (RLY_Org__c.Branch__c; the first stage's branch when it has none) under the Git connection's source path that
 * the org doesn't have any more (Metadata API listMetadata). They may have been deleted in the org, or came from another
 * org through the branch and were never deployed to it, so the page never pre-selects them. Standard objects and fields
 * are left out (they can't be deleted). Callouts only.
 */
public with sharing class RlyDeletionFinder {

    /**
     * @description The components on the org's branch that the org doesn't have.
     * @param org the developer org, with its sign-in fields and Branch__c
     * @return the candidates, each with deleted = true
     */
    public static List<RlyChangeFinder.Change> find(RLY_Org__c org) {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null || conn.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        String branch = branchOf(org);
        String sourcePath = String.isBlank(conn.Source_Path__c) ? '' : conn.Source_Path__c.trim().removeEnd('/');
        List<String> keys = RlyDeletionPaths.keysOf(RlyGit.forConnection(conn).listFiles(branch, sourcePath), sourcePath);
        Map<String, List<String>> byType = new Map<String, List<String>>();
        for (String k : keys) {
            String t = k.substringBefore(':');
            if (!byType.containsKey(t)) {
                byType.put(t, new List<String>());
            }
            byType.get(t).add(k.substringAfter(':'));
        }
        return missing(byType, present(org, byType.keySet()));
    }

    /**
     * @description The branch the org's components are read from.
     * @param org the developer org
     * @return its branch, or the first stage's
     */
    public static String branchOf(RLY_Org__c org) {
        if (String.isNotBlank(org.Branch__c)) {
            return org.Branch__c.trim();
        }
        RLY_Org__c firstStage = RlyReleaseStore.firstStage();
        if (firstStage == null || String.isBlank(firstStage.Branch__c)) {
            throw new RlyReleaseException('Give ' + org.Name + ' its own branch on the Pipeline tab first.');
        }
        return firstStage.Branch__c.trim();
    }

    // type:fullName (lower case) of every component of these types in the org.
    private static Set<String> present(RLY_Org__c org, Set<String> types) {
        List<RlyMetadata.Query> queries = new List<RlyMetadata.Query>();
        for (String t : types) {
            queries.add(new RlyMetadata.Query(t, null));
        }
        Set<String> out = new Set<String>();
        for (RlyMetadata.FileProp p : queries.isEmpty() ? new List<RlyMetadata.FileProp>() : RlyMetadata.listFiles(org, queries)) {
            out.add((p.type + ':' + p.fullName).toLowerCase());
        }
        return out;
    }

    private static List<RlyChangeFinder.Change> missing(Map<String, List<String>> byType, Set<String> inOrg) {
        List<RlyChangeFinder.Change> out = new List<RlyChangeFinder.Change>();
        for (String t : byType.keySet()) {
            for (String n : byType.get(t)) {
                String name = n.contains('%') ? EncodingUtil.urlDecode(n.replace('+', '%2B'), 'UTF-8') : n;
                if (!inOrg.contains((t + ':' + name).toLowerCase()) && out.size() < RlyChangeFinder.MAX_ITEMS) {
                    addUnlessStandard(out, deletion(t, name));
                }
            }
        }
        return out;
    }

    private static RlyChangeFinder.Change deletion(String type, String name) {
        RlyChangeFinder.Change c = new RlyChangeFinder.Change();
        c.type = type;
        c.name = name;
        c.key = type + ':' + name;
        c.deleted = true;
        c.standard = isStandard(type, name);
        return c;
    }

    // A standard object (Account) or field (Account.Industry): it can't be deleted.
    private static Boolean isStandard(String type, String name) {
        String own = type == 'CustomField' ? name.substringAfter('.') : name;
        return (type == 'CustomObject' || type == 'CustomField') && !own.contains('__');
    }

    private static void addUnlessStandard(List<RlyChangeFinder.Change> out, RlyChangeFinder.Change c) {
        if (c.standard != true) {
            out.add(c);
        }
    }
}
