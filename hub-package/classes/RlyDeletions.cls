/**
 * @description A release's deletions (Deletions__c: Type:Name, comma separated): reading them, the repository paths a
 * component lives at (source format, under the Git connection's source path) mapped to Type:Name, the marker file the
 * hub commits when a release has deletions and no components, and the "Deletes:" text of the Slack card.
 */
public with sharing class RlyDeletions {

    /** @description Most characters Deletions__c holds. */
    public static final Integer MAX_LENGTH = 32768;
    /** @description Names shown before "and n more". */
    public static final Integer SHOWN = 5;

    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };
    // Folders whose components are one file each: folder => type and file suffix.
    private static final Map<String, List<String>> FLAT = new Map<String, List<String>>{
        'classes' => new List<String>{ 'ApexClass', '.cls' },
        'triggers' => new List<String>{ 'ApexTrigger', '.trigger' },
        'flows' => new List<String>{ 'Flow', '.flow-meta.xml' },
        'layouts' => new List<String>{ 'Layout', '.layout-meta.xml' },
        'permissionsets' => new List<String>{ 'PermissionSet', '.permissionset-meta.xml' },
        'pages' => new List<String>{ 'ApexPage', '.page' },
        'components' => new List<String>{ 'ApexComponent', '.component' },
        'staticresources' => new List<String>{ 'StaticResource', '.resource-meta.xml' },
        'tabs' => new List<String>{ 'CustomTab', '.tab-meta.xml' }
    };
    // Folders whose components are a folder each.
    private static final Map<String, String> BUNDLES = new Map<String, String>{
        'lwc' => 'LightningComponentBundle', 'aura' => 'AuraDefinitionBundle'
    };
    // Children of an object: folder => type and file suffix.
    private static final Map<String, List<String>> CHILDREN = new Map<String, List<String>>{
        'fields' => new List<String>{ 'CustomField', '.field-meta.xml' },
        'validationRules' => new List<String>{ 'ValidationRule', '.validationRule-meta.xml' },
        'recordTypes' => new List<String>{ 'RecordType', '.recordType-meta.xml' },
        'listViews' => new List<String>{ 'ListView', '.listView-meta.xml' }
    };
    private static final String OBJECTS = 'objects';

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
        List<String> shown = new List<String>();
        for (Integer i = 0; i < Math.min(SHOWN, keys.size()); i++) {
            shown.add(keys[i]);
        }
        Integer more = keys.size() - shown.size();
        return 'Deletes: ' + String.join(shown, ', ') + (more > 0 ? ' and ' + more + ' more' : '');
    }

    /**
     * @description The components these repository files are, each once, in order. Files that aren't a supported
     * component (labels, anything else) are left out.
     * @param paths file paths in the repository
     * @param sourcePath the source path they sit under (for example force-app/main/default), or blank
     * @return Type:Name of each component
     */
    public static List<String> keysOf(List<String> paths, String sourcePath) {
        String prefix = String.isBlank(sourcePath) ? '' : sourcePath.trim().removeEnd('/') + '/';
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (String p : paths) {
            String key = p.startsWith(prefix) ? keyOf(p.removeStart(prefix)) : null;
            if (key != null && seen.add(key)) {
                out.add(key);
            }
        }
        return out;
    }

    /**
     * @description The component a file is, from its path below the source path.
     * @param relativePath for example main/default/classes/AccountService.cls
     * @return Type:Name, or null when it isn't a supported component
     */
    public static String keyOf(String relativePath) {
        List<String> segs = relativePath.split('/');
        for (Integer i = 0; i < segs.size(); i++) {
            String folder = segs[i];
            if (FLAT.containsKey(folder) || BUNDLES.containsKey(folder) || folder == OBJECTS) {
                List<String> rest = new List<String>();
                for (Integer j = i + 1; j < segs.size(); j++) {
                    rest.add(segs[j]);
                }
                return keyIn(folder, rest);
            }
        }
        return null;
    }

    private static String keyIn(String folder, List<String> rest) {
        if (BUNDLES.containsKey(folder)) {
            return rest.size() >= 2 && String.isNotBlank(rest[0]) ? BUNDLES.get(folder) + ':' + rest[0] : null;
        }
        if (folder == OBJECTS) {
            return objectKey(rest);
        }
        return rest.size() == 1 ? suffixed(FLAT.get(folder), rest[0], '') : null;
    }

    private static String objectKey(List<String> rest) {
        if (rest.size() == 2 && rest[1] == rest[0] + '.object-meta.xml') {
            return 'CustomObject:' + rest[0];
        }
        if (rest.size() == 3 && CHILDREN.containsKey(rest[1])) {
            return suffixed(CHILDREN.get(rest[1]), rest[2], rest[0] + '.');
        }
        return null;
    }

    // typeAndSuffix: the type and the file suffix; the name is the file name without the suffix.
    private static String suffixed(List<String> typeAndSuffix, String fileName, String parent) {
        String suffix = typeAndSuffix[1];
        if (!fileName.endsWith(suffix) || fileName.length() == suffix.length()) {
            return null;
        }
        return typeAndSuffix[0] + ':' + parent + fileName.removeEnd(suffix);
    }
}
