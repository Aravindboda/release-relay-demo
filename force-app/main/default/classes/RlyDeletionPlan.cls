/**
 * @description Find deleted components, the branch side, in parts (RlyChangePartsController), so no call reads the
 * whole repository:
 *   build     walks to the source path (one tree per folder level, not the whole repository), lists its component folders
 *         (classes, lwc, flows…) and the object folders under objects, and returns one part per component folder and
 *         one per OBJECTS_PER_PART objects, each with its folders' tree shas
 *   readPart  reads one part's folders (each tree by its sha, recursively) and returns the components on the branch
 * GitHub only (the other providers can't list files from the hub yet). A tree GitHub cut short sets truncated, and
 * the page says so. The org side is RlyDeletionPresence; the page compares the two.
 */
public with sharing class RlyDeletionPlan {

    /** @description Object folders per part. */
    public static final Integer OBJECTS_PER_PART = 15;
    /** @description Most folders one part takes. */
    public static final Integer MAX_FOLDERS_PER_PART = 30;
    private static final String TREE = 'tree';
    private static final Pattern SHA_PATTERN = Pattern.compile('^[0-9a-f]{40}$');

    /** @description The parts of the branch to read. */
    public class Plan {
        /** @description The branch read. */
        @AuraEnabled public String branch;
        /** @description The parts, one call each. */
        @AuraEnabled public List<Part> parts = new List<Part>();
        /** @description GitHub cut a folder list short: some folders may be missing. */
        @AuraEnabled public Boolean truncated = false;
    }

    /** @description One part: some folders of the branch. */
    public class Part {
        /** @description Its id. */
        @AuraEnabled public String id;
        /** @description What it covers, for example classes or Objects Account – Invoice__c. */
        @AuraEnabled public String label;
        /** @description Its folders. */
        @AuraEnabled public List<Folder> folders = new List<Folder>();
    }

    /** @description One folder: where it is below the source path and its tree's sha. */
    public class Folder {
        /** @description Its path below the source path, ending with /, for example classes/ or objects/Invoice__c/. */
        @AuraEnabled public String prefix;
        /** @description Its tree's sha. */
        @AuraEnabled public String sha;
    }

    /** @description What one part found on the branch. */
    public class PartResult {
        /** @description The components (Type:Name), each once. */
        @AuraEnabled public List<String> keys = new List<String>();
        /** @description GitHub cut a folder short: some files may be missing. */
        @AuraEnabled public Boolean truncated = false;
    }

    /**
     * @description The parts of the org's branch.
     * @param org the developer org
     * @return the plan (no parts when the source path isn't on the branch)
     */
    public static Plan build(RLY_Org__c org) {
        RlyGitTreeReader git = reader();
        Plan p = new Plan();
        p.branch = RlyDeletionFinder.branchOf(org);
        RlyGitTree.Tree level = git.own(p.branch);
        String sourcePath = RlyDeletionFinder.sourcePath();
        for (String segment : String.isBlank(sourcePath) ? new List<String>() : sourcePath.split('/')) {
            p.truncated = p.truncated || level.truncated;
            RlyGitTree.Entry next = folderNamed(level, segment);
            if (next == null) {
                return p;
            }
            level = git.own(next.sha);
        }
        new RlyDeletionWalk(git, p).collect(level, '', 1);
        Integer n = 1;
        for (Part pt : p.parts) {
            pt.id = 'p' + n++;
        }
        return p;
    }

    /**
     * @description Reads one part's folders.
     * @param given the part (from the plan)
     * @return the components on the branch
     */
    public static PartResult readPart(Part given) {
        checkPart(given);
        RlyGitTreeReader git = reader();
        PartResult r = new PartResult();
        Set<String> seen = new Set<String>();
        for (Folder f : given.folders) {
            RlyGitTree.Tree t = git.below(f.sha);
            r.truncated = r.truncated || t.truncated;
            List<String> paths = new List<String>();
            for (RlyGitTree.Entry e : t.entries) {
                if (e.type == 'blob' && e.path != null) {
                    paths.add(f.prefix + e.path);
                }
            }
            for (String k : RlyDeletionPaths.keysOf(paths, '')) {
                if (seen.add(k)) {
                    r.keys.add(k);
                }
            }
        }
        return r;
    }

    // The tree reader on the hub's Git connection (checked: connected).
    private static RlyGitTreeReader reader() {
        RlyDeletionFinder.git();
        return new RlyGitTreeReader(RlyReleaseStore.git());
    }

    /**
     * @description A part of some folders.
     * @param label what it covers
     * @param folders its folders
     * @return the part
     */
    public static Part newPart(String label, List<Folder> folders) {
        Part p = new Part();
        p.label = label;
        p.folders = folders;
        return p;
    }

    /**
     * @description A folder of a part.
     * @param prefix its path below the source path, ending with /
     * @param sha its tree's sha
     * @return the folder
     */
    public static Folder folderAt(String prefix, String sha) {
        Folder f = new Folder();
        f.prefix = prefix;
        f.sha = sha;
        return f;
    }

    private static RlyGitTree.Entry folderNamed(RlyGitTree.Tree level, String name) {
        for (RlyGitTree.Entry e : level.entries) {
            if (e.type == TREE && e.path == name) {
                return e;
            }
        }
        return null;
    }

    // A part from the page: 1 to MAX_FOLDERS_PER_PART folders, each a 40-character sha and a plain relative path.
    private static void checkPart(Part given) {
        Boolean sized = given != null && given.folders != null && !given.folders.isEmpty() && given.folders.size() <= MAX_FOLDERS_PER_PART;
        if (!sized) {
            throw new RlyReleaseException('That part of the branch isn\'t valid: find deleted components again.');
        }
        for (Folder f : given.folders) {
            Boolean ok = f != null && f.sha != null && SHA_PATTERN.matcher(f.sha).matches() && f.prefix != null && f.prefix.endsWith('/')
                && !f.prefix.contains('..') && !f.prefix.startsWith('/') && f.prefix.length() <= 400;
            if (!ok) {
                throw new RlyReleaseException('That part of the branch isn\'t valid: find deleted components again.');
            }
        }
    }
}
