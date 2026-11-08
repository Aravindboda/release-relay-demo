/**
 * @description Compare on Review: which components can be compared and where their files are. A Metadata API zip path
 * (classes/X.cls, lwc/x/x.js, flows/X.flow…) maps to its component (Type:Name) and to its path in source format below the
 * Git connection's source path (flows/X.flow becomes flows/X.flow-meta.xml). Static resources and profiles (build 50: large
 * files) are left out, here and in the pipeline, with a link to the file on the branch; types whose files differ between
 * the two formats (objects, fields, record types…) aren't compared. Also the file and component statuses the page shows.
 */
public with sharing class RlyCompareFiles {

    /** @description Most components one compare takes. */
    public static final Integer MAX_COMPONENTS = 25;
    /** @description Largest file compared, in characters. */
    public static final Integer MAX_FILE_CHARS = 300000;
    /** @description Status: the branch has a different copy. */
    public static final String CHANGED = 'changed';
    /** @description Status: both sides are the same. */
    public static final String SAME = 'same';
    /** @description Status: the branch doesn't have it yet (the API value is new). */
    public static final String ADDED = 'new';
    /** @description Status: the release deletes it. */
    public static final String REMOVED = 'deleted';
    /** @description Status: compare can't show it (the reason says why). */
    public static final String UNSUPPORTED = 'unsupported';
    /** @description Status: the branch's copy is still to be read (the page asks again). */
    public static final String PENDING = 'pending';
    /** @description Reason for a file over MAX_FILE_CHARS. */
    public static final String TOO_LARGE = 'Too large to compare here';
    /** @description Reason for a type compare leaves out (static resources, profiles): the page links to the file. */
    public static final String LEFT_OUT = 'Not compared: open it in Git.';

    private static final String META = '-meta.xml';
    // Folder in the zip and in source format => type.
    private static final Map<String, String> TYPE_IN = new Map<String, String>{
        'classes' => 'ApexClass', 'triggers' => 'ApexTrigger', 'pages' => 'ApexPage', 'components' => 'ApexComponent',
        'flows' => 'Flow', 'layouts' => 'Layout', 'permissionsets' => 'PermissionSet',
        'lwc' => 'LightningComponentBundle', 'aura' => 'AuraDefinitionBundle'
    };
    // Type => folder.
    private static final Map<String, String> FOLDER_OF = new Map<String, String>{
        'ApexClass' => 'classes', 'ApexTrigger' => 'triggers', 'ApexPage' => 'pages', 'ApexComponent' => 'components',
        'Flow' => 'flows', 'Layout' => 'layouts', 'PermissionSet' => 'permissionsets',
        'LightningComponentBundle' => 'lwc', 'AuraDefinitionBundle' => 'aura'
    };
    // One-file types => Metadata API suffix. Code files have a -meta.xml beside them; XML types get -meta.xml in source format.
    private static final Map<String, String> SUFFIX = new Map<String, String>{
        'ApexClass' => '.cls', 'ApexTrigger' => '.trigger', 'ApexPage' => '.page', 'ApexComponent' => '.component',
        'Flow' => '.flow', 'Layout' => '.layout', 'PermissionSet' => '.permissionset'
    };
    private static final Set<String> XML_TYPES = new Set<String>{ 'Flow', 'Layout', 'PermissionSet' };
    // Types compare leaves out (large files) => their file in source format, {0} the name.
    private static final Map<String, String> LEFT_OUT_FILES = new Map<String, String>{
        'StaticResource' => 'staticresources/{0}.resource-meta.xml', 'Profile' => 'profiles/{0}.profile-meta.xml' };
    // A bundle's main file: type => extension of the file named like the bundle.
    private static final Map<String, String> BUNDLE_MAIN = new Map<String, String>{ 'LightningComponentBundle' => '.js', 'AuraDefinitionBundle' => '.cmp' };

    /** @description One file of a component, both sides. */
    public class FileDiff {
        /** @description Path in source format below the source path, for example classes/AccountService.cls. */
        @AuraEnabled public String path;
        /** @description The branch's copy (null: not on the branch, or not read). */
        @AuraEnabled public String left;
        /** @description The developer org's copy (null: deleted, or not read). */
        @AuraEnabled public String right;
        /** @description changed, same, new, deleted, unsupported or pending. */
        @AuraEnabled public String status;
        /** @description Why it isn't compared, for unsupported. */
        @AuraEnabled public String reason;
        /** @description A compare in the pipeline: the file's number (its text is read when it's opened), or null. */
        @AuraEnabled public Integer n;
        /** @description A compare in the pipeline: a file too large for both copies comes as a unified diff. */
        @AuraEnabled public String patch;
    }

    /** @description One component: its status (its main file's) and its files, main file first. */
    public class ComponentDiff {
        /** @description Type:Name. */
        @AuraEnabled public String key;
        /** @description The status the list shows: its main file's, or unsupported. */
        @AuraEnabled public String status;
        /** @description Why it isn't compared, for unsupported. */
        @AuraEnabled public String reason;
        /** @description The release deletes it. */
        @AuraEnabled public Boolean deleted = false;
        /** @description Its files, main file first. */
        @AuraEnabled public List<FileDiff> files = new List<FileDiff>();
        /** @description A type compare leaves out: its file on the compared branch, or null. */
        @AuraEnabled public String gitUrl;
    }

    /**
     * @description Whether compare leaves this type out (static resources and profiles: their files are large).
     * @param typeName the metadata type
     * @return true when it's left out
     */
    public static Boolean isLeftOut(String typeName) {
        return LEFT_OUT_FILES.containsKey(typeName);
    }

    /**
     * @description Links each left-out component (static resource, profile) to its file on the branch.
     * @param components the components
     * @param branchWeb the branch's web address (RlyGit.branchUrl), or null when the provider has none
     * @param prefix the source path with its trailing slash (blank: the repository root)
     */
    public static void linkLeftOut(List<ComponentDiff> components, String branchWeb, String prefix) {
        for (ComponentDiff c : components) {
            String path = leftOutPath(c.key);
            if (path != null && branchWeb != null) {
                List<String> segs = new List<String>();
                for (String s : (prefix + path).split('/')) {
                    segs.add(EncodingUtil.urlEncode(s, 'UTF-8').replace('+', '%20'));
                }
                c.gitUrl = branchWeb + (branchWeb.contains('?') ? '&path=/' : '/') + String.join(segs, '/');
            }
        }
    }

    /**
     * @description A left-out component's file in source format, below the source path.
     * @param key Type:Name
     * @return the path, or null when the type isn't left out
     */
    public static String leftOutPath(String key) {
        String pathPattern = LEFT_OUT_FILES.get(key.substringBefore(':'));
        return pathPattern == null ? null : pathPattern.replace('{0}', key.substringAfter(':'));
    }

    /**
     * @description Whether compare can show this type.
     * @param typeName the metadata type
     * @return true for code, flows, layouts, permission sets, LWC and Aura bundles
     */
    public static Boolean isSupported(String typeName) {
        return FOLDER_OF.containsKey(typeName);
    }

    /**
     * @description Why compare can't show a type.
     * @param typeName the metadata type
     * @return the reason the page shows
     */
    public static String reasonFor(String typeName) {
        if (isLeftOut(typeName)) {
            return LEFT_OUT;
        }
        return 'Compare isn\'t available for ' + typeName + ' yet — see the pull request\'s Changes after raising';
    }

    /**
     * @description The component a Metadata API zip path belongs to.
     * @param zipPath for example classes/AccountService.cls-meta.xml or lwc/accountCard/accountCard.js
     * @return Type:Name, or null when compare doesn't show that file
     */
    public static String keyOf(String zipPath) {
        List<String> segs = zipPath.split('/');
        String typeName = segs.size() < 2 ? null : TYPE_IN.get(segs[0]);
        if (typeName == null) {
            return null;
        }
        String ending = SUFFIX.get(typeName);
        if (ending == null) {
            return segs.size() >= 3 && String.isNotBlank(segs[1]) ? typeName + ':' + segs[1] : null;
        }
        String fileName = segs.size() == 2 ? segs[1].removeEnd(META) : '';
        return fileName.endsWith(ending) && fileName.length() > ending.length() ? typeName + ':' + decoded(fileName.removeEnd(ending)) : null;
    }

    /**
     * @description A zip path in source format: the XML types (flows, layouts, permission sets) gain -meta.xml.
     * @param zipPath the Metadata API path
     * @return the path below the source path
     */
    public static String sourcePathOf(String zipPath) {
        String typeName = TYPE_IN.get(zipPath.substringBefore('/'));
        return XML_TYPES.contains(typeName) && !zipPath.endsWith(META) ? zipPath + META : zipPath;
    }

    /**
     * @description The source-format files of a one-file component (deletions need them without a zip).
     * @param key Type:Name
     * @return the paths below the source path, or null for a bundle (its files are listed from the branch)
     */
    public static List<String> pathsOf(String key) {
        String typeName = key.substringBefore(':');
        String ending = SUFFIX.get(typeName);
        if (ending == null) {
            return null;
        }
        String main = FOLDER_OF.get(typeName) + '/' + key.substringAfter(':') + ending;
        return XML_TYPES.contains(typeName) ? new List<String>{ main + META } : new List<String>{ main, main + META };
    }

    /**
     * @description A bundle's folder below the source path, with a trailing slash.
     * @param key Type:Name of an LWC or Aura bundle
     * @return for example lwc/accountCard/
     */
    public static String bundleFolder(String key) {
        return FOLDER_OF.get(key.substringBefore(':')) + '/' + key.substringAfter(':') + '/';
    }

    /**
     * @description Puts a component's main file first, the others by path.
     * @param key Type:Name
     * @param files the component's files
     * @return the files, main first
     */
    public static List<FileDiff> mainFirst(String key, List<FileDiff> files) {
        String main = mainPath(key).toLowerCase();
        Map<String, FileDiff> byPath = new Map<String, FileDiff>();
        for (FileDiff f : files) {
            byPath.put(f.path, f);
        }
        List<String> paths = new List<String>(byPath.keySet());
        paths.sort();
        FileDiff mainFile;
        List<FileDiff> out = new List<FileDiff>();
        for (String p : paths) {
            if (mainFile == null && p.toLowerCase() == main) {
                mainFile = byPath.get(p);
            } else {
                out.add(byPath.get(p));
            }
        }
        if (mainFile == null) {
            return out;
        }
        // Apex can't add at index 0 of an empty list.
        List<FileDiff> ordered = new List<FileDiff>{ mainFile };
        ordered.addAll(out);
        return ordered;
    }

    private static String mainPath(String key) {
        String typeName = key.substringBefore(':');
        if (BUNDLE_MAIN.containsKey(typeName)) {
            return bundleFolder(key) + key.substringAfter(':') + BUNDLE_MAIN.get(typeName);
        }
        List<String> paths = pathsOf(key);
        return paths == null ? '' : paths[0];
    }

    // Layout and other names are URL-encoded in file names (%28 for "(", for example).
    private static String decoded(String name) {
        try {
            return EncodingUtil.urlDecode(name.replace('+', '%2B'), 'UTF-8');
        } catch (Exception e) {
            return name;
        }
    }
}
