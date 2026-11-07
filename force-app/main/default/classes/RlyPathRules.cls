/**
 * @description Which folder of a branch (in source format) holds which metadata type, so a file's path gives its
 * component (RlyDeletionPaths). Read from the developer org's describeMetadata (each type's directoryName, suffix and
 * inFolder), so every type the org has is covered (build 37.1); the fixed rules (FALLBACK) fill folders the org didn't
 * describe and are used alone when describeMetadata can't be read. Kinds:
 *   file    one file per component in the folder: <Name>.<suffix>-meta.xml (and <Name>.<suffix> for types with a
 *           content file, such as classes/X.cls)
 *   bundle  one folder per component (lwc, aura)
 *   folder  components in folders (reports/<Folder>/<Name>.report-meta.xml → Report:<Folder>/<Name>)
 *   objects objects and their children (fields, record types… RlyDeletionPaths)
 *   territory Enterprise Territory Management models with their territories and rules (territory2Models/<Model>/…)
 * The page gets the rules with the plan and sends them back with each part (checked here), so a part needs no
 * describeMetadata call of its own.
 */
public with sharing class RlyPathRules {

    /** @description One file per component. */
    public static final String FILE = 'file';
    /** @description One folder per component. */
    public static final String BUNDLE = 'bundle';
    /** @description Components in folders. */
    public static final String FOLDERED = 'folder';
    /** @description Objects and their children. */
    public static final String OBJECTS = 'objects';
    /** @description Territory models with their territories and rules. */
    public static final String TERRITORY = 'territory';
    /** @description Most rules a part may send back. */
    public static final Integer MAX_RULES = 800;

    private static final Pattern WORD_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_.-]{0,79}$');
    private static final Set<String> KINDS = new Set<String>{ FILE, BUNDLE, FOLDERED, OBJECTS, TERRITORY };
    // Folders whose layout the fixed rule describes better than describeMetadata (several types share them).
    private static final Set<String> FORCED = new Set<String>{ 'objects', 'territory2Models' };
    // Types whose files can't be told apart by name: left out (Document names keep their file extension).
    private static final Set<String> UNMAPPED = new Set<String>{ 'Document' };
    // dir => type, suffix, kind: the folders every org has, used when describeMetadata isn't there.
    private static final Map<String, List<String>> FALLBACK = new Map<String, List<String>>{
        'classes' => new List<String>{ 'ApexClass', 'cls', FILE },
        'triggers' => new List<String>{ 'ApexTrigger', 'trigger', FILE },
        'flows' => new List<String>{ 'Flow', 'flow', FILE },
        'layouts' => new List<String>{ 'Layout', 'layout', FILE },
        'permissionsets' => new List<String>{ 'PermissionSet', 'permissionset', FILE },
        'pages' => new List<String>{ 'ApexPage', 'page', FILE },
        'components' => new List<String>{ 'ApexComponent', 'component', FILE },
        'staticresources' => new List<String>{ 'StaticResource', 'resource', FILE },
        'tabs' => new List<String>{ 'CustomTab', 'tab', FILE },
        'queues' => new List<String>{ 'Queue', 'queue', FILE },
        'groups' => new List<String>{ 'Group', 'group', FILE },
        'globalValueSets' => new List<String>{ 'GlobalValueSet', 'globalValueSet', FILE },
        'flexipages' => new List<String>{ 'FlexiPage', 'flexipage', FILE },
        'quickActions' => new List<String>{ 'QuickAction', 'quickAction', FILE },
        'customPermissions' => new List<String>{ 'CustomPermission', 'customPermission', FILE },
        'lwc' => new List<String>{ 'LightningComponentBundle', '', BUNDLE },
        'aura' => new List<String>{ 'AuraDefinitionBundle', '', BUNDLE },
        'objects' => new List<String>{ 'CustomObject', 'object', OBJECTS },
        'territory2Models' => new List<String>{ 'Territory2Model', 'territory2Model', TERRITORY },
        'territory2Types' => new List<String>{ 'Territory2Type', 'territory2Type', FILE },
        'objectTerritory2AssignmentRules' => new List<String>{ 'ObjectTerritory2AssignmentRule', 'objectTerritory2AssignmentRule', FILE },
        'settings' => new List<String>{ 'Settings', 'settings', FILE }
    };

    /** @description One folder's rule. */
    public class Rule {
        /** @description The folder's name, for example classes. */
        @AuraEnabled public String dir;
        /** @description The metadata type, for example ApexClass. */
        @AuraEnabled public String type;
        /** @description The file suffix without the dot, for example cls (blank for bundles). */
        @AuraEnabled public String suffix;
        /** @description file, bundle, folder, objects or territory. */
        @AuraEnabled public String kind;
    }

    /** @description The rules for an org, with its own namespace. */
    public class Described {
        /** @description The rules, sorted by folder. */
        public List<Rule> rules;
        /** @description The org's namespace (describeMetadata organizationNamespace), blank for most orgs. */
        public String namespace = '';
    }

    /**
     * @description The rules for a developer org: its describeMetadata, then the fixed rules for folders it didn't
     * describe. describeMetadata failing gives the fixed rules alone.
     * @param org the developer org
     * @return the rules, sorted by folder
     */
    public static List<Rule> forOrg(RLY_Org__c org) {
        return forOrgWithNamespace(org).rules;
    }

    /**
     * @description The rules for a developer org and its own namespace.
     * @param org the developer org
     * @return the rules and the namespace
     */
    public static Described forOrgWithNamespace(RLY_Org__c org) {
        Described d = new Described();
        List<Rule> described = new List<Rule>();
        try {
            Dom.XmlNode result = RlySoapClient.call(org, 'describeMetadata', '<met:asOfVersion>' + RlyOrgSession.API_VERSION + '</met:asOfVersion>');
            described = fromDescribe(result);
            String ns = RlySoapClient.text(result, 'organizationNamespace');
            d.namespace = String.isBlank(ns) ? '' : ns.trim();
        } catch (Exception e) {
            described = new List<Rule>(); // the fixed rules still find the common types
        }
        d.rules = merged(described);
        return d;
    }

    /**
     * @description The fixed rules alone.
     * @return the rules, sorted by folder
     */
    public static List<Rule> fallback() {
        return merged(new List<Rule>());
    }

    /**
     * @description The rules by folder.
     * @param rules the rules (null: the fixed rules)
     * @return folder => rule
     */
    public static Map<String, Rule> byDir(List<Rule> rules) {
        Map<String, Rule> out = new Map<String, Rule>();
        for (Rule r : rules == null ? fallback() : rules) {
            out.put(r.dir, r);
        }
        return out;
    }

    /**
     * @description Rules sent back by the page, checked: plain names, a known kind, at most MAX_RULES.
     * @param given the rules (null or empty: the fixed rules)
     * @return the rules
     */
    public static List<Rule> checked(List<Rule> given) {
        if (given == null || given.isEmpty()) {
            return fallback();
        }
        if (given.size() > MAX_RULES) {
            throw new RlyReleaseException('That part of the branch isn\'t valid: read the branch again.');
        }
        for (Rule r : given) {
            Boolean ok = r != null && plain(r.dir) && plain(r.type) && KINDS.contains(r.kind) && (String.isBlank(r.suffix) || plain(r.suffix));
            if (!ok) {
                throw new RlyReleaseException('That part of the branch isn\'t valid: read the branch again.');
            }
        }
        return given;
    }

    /**
     * @description The rules in a describeMetadata answer: one per type with a folder, the first type of a folder wins.
     * @param result the describeMetadata result node
     * @return the rules
     */
    public static List<Rule> fromDescribe(Dom.XmlNode result) {
        List<Rule> out = new List<Rule>();
        Set<String> dirs = new Set<String>();
        for (Dom.XmlNode obj : result.getChildElements()) {
            Rule r = obj.getName() == 'metadataObjects' ? ruleOf(obj) : null;
            if (r != null && dirs.add(r.dir)) {
                out.add(r);
            }
        }
        return out;
    }

    // A type's rule, or null for a type without a folder (or one left out).
    private static Rule ruleOf(Dom.XmlNode obj) {
        String xmlName = RlySoapClient.text(obj, 'xmlName');
        String dir = RlySoapClient.text(obj, 'directoryName');
        if (String.isBlank(xmlName) || String.isBlank(dir) || UNMAPPED.contains(xmlName)) {
            return null;
        }
        String suffix = RlySoapClient.text(obj, 'suffix');
        String kind;
        if (xmlName == 'CustomObject') {
            kind = OBJECTS;
        } else if (RlySoapClient.text(obj, 'inFolder') == 'true') {
            kind = FOLDERED;
        } else {
            kind = String.isBlank(suffix) ? BUNDLE : FILE;
        }
        return rule(dir, new List<String>{ xmlName, suffix, kind });
    }

    // The described rules, then the fixed rules for folders not described; sorted by folder.
    private static List<Rule> merged(List<Rule> described) {
        Map<String, Rule> out = new Map<String, Rule>();
        for (Rule r : described) {
            out.put(r.dir, r);
        }
        for (String dir : FALLBACK.keySet()) {
            if (!out.containsKey(dir) || FORCED.contains(dir)) {
                out.put(dir, rule(dir, FALLBACK.get(dir)));
            }
        }
        List<String> dirs = new List<String>(out.keySet());
        dirs.sort();
        List<Rule> sorted = new List<Rule>();
        for (String d : dirs) {
            sorted.add(out.get(d));
        }
        return sorted;
    }

    // spec: the type, the suffix and the kind.
    private static Rule rule(String dir, List<String> spec) {
        Rule r = new Rule();
        r.dir = dir;
        r.type = spec[0];
        r.suffix = String.isBlank(spec[1]) ? '' : spec[1];
        r.kind = spec[2];
        return r;
    }

    private static Boolean plain(String s) {
        return String.isNotBlank(s) && WORD_PATTERN.matcher(s).matches();
    }
}
