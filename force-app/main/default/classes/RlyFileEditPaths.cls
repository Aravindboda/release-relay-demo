/**
 * @description Build 55: which files belong to a release's components, for Edit a file (RlyFileEdit). The types Compare
 * reads (RlyCompareFiles: code, flows, layouts, permission sets, LWC and Aura bundles) keep its paths; objects and their
 * fields, record types, list views, validation rules, compact layouts, field sets and buttons, profiles, tabs, apps,
 * Lightning pages, permission set groups, custom metadata records and quick actions get theirs here. Other types
 * (static resources among them) aren't edited on the page. Paths are below the connection's source path.
 */
public with sharing class RlyFileEditPaths {

    // Object-level files compare doesn't map (Type => path pattern below the source path; {0} object, {1} member).
    private static final Map<String, String> OBJECT_FILES = new Map<String, String>{
        'CustomField' => 'objects/{0}/fields/{1}.field-meta.xml', 'RecordType' => 'objects/{0}/recordTypes/{1}.recordType-meta.xml',
        'ListView' => 'objects/{0}/listViews/{1}.listView-meta.xml', 'ValidationRule' => 'objects/{0}/validationRules/{1}.validationRule-meta.xml',
        'CompactLayout' => 'objects/{0}/compactLayouts/{1}.compactLayout-meta.xml', 'FieldSet' => 'objects/{0}/fieldSets/{1}.fieldSet-meta.xml',
        'WebLink' => 'objects/{0}/webLinks/{1}.webLink-meta.xml' };
    // One-file types compare doesn't map (Type => path pattern, {0} the name).
    private static final Map<String, String> OTHER_FILES = new Map<String, String>{
        'CustomObject' => 'objects/{0}/{0}.object-meta.xml', 'Profile' => 'profiles/{0}.profile-meta.xml',
        'CustomTab' => 'tabs/{0}.tab-meta.xml', 'CustomApplication' => 'applications/{0}.app-meta.xml',
        'FlexiPage' => 'flexipages/{0}.flexipage-meta.xml', 'PermissionSetGroup' => 'permissionsetgroups/{0}.permissionsetgroup-meta.xml',
        'CustomMetadata' => 'customMetadata/{0}.md-meta.xml', 'QuickAction' => 'quickActions/{0}.quickAction-meta.xml' };

    /**
     * @description The files of a one-file component below the source path, or null for a bundle (listed from the branch).
     * @param key Type:Name
     * @return the paths (empty for a type not edited here), or null for a bundle
     */
    public static List<String> pathsFor(String key) {
        String typeName = key.substringBefore(':');
        String name = key.substringAfter(':');
        if (OBJECT_FILES.containsKey(typeName) && name.contains('.')) { // first: custom fields are compared too (build 60)
            return new List<String>{ OBJECT_FILES.get(typeName).replace('{0}', name.substringBefore('.')).replace('{1}', name.substringAfter('.')) };
        }
        if (RlyCompareFiles.isSupported(typeName)) {
            return RlyCompareFiles.pathsOf(key);
        }
        if (OTHER_FILES.containsKey(typeName)) {
            return new List<String>{ OTHER_FILES.get(typeName).replace('{0}', name) };
        }
        return new List<String>();
    }

    /**
     * @description One of the release's components for the page.
     * @param typeName the metadata type
     * @param name the component's name
     * @return the item
     */
    public static RlyFileEdit.Item item(String typeName, String name) {
        RlyFileEdit.Item i = new RlyFileEdit.Item();
        i.type = typeName;
        i.name = name;
        i.key = typeName + ':' + name;
        List<String> paths = pathsFor(i.key);
        i.editable = paths == null || !paths.isEmpty();
        i.comparable = RlyCompareFiles.isSupported(typeName);
        return i;
    }

    /**
     * @description Refuses a key that isn't one of the release's components (deletions left out).
     * @param items the release's items
     * @param key Type:Name
     */
    public static void requireItem(List<RLY_Release_Item__c> items, String key) {
        for (RLY_Release_Item__c i : items) {
            if (i.Is_Deletion__c != true && key == i.Metadata_Type__c + ':' + i.Component_Name__c) {
                return;
            }
        }
        throw new RlyReleaseException('That component isn\'t in this release.');
    }

    /**
     * @description Refuses a path that isn't a file of one of the release's components (a one-file component's file, or
     * a file inside its bundle).
     * @param items the release's items
     * @param path the path below the source path
     */
    public static void requirePath(List<RLY_Release_Item__c> items, String path) {
        for (RLY_Release_Item__c i : items) {
            if (isSafe(path) && i.Is_Deletion__c != true && owns(i.Metadata_Type__c + ':' + i.Component_Name__c, path)) {
                return;
            }
        }
        throw new RlyReleaseException('That isn\'t a file of this release.');
    }

    // A relative path that stays below the source path.
    private static Boolean isSafe(String path) {
        return String.isNotBlank(path) && !path.contains('..') && !path.startsWith('/') && !path.contains('\\');
    }

    // Whether the path is one of the component's files.
    private static Boolean owns(String key, String path) {
        List<String> paths = pathsFor(key);
        return paths == null ? path.startsWith(RlyCompareFiles.bundleFolder(key)) : paths.contains(path);
    }

    /**
     * @description One file of the page: both branches' copies, or why it can't be shown.
     * @param path the path
     * @param mine the release branch's read (left)
     * @param theirs the target branch's read (left)
     * @return the file
     */
    public static RlyFileEdit.FileText fileText(String path, RlyCompareFiles.FileDiff mine, RlyCompareFiles.FileDiff theirs) {
        RlyFileEdit.FileText t = new RlyFileEdit.FileText();
        t.path = path;
        t.release = mine.left;
        t.target = theirs.left;
        if (mine.status == RlyCompareFiles.PENDING || theirs.status == RlyCompareFiles.PENDING) {
            t.reason = 'Not read: too many files at once. Open it again.';
        } else if (mine.status == RlyCompareFiles.UNSUPPORTED || theirs.status == RlyCompareFiles.UNSUPPORTED) {
            t.reason = String.isNotBlank(mine.reason) ? mine.reason : theirs.reason;
            t.release = null;
        }
        return t;
    }
}
