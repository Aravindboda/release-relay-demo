/**
 * @description The components of nested folders in source format (RlyDeletionPaths): objects and their children,
 * components in folders (reports, dashboards, email templates) and territory models with their territories and rules.
 */
public with sharing class RlyDeletionKinds {

    // Children of an object in source format: folder => type and file suffix.
    private static final Map<String, List<String>> CHILDREN = new Map<String, List<String>>{
        'fields' => new List<String>{ 'CustomField', '.field-meta.xml' },
        'validationRules' => new List<String>{ 'ValidationRule', '.validationRule-meta.xml' },
        'recordTypes' => new List<String>{ 'RecordType', '.recordType-meta.xml' },
        'listViews' => new List<String>{ 'ListView', '.listView-meta.xml' },
        'compactLayouts' => new List<String>{ 'CompactLayout', '.compactLayout-meta.xml' },
        'webLinks' => new List<String>{ 'WebLink', '.webLink-meta.xml' },
        'fieldSets' => new List<String>{ 'FieldSet', '.fieldSet-meta.xml' },
        'businessProcesses' => new List<String>{ 'BusinessProcess', '.businessProcess-meta.xml' },
        'sharingReasons' => new List<String>{ 'SharingReason', '.sharingReason-meta.xml' },
        'indexes' => new List<String>{ 'Index', '.index-meta.xml' }
    };
    // Children of a territory model: folder => type and file suffix.
    private static final Map<String, List<String>> TERRITORY_CHILDREN = new Map<String, List<String>>{
        'territories' => new List<String>{ 'Territory2', 'territory2' },
        'rules' => new List<String>{ 'Territory2Rule', 'territory2Rule' }
    };
    private static final String META = '-meta.xml';

    /**
     * @description The component a file in a nested folder is.
     * @param r the folder's rule (objects, folder or territory)
     * @param rest the path's segments below the folder
     * @return Type:Name, or null
     */
    public static String nestedKey(RlyPathRules.Rule r, List<String> rest) {
        if (r.kind == RlyPathRules.OBJECTS) {
            return objectKey(rest);
        }
        if (r.kind == RlyPathRules.TERRITORY) {
            return territoryKey(rest);
        }
        return r.kind == RlyPathRules.FOLDERED ? folderedKey(r, rest) : null;
    }

    // reports/Sales/Q1/Pipeline.report-meta.xml → Report:Sales/Q1/Pipeline (the folder's own file isn't a component here).
    private static String folderedKey(RlyPathRules.Rule r, List<String> rest) {
        if (rest.size() < 2) {
            return null;
        }
        String name = nameOf(rest[rest.size() - 1], r.suffix);
        if (name == null) {
            return null;
        }
        List<String> folders = new List<String>();
        for (Integer i = 0; i < rest.size() - 1; i++) {
            folders.add(rest[i]);
        }
        return r.type + ':' + String.join(folders, '/') + '/' + name;
    }

    // A territory model, or one of its territories or rules (named Model.Name, as listMetadata and retrieve name them).
    private static String territoryKey(List<String> rest) {
        if (rest.size() == 2) {
            String name = nameOf(rest[1], 'territory2Model');
            return name != null && name == rest[0] ? 'Territory2Model:' + name : null;
        }
        if (rest.size() == 3 && TERRITORY_CHILDREN.containsKey(rest[1])) {
            List<String> child = TERRITORY_CHILDREN.get(rest[1]);
            String name = nameOf(rest[2], child[1]);
            return name == null ? null : child[0] + ':' + rest[0] + '.' + name;
        }
        return null;
    }

    private static String objectKey(List<String> rest) {
        if (rest.size() == 2 && rest[1] == rest[0] + '.object' + META) {
            return 'CustomObject:' + rest[0];
        }
        if (rest.size() == 3 && CHILDREN.containsKey(rest[1])) {
            List<String> child = CHILDREN.get(rest[1]);
            String file = rest[2];
            return file.endsWith(child[1]) && file.length() > child[1].length() ? child[0] + ':' + rest[0] + '.' + file.removeEnd(child[1]) : null;
        }
        return null;
    }

    /**
     * @description A component's name from its file name.
     * @param fileName for example X.cls-meta.xml or X.cls
     * @param suffix the type's suffix, for example cls
     * @return X, or null (blank suffix, or another file)
     */
    public static String nameOf(String fileName, String suffix) {
        if (String.isBlank(suffix)) {
            return null;
        }
        String withMeta = withoutEnd(fileName, '.' + suffix + META);
        return withMeta != null ? withMeta : withoutEnd(fileName, '.' + suffix);
    }

    // The file name without an ending, or null when it doesn't end with it (or is only the ending).
    private static String withoutEnd(String fileName, String ending) {
        return fileName.endsWith(ending) && fileName.length() > ending.length() ? fileName.removeEnd(ending) : null;
    }
}
