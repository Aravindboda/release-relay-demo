/**
 * @description A release's deletions (Deletions__c: Type:Name, comma separated): reading them, whether they delete Apex,
 * the marker file the hub commits when a release has deletions and no components, and the "Deletes:" text of the Slack
 * card. Repository paths are mapped to Type:Name by RlyDeletionPaths.
 */
public with sharing class RlyDeletions {

    /** @description Most characters Deletions__c holds. */
    public static final Integer MAX_LENGTH = 32768;
    /** @description Names shown before "and n more". */
    public static final Integer SHOWN = 5;

    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };

    /**
     * @description The test classes a run can use: a test class the release deletes (ApexClass:Name in its deletions)
     * is left out, since the org won't have it after the deploy (a promotion carries the deletions of the releases it
     * promotes, and a rollback restores them only from its own snapshot).
     * @param tests the test class names
     * @param rel the release, with Deletions__c
     * @return the names the run can use, in the same order
     */
    public static List<String> withoutDeletedTests(List<String> tests, RLY_Release__c rel) {
        Set<String> deleted = new Set<String>();
        for (String key : of(rel)) {
            if (key.startsWithIgnoreCase('ApexClass:')) {
                deleted.add(key.substringAfter(':').trim().toLowerCase());
            }
        }
        List<String> out = new List<String>();
        for (String name : tests == null ? new List<String>() : tests) {
            if (String.isNotBlank(name) && !deleted.contains(name.trim().toLowerCase())) {
                out.add(name.trim());
            }
        }
        return out;
    }

    /**
     * @description The deletions of a release, in order.
     * @param rel the release (with Deletions__c, when it has any)
     * @return Type:Name of each (empty when there are none)
     */
    public static List<String> of(RLY_Release__c rel) {
        List<String> out = new List<String>();
        // Read through the populated fields: a release queried without Deletions__c has none to read, and that isn't an error.
        Object raw = rel == null ? null : rel.getPopulatedFieldsAsMap().get('Deletions__c');
        for (String s : raw == null ? new List<String>() : String.valueOf(raw).split(',')) {
            if (String.isNotBlank(s) && !out.contains(s.trim())) {
                out.add(s.trim());
            }
        }
        return out;
    }

    /**
     * @description Whether the release deletes an Apex class or trigger.
     * @param rel the release, with Deletions__c
     * @return true when it does
     */
    public static Boolean deletesApex(RLY_Release__c rel) {
        for (String k : of(rel)) {
            if (APEX_TYPES.contains(k.substringBefore(':'))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description The file the hub commits on the release branch when the release has deletions and no components
     * (there is no zip): .relay-inbox/<REL>.deletions, holding the deletions comma separated.
     * @param rel the release, with Name and Deletions__c
     * @param branch the release branch
     * @return the file, or null when the release has no deletions
     */
    public static RlyGitFile marker(RLY_Release__c rel, String branch) {
        List<String> keys = of(rel);
        if (keys.isEmpty()) {
            return null;
        }
        return new RlyGitFile('.relay-inbox/' + rel.Name + '.deletions', branch)
            .withContent(EncodingUtil.base64Encode(Blob.valueOf(String.join(keys, ',') + '\n')), rel.Name + ': deletions');
    }

    /**
     * @description The Slack card's line: "Deletes: " and the first few, then "and n more".
     * @param rel the release, with Deletions__c
     * @return the line (not escaped, no line break), or null when the release deletes nothing
     */
    public static String summary(RLY_Release__c rel) {
        List<String> keys = of(rel);
        if (keys.isEmpty()) {
            return null;
        }
        List<String> firstKeys = new List<String>();
        for (Integer i = 0; i < Math.min(SHOWN, keys.size()); i++) {
            firstKeys.add(keys[i]);
        }
        Integer more = keys.size() - firstKeys.size();
        return 'Deletes: ' + String.join(firstKeys, ', ') + (more > 0 ? ' and ' + more + ' more' : '');
    }
}
