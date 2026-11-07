/**
 * @description Find deleted components: the walk RlyDeletionPlan makes from the source path to its component folders.
 * Each component folder (classes, lwc, flows…) becomes a part; objects is split into parts of
 * RlyDeletionPlan.OBJECTS_PER_PART object folders. When the source path holds no component folder (it points higher,
 * for example force-app), the walk looks up to MAX_DEPTH levels below it, into at most MAX_LOOK_INTO folders a level.
 */
public with sharing class RlyDeletionWalk {

    /** @description How far below the source path component folders are looked for. */
    private static final Integer MAX_DEPTH = 3;
    /** @description Most folders looked into at one level. */
    private static final Integer MAX_LOOK_INTO = 10;
    private static final String OBJECTS = 'objects';
    private static final String TREE = 'tree';

    private RlyGitTreeReader git;
    private RlyDeletionPlan.Plan plan;

    /**
     * @description A walk that adds its parts to a plan.
     * @param git the tree reader
     * @param plan the plan
     */
    public RlyDeletionWalk(RlyGitTreeReader git, RlyDeletionPlan.Plan plan) {
        this.git = git;
        this.plan = plan;
    }

    /**
     * @description Adds the component folders of a level (objects split into groups); looks below it when it has none.
     * @param level the folder's own entries
     * @param prefix its path below the source path ('' for the source path itself)
     * @param depth 1 for the source path
     */
    public void collect(RlyGitTree.Tree level, String prefix, Integer depth) {
        plan.truncated = plan.truncated || level.truncated;
        List<RlyGitTree.Entry> others = new List<RlyGitTree.Entry>();
        Boolean found = false;
        for (RlyGitTree.Entry e : level.entries) {
            if (e.type != TREE) {
                continue;
            }
            if (RlyDeletionPaths.isComponentFolder(e.path)) {
                found = true;
                addFolder(e, prefix);
            } else {
                others.add(e);
            }
        }
        if (found || depth >= MAX_DEPTH) {
            return;
        }
        for (Integer i = 0; i < Math.min(others.size(), MAX_LOOK_INTO); i++) {
            collect(git.own(others[i].sha), prefix + others[i].path + '/', depth + 1);
        }
    }

    // A component folder: one part, or objects in groups.
    private void addFolder(RlyGitTree.Entry e, String prefix) {
        if (e.path == OBJECTS) {
            objectParts(e.sha, prefix + OBJECTS + '/');
            return;
        }
        plan.parts.add(RlyDeletionPlan.newPart(prefix + e.path,
            new List<RlyDeletionPlan.Folder>{ RlyDeletionPlan.folderAt(prefix + e.path + '/', e.sha) }));
    }

    // One part per OBJECTS_PER_PART object folders.
    private void objectParts(String sha, String prefix) {
        RlyGitTree.Tree t = git.own(sha);
        plan.truncated = plan.truncated || t.truncated;
        List<RlyDeletionPlan.Folder> bunch = new List<RlyDeletionPlan.Folder>();
        List<String> names = new List<String>();
        for (RlyGitTree.Entry e : t.entries) {
            if (e.type != TREE) {
                continue;
            }
            bunch.add(RlyDeletionPlan.folderAt(prefix + e.path + '/', e.sha));
            names.add(e.path);
            if (bunch.size() == RlyDeletionPlan.OBJECTS_PER_PART) {
                plan.parts.add(RlyDeletionPlan.newPart(objectsLabel(names), bunch));
                bunch = new List<RlyDeletionPlan.Folder>();
                names = new List<String>();
            }
        }
        if (!bunch.isEmpty()) {
            plan.parts.add(RlyDeletionPlan.newPart(objectsLabel(names), bunch));
        }
    }

    private static String objectsLabel(List<String> names) {
        return names.size() == 1 ? 'Object ' + names[0] : 'Objects ' + names[0] + ' – ' + names[names.size() - 1];
    }
}
