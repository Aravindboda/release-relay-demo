/**
 * @description Compare on Review: reads the target branch's copies through the Git connection, one call per file under
 * the connection's source path (not there = null). It stays under RlyCompareRun's callout and text budgets: a file it
 * can't read now is left pending and more is set, so the page asks again for just those paths.
 */
public with sharing class RlyCompareBranch {

    /** @description Some files were left pending. */
    public Boolean more = false;

    private RlyGit git;
    private String sourcePath;
    private String branch;
    private Integer chars = 0;
    private List<String> tree;

    /**
     * @description A reader of one branch.
     * @param git the Git provider
     * @param sourcePath the connection's source path (blank: the repository root)
     * @param branch the branch
     */
    public RlyCompareBranch(RlyGit git, String sourcePath, String branch) {
        this.git = git;
        this.sourcePath = String.isBlank(sourcePath) ? '' : sourcePath.trim().removeEnd('/');
        this.branch = branch;
    }

    /**
     * @description What a deleted component's files say when the branch doesn't have them.
     * @return the reason
     */
    public String notThere() {
        return 'Not on the ' + branch + ' branch either.';
    }

    /**
     * @description The branch's files in a folder below the source path (the branch's tree is listed once).
     * @param folder for example lwc/accountCard/
     * @return the paths below the source path
     */
    public List<String> filesUnder(String folder) {
        if (tree == null) {
            tree = git.listFiles(branch, sourcePath);
        }
        String prefix = prefix();
        List<String> out = new List<String>();
        for (String p : tree) {
            if (p.startsWith(prefix + folder)) {
                out.add(p.removeStart(prefix));
            }
        }
        return out;
    }

    /**
     * @description Reads the branch's copy of every file without a status and sets its status, main files first so the
     * list's chips fill in first; then each component's status.
     * @param components the components
     */
    public void readAll(List<RlyCompareFiles.ComponentDiff> components) {
        for (RlyCompareFiles.FileDiff f : mainsFirst(components)) {
            if (f.status == null && fetch(f)) {
                f.status = RlyCompareParts.statusOf(f.left, f.right);
                f.reason = f.left == null && f.right == null ? notThere() : null;
            }
        }
        for (RlyCompareFiles.ComponentDiff c : components) {
            RlyCompareParts.settle(c);
        }
    }

    // Every component's main file, then the other files.
    private static List<RlyCompareFiles.FileDiff> mainsFirst(List<RlyCompareFiles.ComponentDiff> components) {
        List<RlyCompareFiles.FileDiff> ordered = new List<RlyCompareFiles.FileDiff>();
        List<RlyCompareFiles.FileDiff> others = new List<RlyCompareFiles.FileDiff>();
        for (RlyCompareFiles.ComponentDiff c : components) {
            List<RlyCompareFiles.FileDiff> files = c.files.clone();
            if (!files.isEmpty()) {
                ordered.add(files.remove(0));
            }
            others.addAll(files);
        }
        ordered.addAll(others);
        return ordered;
    }

    /**
     * @description A follow-up: the branch's copies of these paths (left), unsupported or still pending where so.
     * @param paths paths below the source path
     * @return one file per path
     */
    public List<RlyCompareFiles.FileDiff> readPaths(List<String> paths) {
        List<RlyCompareFiles.FileDiff> out = new List<RlyCompareFiles.FileDiff>();
        for (String p : paths) {
            if (String.isBlank(p) || p.contains('..') || p.startsWith('/')) {
                throw new RlyReleaseException('"' + p + '" isn\'t a file path below the source path.');
            }
        }
        for (String p : paths) {
            RlyCompareFiles.FileDiff f = new RlyCompareFiles.FileDiff();
            f.path = p;
            fetch(f);
            out.add(f);
        }
        return out;
    }

    // Reads the branch's copy into left; false when it's left pending (budget) or unsupported (too large).
    private Boolean fetch(RlyCompareFiles.FileDiff f) {
        if (Limits.getCallouts() >= RlyCompareRun.callBudget || chars >= RlyCompareRun.TEXT_BUDGET) {
            f.status = RlyCompareFiles.PENDING;
            more = true;
            return false;
        }
        String text = git.getFileRaw(prefix() + f.path, branch);
        if (text != null && text.length() > RlyCompareFiles.MAX_FILE_CHARS) {
            f.status = RlyCompareFiles.UNSUPPORTED;
            f.reason = RlyCompareParts.tooLarge(text, 'on the ' + branch + ' branch');
            f.right = null;
            return false;
        }
        f.left = text;
        chars += text == null ? 0 : text.length();
        return true;
    }

    private String prefix() {
        return String.isBlank(sourcePath) ? '' : sourcePath + '/';
    }
}
