/**
 * @description Repository paths of components in source format (under the Git connection's source path) mapped to
 * Type:Name with the folder rules of RlyPathRules: every type the developer org describes (build 37.1), else the fixed
 * rules (classes, triggers, lwc and aura bundles, objects and their children, flows, layouts, permission sets, pages,
 * Visualforce components, static resources, tabs, queues, groups, global value sets, Lightning pages, quick actions and
 * custom permissions). Objects' children come from their folders: fields, validation rules, record types, list views,
 * compact layouts, links and buttons, field sets, business processes, sharing reasons and indexes. Org settings are
 * <Name>Settings. Territory models: territory2Models/<Model>/<Model>.territory2Model-meta.xml → Territory2Model:<Model>,
 * …/territories/<T>.territory2-meta.xml → Territory2:<Model>.<T>, …/rules/<R>.territory2Rule-meta.xml →
 * Territory2Rule:<Model>.<R>. Anything else (files that aren't a component's) is left out.
 */
public with sharing class RlyDeletionPaths {

    private static final String SETTINGS_DIR = 'settings';

    /**
     * @description The components these repository files are, each once, in order, with the fixed folder rules.
     * @param paths file paths in the repository
     * @param sourcePath the source path they sit under (for example force-app/main/default), or blank
     * @return Type:Name of each component
     */
    public static List<String> keysOf(List<String> paths, String sourcePath) {
        return keysOf(paths, sourcePath, RlyPathRules.byDir(null));
    }

    /**
     * @description The components these repository files are, each once, in order.
     * @param paths file paths in the repository
     * @param sourcePath the source path they sit under, or blank
     * @param rules the folder rules (RlyPathRules.byDir)
     * @return Type:Name of each component
     */
    public static List<String> keysOf(List<String> paths, String sourcePath, Map<String, RlyPathRules.Rule> rules) {
        String prefix = String.isBlank(sourcePath) ? '' : sourcePath.trim().removeEnd('/') + '/';
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (String p : paths) {
            String key = p.startsWith(prefix) ? keyOf(p.removeStart(prefix), rules) : null;
            if (key != null && seen.add(key)) {
                out.add(key);
            }
        }
        return out;
    }

    /**
     * @description Whether a folder holds components, with the fixed folder rules.
     * @param folder the folder's name
     * @return true for a component folder
     */
    public static Boolean isComponentFolder(String folder) {
        return RlyPathRules.byDir(null).containsKey(folder);
    }

    /**
     * @description The component a file is, from its path below the source path, with the fixed folder rules.
     * @param relativePath for example main/default/classes/AccountService.cls
     * @return Type:Name, or null when it isn't a component's file
     */
    public static String keyOf(String relativePath) {
        return keyOf(relativePath, RlyPathRules.byDir(null));
    }

    /**
     * @description The component a file is, from its path below the source path: the first folder with a rule decides.
     * @param relativePath for example main/default/reports/Sales/Pipeline.report-meta.xml
     * @param rules the folder rules (RlyPathRules.byDir)
     * @return Type:Name, or null when it isn't a component's file
     */
    public static String keyOf(String relativePath, Map<String, RlyPathRules.Rule> rules) {
        List<String> segs = relativePath.split('/');
        Integer at = 0;
        while (at < segs.size() && !rules.containsKey(segs[at])) {
            at++;
        }
        return at < segs.size() ? keyIn(rules.get(segs[at]), restAfter(segs, at)) : null;
    }

    // The segments after one.
    private static List<String> restAfter(List<String> segs, Integer at) {
        List<String> rest = new List<String>();
        for (Integer j = at + 1; j < segs.size(); j++) {
            rest.add(segs[j]);
        }
        return rest;
    }

    private static String keyIn(RlyPathRules.Rule r, List<String> rest) {
        if (r.kind == RlyPathRules.BUNDLE) {
            return rest.size() >= 2 && String.isNotBlank(rest[0]) ? r.type + ':' + rest[0] : null;
        }
        if (r.kind != RlyPathRules.FILE) {
            return RlyDeletionKinds.nestedKey(r, rest);
        }
        String name = rest.size() == 1 ? RlyDeletionKinds.nameOf(rest[0], r.suffix) : null;
        if (name == null) {
            return null;
        }
        return r.dir == SETTINGS_DIR ? name + 'Settings:' + name : r.type + ':' + name;
    }
}
