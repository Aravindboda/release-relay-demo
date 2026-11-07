/**
 * @description Reads one GitHub tree at a time for Find deleted components in parts (RlyDeletionPlan): a branch's or a
 * folder's own entries (own), or every file below a folder (below), each by a branch name or a tree's sha, through the
 * Git connection's Named Credential like RlyGitHub. The answer is scanned (RlyGitTree), never parsed as a document.
 * Build 45: GitLab too, through RlyGitLabTree (folders by path, so a folder's sha there is a folder reference,
 * branch:path; isTreeRef accepts both). Bitbucket and Azure DevOps can't list files from the hub yet.
 */
public with sharing class RlyGitTreeReader {

    private static final Integer TIMEOUT_MS = 30000;

    private RLY_Git_Connection__c conn;
    private RlyGit gitLab;

    /**
     * @description A reader on a Git connection (connected, GitHub or GitLab).
     * @param conn the connection
     */
    public RlyGitTreeReader(RLY_Git_Connection__c conn) {
        if (conn.Provider__c == 'GitLab') {
            gitLab = RlyGit.forConnection(conn);
        } else if (conn.Provider__c != 'GitHub') {
            throw new RlyGit.GitException('Listing files isn\'t available for ' + conn.Provider__c + ' in the hub yet. Use GitHub or GitLab for now.');
        }
        this.conn = conn;
    }

    /**
     * @description Whether a folder's sha from the page can be read: a tree's sha (GitHub) or a folder reference (GitLab).
     * @param value the value
     * @return true when it can
     */
    public static Boolean isTreeRef(String value) {
        return RlyGitLabTree.isTreeRef(value);
    }

    /**
     * @description A tree's own entries (its files and folders, not below them).
     * @param treeIsh a branch or a tree's sha
     * @return the tree
     */
    public RlyGitTree.Tree own(String treeIsh) {
        return fetch(treeIsh, '');
    }

    /**
     * @description Every file and folder below a tree.
     * @param treeIsh a branch or a tree's sha
     * @return the tree
     */
    public RlyGitTree.Tree below(String treeIsh) {
        return fetch(treeIsh, '?recursive=1');
    }

    private RlyGitTree.Tree fetch(String treeIsh, String query) {
        if (gitLab != null) {
            RlyGitLabTree folder = new RlyGitLabTree(gitLab, treeIsh);
            return query == '' ? folder.own() : folder.below();
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + conn.Named_Credential__c.trim() + '/repos/' + conn.Repository__c.trim() + '/git/trees/'
            + RlyGitRequest.encodePath(treeIsh) + query);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('User-Agent', 'Release-Relay-Salesforce');
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('X-GitHub-Api-Version', '2022-11-28');
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new RlyGit.GitException(RlyGitAdvice.forCallout(e.getMessage(), conn));
        }
        RlyGitAdvice.requireSuccess(res, 'Listing the files on ' + treeIsh, conn);
        return RlyGitTree.read(res.getBody());
    }
}
