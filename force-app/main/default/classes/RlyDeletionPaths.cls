/**
 * @description Repository paths of components in source format (under the Git connection's source path) mapped to
 * Type:Name: classes, triggers, lwc and aura bundles, objects and their fields, validation rules, record types and list
 * views, flows, layouts, permission sets, pages, Visualforce components, static resources and tabs. Anything else
 * (labels among them) is left out.
 */
public with sharing class RlyDeletionPaths {

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
     * @description The files of a Git tree answer (GitHub: {tree:[{path,type}]}) under a path.
     * @param treeJson the parsed answer
     * @param path the folder (blank: every file)
     * @return the file paths
     */
    public static List<String> blobs(Object treeJson, String path) {
        String prefix = String.isBlank(path) ? '' : path.trim().removeEnd('/') + '/';
        Object tree = treeJson instanceof Map<String, Object> ? ((Map<String, Object>) treeJson).get('tree') : null;
        List<String> out = new List<String>();
        for (Object o : tree instanceof List<Object> ? (List<Object>) tree : new List<Object>()) {
            Map<String, Object> entry = (Map<String, Object>) o;
            String filePath = String.valueOf(entry.get('path'));
            if (String.valueOf(entry.get('type')) == 'blob' && filePath.startsWith(prefix)) {
                out.add(filePath);
            }
        }
        return out;
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
