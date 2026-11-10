/**
 * @description Raising a big release in parts (build 36). The developer org's retrieve comes back as one zip that the
 * hub commits to the release branch without decoding it; a big zip held in memory more than once can pass the heap
 * limit, and that error can't be caught, so the release would stay Retrieving. A release of more than PART_SIZE
 * components, or with a large type (HEAVY: one per part), is retrieved and committed one part at a time instead: each
 * release check handles one part (its retrieve's status, its zip committed as .relay-inbox/<REL>-part-<k>.zip, the next
 * part's retrieve started) and the run starts once every part is on the branch (pipeline files v22 unpack the parts).
 * The parts are worked out the same way at raise time and on every check (types and names sorted), so only the current
 * part is kept: Retrieve_Id__c holds "k:retrieveId". A small release keeps one retrieve and one zip, as before.
 */
public with sharing class RlyRaiseParts {

    /** @description Most components in one part. */
    public static final Integer PART_SIZE = 25;
    /** @description Types that can be large: each goes in a part of its own. */
    public static final Set<String> HEAVY = new Set<String>{ 'StaticResource', 'ContentAsset', 'Document', 'Profile',
        'ExperienceBundle', 'SiteDotCom', 'NetworkBranding', 'Territory2Model', 'CustomObjectTranslation', 'Translations' };

    /**
     * @description Starts the release's retrieve: one retrieve when it fits one part, else the first part's.
     * @param source the developer org
     * @param byType the components by type
     * @return the value for Retrieve_Id__c: the retrieve's id, or "1:id" for a release in parts
     */
    public static String startFirst(RLY_Org__c source, Map<String, Set<String>> byType) {
        List<Map<String, Set<String>>> parts = plan(byType);
        if (parts.size() <= 1) {
            return RlyRetrieve.start(source, byType);
        }
        return '1:' + RlyRetrieve.start(source, parts[0]);
    }

    /**
     * @description Whether a release is retrieved in parts.
     * @param retrieveId Retrieve_Id__c
     * @return true for "k:id"
     */
    public static Boolean isParted(String retrieveId) {
        return String.isNotBlank(retrieveId) && retrieveId.contains(':') && retrieveId.substringBefore(':').isNumeric();
    }

    /**
     * @description Whether this check of the release is a part's (not changes added to an open release).
     * @param rel the release
     * @return true for a release in parts
     */
    public static Boolean handles(RLY_Release__c rel) {
        return isParted(rel.Retrieve_Id__c) && !RlyAppendRun.isPending(rel);
    }

    /**
     * @description One check of a release in parts: when the current part's retrieve is done, commits its zip and starts
     * the next part's retrieve. The branch must exist.
     * @param rel the release (Retrieving, Retrieve_Id__c "k:id")
     * @param git the Git provider
     * @param branch the release branch
     * @return true once the last part is on the branch (the run can start)
     */
    public static Boolean advance(RLY_Release__c rel, RlyGit git, String branch) {
        RLY_Org__c source = RlyReleaseStore.org(rel.Source_Org__c);
        Integer k = Integer.valueOf(rel.Retrieve_Id__c.substringBefore(':'));
        List<Map<String, Set<String>>> parts = plan(byTypeOf(RlyReleaseStore.items(rel.Id)));
        RlyRetrieve.RetrieveStatus st = RlyRetrieve.check(source, rel.Retrieve_Id__c.substringAfter(':'));
        if (!st.done) {
            return false;
        }
        String problem = RlyRetrieve.problemOf(st, source.Name);
        if (problem != null) {
            RlyStatusReader.fail(rel, 'Part ' + k + ' of ' + parts.size() + ': ' + problem);
            return false;
        }
        git.putFile(new RlyGitFile(partPath(rel, k), branch)
            .withContent(st.zipBase64, rel.Name + ': part ' + k + ' of ' + parts.size() + ' from ' + source.Name));
        st.zipBase64 = null;
        if (k >= parts.size()) {
            return true;
        }
        rel.Retrieve_Id__c = (k + 1) + ':' + RlyRetrieve.start(source, parts[k]);
        rel.Error_Message__c = null;
        return false;
    }

    /**
     * @description Where a part's zip goes on the release branch.
     * @param rel the release
     * @param k the part's number, from 1
     * @return .relay-inbox/<REL>-part-<k>.zip
     */
    public static String partPath(RLY_Release__c rel, Integer k) {
        return '.relay-inbox/' + rel.Name + '-part-' + k + '.zip';
    }

    /**
     * @description How far a release in parts is, for the page.
     * @param rel the release
     * @return for example Part 2 of 5, or null for a release in one part
     */
    public static String progress(RLY_Release__c rel) {
        if (rel == null || !isParted(rel.Retrieve_Id__c)) {
            return null;
        }
        Integer total = plan(byTypeOf(RlyReleaseStore.items(rel.Id))).size();
        return 'Part ' + rel.Retrieve_Id__c.substringBefore(':') + ' of ' + total;
    }

    /**
     * @description The parts: each HEAVY component alone, then the rest PART_SIZE at a time, types and names sorted.
     * @param byType the components by type
     * @return the parts, each components by type
     */
    public static List<Map<String, Set<String>>> plan(Map<String, Set<String>> byType) {
        List<Map<String, Set<String>>> parts = new List<Map<String, Set<String>>>();
        Map<String, Set<String>> current = new Map<String, Set<String>>();
        Integer inCurrent = 0;
        List<String> types = new List<String>(byType.keySet());
        types.sort();
        for (String t : types) {
            List<String> names = new List<String>(byType.get(t));
            names.sort();
            for (String n : names) {
                if (HEAVY.contains(t)) {
                    parts.add(new Map<String, Set<String>>{ t => new Set<String>{ n } });
                    continue;
                }
                if (inCurrent == PART_SIZE) {
                    parts.add(current);
                    current = new Map<String, Set<String>>();
                    inCurrent = 0;
                }
                add(current, t, n);
                inCurrent++;
            }
        }
        if (inCurrent > 0) {
            parts.add(current);
        }
        return parts;
    }

    // The release's components (not its deletions) by type, as raising grouped them.
    private static Map<String, Set<String>> byTypeOf(List<RLY_Release_Item__c> items) {
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (RLY_Release_Item__c i : items) {
            if (i.Is_Deletion__c != true) {
                add(out, i.Metadata_Type__c, i.Component_Name__c);
            }
        }
        return out;
    }

    private static void add(Map<String, Set<String>> m, String t, String n) {
        if (!m.containsKey(t)) {
            m.put(t, new Set<String>());
        }
        m.get(t).add(n);
    }
}
