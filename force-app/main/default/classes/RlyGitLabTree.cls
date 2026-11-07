/**
 * @description One folder of a GitLab branch as a Git tree (RlyGitTree), read from GET /repository/tree a page of 100
 * entries at a time (build 45), for RlyGitTreeReader and RlyGitLab.listFiles. GitLab reads a folder by its path and a
 * branch, not by a tree's sha, so a folder's sha here is a folder reference, branch:path (a branch name never holds a
 * colon), which a new RlyGitLabTree reads back. A missing folder or branch is an empty tree; a folder longer than
 * MAX_PAGES pages (or the call's callouts) is cut short and says so (truncated).
 */
public with sharing class RlyGitLabTree {

    /** @description Entries per page (GitLab's most). */
    public static final Integer PER_PAGE = 100;
    /** @description Most pages one folder read takes (5,000 entries). */
    public static final Integer MAX_PAGES = 50;
    private static final String SEP = ':';
    private static final Pattern SHA_PATTERN = Pattern.compile('^[0-9a-f]{40}$');
    private static final Pattern FOLDER_REF_PATTERN = Pattern.compile('^[A-Za-z0-9._/-]{1,100}:[^\\r\\n]{1,400}$');

    private RlyGit git;
    private String ref;
    private String folder;

    /**
     * @description A folder to read.
     * @param git the GitLab provider
     * @param treeIsh a branch (its root), or a folder reference branch:path
     */
    public RlyGitLabTree(RlyGit git, String treeIsh) {
        this.git = git;
        this.ref = refOf(treeIsh);
        this.folder = pathOf(treeIsh);
    }

    /**
     * @description The folder's own entries (its files and folders, not below them).
     * @return the tree: paths relative to the folder
     */
    public RlyGitTree.Tree own() {
        return read('');
    }

    /**
     * @description Every file and folder below the folder.
     * @return the tree: paths relative to the folder
     */
    public RlyGitTree.Tree below() {
        return read('&recursive=true');
    }

    private RlyGitTree.Tree read(String recursive) {
        RlyGitTree.Tree t = new RlyGitTree.Tree();
        String query = RlyGitLabRuns.project(git, '/repository/tree?ref=' + RlyGitRequest.encode(ref)
            + (folder == '' ? '' : '&path=' + RlyGitRequest.encode(folder)) + recursive + '&per_page=' + PER_PAGE + '&page=');
        for (Integer pageNo = 1; pageNo <= MAX_PAGES; pageNo++) {
            HttpResponse res = git.request(new RlyGitRequest('GET', query + pageNo, null));
            if (res.getStatusCode() == 404) {
                return t;
            }
            git.requireOk(res, 'Listing the files on ' + ref);
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(res.getBody());
            addEntries(t, rows);
            if (isLastPage(rows.size(), res.getHeader('X-Next-Page'))) {
                return t;
            }
            if (Limits.getCallouts() >= Limits.getLimitCallouts() - 1) {
                break;
            }
        }
        t.truncated = true;
        return t;
    }

    // One page's entries: paths relative to the folder read, folders' sha as references.
    private void addEntries(RlyGitTree.Tree t, List<Object> rows) {
        String prefix = folder == '' ? '' : folder + '/';
        for (Object o : rows) {
            Map<String, Object> row = (Map<String, Object>) o;
            String fullPath = RlyGitLabRuns.text(row.get('path'));
            if (fullPath == null) {
                continue;
            }
            RlyGitTree.Entry e = new RlyGitTree.Entry();
            e.type = RlyGitLabRuns.text(row.get('type'));
            e.path = fullPath.removeStart(prefix);
            e.sha = e.type == 'tree' ? folderRef(ref, fullPath) : RlyGitLabRuns.text(row.get('id'));
            t.entries.add(e);
        }
    }

    /**
     * @description A folder's reference: the branch and its path (the branch alone for the root).
     * @param branch the branch
     * @param path the folder's path from the repository's root (blank: the root)
     * @return branch:path, or the branch
     */
    public static String folderRef(String branch, String path) {
        return String.isBlank(path) ? branch : branch + SEP + path;
    }

    /**
     * @description The branch of a branch name or a folder reference.
     * @param treeIsh a branch, or branch:path
     * @return the branch
     */
    public static String refOf(String treeIsh) {
        String t = treeIsh == null ? '' : treeIsh.trim();
        return t.contains(SEP) ? t.substringBefore(SEP) : t;
    }

    /**
     * @description The folder of a branch name (the root: blank) or a folder reference.
     * @param treeIsh a branch, or branch:path
     * @return the folder's path, without a trailing slash
     */
    public static String pathOf(String treeIsh) {
        String t = treeIsh == null ? '' : treeIsh.trim();
        return t.contains(SEP) ? t.substringAfter(SEP).removeEnd('/') : '';
    }

    /**
     * @description Whether a value can name a folder to read: a tree's sha (GitHub) or a folder reference (GitLab)
     * whose branch and path stay inside the repository.
     * @param value the value from the page
     * @return true when it can
     */
    public static Boolean isTreeRef(String value) {
        if (value == null) {
            return false;
        }
        return SHA_PATTERN.matcher(value).matches()
            || (FOLDER_REF_PATTERN.matcher(value).matches() && !value.contains('..') && !pathOf(value).startsWith('/'));
    }

    /**
     * @description Whether a page was the last: GitLab says so with an empty X-Next-Page header; without the header,
     * a page shorter than PER_PAGE is the last.
     * @param rows entries on the page
     * @param nextPage the X-Next-Page header, or null
     * @return true when there's no next page
     */
    public static Boolean isLastPage(Integer rows, String nextPage) {
        if (nextPage != null) {
            return String.isBlank(nextPage);
        }
        return rows < PER_PAGE;
    }
}
