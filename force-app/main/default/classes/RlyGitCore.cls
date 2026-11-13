/**
 * @description The repository side of a Git provider (build 45: RlyGit's base, so each class keeps a short public
 * surface): the repository checks every provider supplies, the names and web links the pages show, and the shared HTTP
 * call through the connection's Named Credential (the token never leaves it). RlyGit adds the factory and the release
 * operations; callers keep using RlyGit.
 */
public abstract with sharing class RlyGitCore {

    private static final Integer TIMEOUT_MS = 30000;
    private static final Integer CONFLICT_ATTEMPTS = 3;
    private static final String MOVED_TEXT = 'reference does not point to expected object';
    /** @description Where each provider's repositories are on the web (Azure DevOps builds its own address). */
    private static final Map<String, String> WEB_HOSTS = new Map<String, String>{
        'GitHub' => 'https://github.com/', 'GitLab' => 'https://gitlab.com/', 'Bitbucket' => 'https://bitbucket.org/'
    };
    /** @description What comes between a repository's web address and a branch name, where it isn't /tree/. */
    private static final Map<String, String> BRANCH_FOLDERS = new Map<String, String>{ 'GitLab' => '/-/tree/', 'Bitbucket' => '/src/' };

    protected RLY_Git_Connection__c conn;
    protected String base;

    // ---------- what each provider supplies ----------

    /**
     * @description The shape a repository name must have.
     * @return the pattern
     */
    protected abstract Pattern repositoryPattern();

    /**
     * @description The shape a repository name must have, in words.
     * @return for example owner/repository
     */
    public abstract String repositoryHint();

    /**
     * @description The repository's default branch. Throws when the repository can't be reached.
     * @return the branch name
     */
    public abstract String defaultBranch();

    /**
     * @description The provider's name as people know it (the "In <provider>" approval option, Approved_Via__c).
     * @return for example GitHub
     */
    public abstract String providerLabel();

    /**
     * @description The latest commit on a branch.
     * @param branch the branch name
     * @return the commit SHA, or null when the branch isn't there
     */
    public abstract String branchHead(String branch);

    /**
     * @description Whether a branch exists.
     * @param branch the branch name
     * @return true when it exists
     */
    public abstract Boolean branchExists(String branch);

    /**
     * @description Whether a file exists on a branch.
     * @param path path in the repository
     * @param ref the branch
     * @return true when it exists
     */
    public abstract Boolean fileExists(String path, String ref);

    /**
     * @description Creates a branch at another branch's latest commit.
     * @param branch the new branch
     * @param fromRef the branch to start from
     */
    public abstract void createBranch(String branch, String fromRef);

    /**
     * @description Files the pipeline needs in the repository, to check they're there.
     * @return the paths
     */
    public abstract List<String> pipelineFiles();

    /**
     * @description Checks the pipeline exists when it isn't a file (Azure DevOps). Where the pipeline is a file,
     * pipelineFiles() covers it, so there is nothing more to check.
     */
    public virtual void checkPipeline() {
        return;
    }

    // ---------- names and links (build 45: several Git connections) ----------

    /**
     * @description What the provider calls a request to merge a branch, for the pages.
     * @return Pull request (GitLab: Merge request)
     */
    public virtual String changeRequestLabel() {
        return 'Pull request';
    }

    /**
     * @description The repository's web address, for links on the pages.
     * @return for example https://github.com/owner/repo, or null when the provider has none
     */
    public virtual String webUrl() {
        String host = WEB_HOSTS.get(conn.Provider__c);
        return host == null ? null : host + conn.Repository__c.trim();
    }

    /**
     * @description A branch's web address in the repository (/tree/ on GitHub, /-/tree/ on GitLab, /src/ on Bitbucket).
     * @param branch the branch name
     * @return the link, the repository's when the branch is blank, or null when the provider has no web address
     */
    public virtual String branchUrl(String branch) {
        String web = webUrl();
        if (web == null || String.isBlank(branch)) {
            return web;
        }
        String folder = BRANCH_FOLDERS.get(conn.Provider__c);
        return web + (folder == null ? '/tree/' : folder) + encPath(branch.trim());
    }

    // ---------- shared HTTP ----------

    /**
     * @description The Git connection this provider calls.
     * @return the connection
     */
    public RLY_Git_Connection__c connection() {
        return conn;
    }

    /**
     * @description Sends one request through the connection's Named Credential, for the provider's helper classes
     * (RlyGitLabTree, RlyGitLabRuns, RlyGitChanges); the answer is returned whatever its status.
     * @param r the request
     * @return the answer
     */
    public HttpResponse request(RlyGitRequest r) {
        return send(r);
    }

    /**
     * @description Throws a GitException with advice unless the answer is a 2xx (RlyGitAdvice).
     * @param res the answer
     * @param action what was being done, for the message
     */
    public void requireOk(HttpResponse res, String action) {
        RlyGitAdvice.requireSuccess(res, action, conn);
    }

    protected HttpResponse send(String method, String path, String body) {
        return send(new RlyGitRequest(method, path, body));
    }

    // A 409 answer when another commit moved the branch meanwhile (parts are sent side by side): the same call is sent
    // again, at most three times in all (build 53). GitLab says it with a 400 (build 61, D46).
    protected HttpResponse sendRetryingConflicts(String method, String path, String body) {
        HttpResponse res = send(method, path, body);
        for (Integer attempt = 1; attempt < CONFLICT_ATTEMPTS && branchMoved(res); attempt++) {
            res = send(method, path, body);
        }
        return res;
    }

    /**
     * @description Whether an answer says the branch moved under the commit: HTTP 409, or GitLab's 400 "reference does
     * not point to expected object" (build 61, D46).
     * @param res the answer
     * @return true when sending the same commit again can work
     */
    public static Boolean branchMoved(HttpResponse res) {
        return res != null && (res.getStatusCode() == 409 || (res.getStatusCode() == 400
            && String.valueOf(res.getBody()).containsIgnoreCase(MOVED_TEXT)));
    }

    protected HttpResponse send(RlyGitRequest r) {
        HttpRequest req = new HttpRequest();
        req.setMethod(r.method);
        req.setEndpoint(base + r.path);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('User-Agent', 'Release-Relay-Salesforce');
        req.setHeader('Accept', 'application/json');
        Map<String, String> extra = headers();
        extra.putAll(r.headers);
        for (String h : extra.keySet()) {
            req.setHeader(h, extra.get(h));
        }
        if (r.body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(r.body);
        }
        try {
            return new Http().send(req);
        } catch (CalloutException e) {
            throw new RlyGit.GitException(RlyGitAdvice.forCallout(e.getMessage(), conn));
        }
    }

    protected virtual Map<String, String> headers() {
        return new Map<String, String>();
    }

    protected Object parse(HttpResponse res) {
        return JSON.deserializeUntyped(res.getBody());
    }

    protected void assertOk(HttpResponse res, String action) {
        RlyGitAdvice.requireSuccess(res, action, conn);
    }

    /**
     * @description URL-encodes a value (spaces as %20).
     * @param value the value
     * @return the encoded value
     */
    protected String enc(String value) {
        return RlyGitRequest.encode(value);
    }

    /**
     * @description Encodes each path segment, keeping the slashes.
     * @param path the path
     * @return the encoded path
     */
    protected String encPath(String path) {
        return RlyGitRequest.encodePath(path);
    }
}
