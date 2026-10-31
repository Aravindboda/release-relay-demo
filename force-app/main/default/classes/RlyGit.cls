/**
 * @description Git provider for the Release Relay hub: GitHub, GitLab, Bitbucket Cloud or Azure DevOps,
 * called through the Named Credential on the hub's Git connection (the token never leaves it).
 *
 * Each provider is a small subclass with its endpoints; this class holds the factory, the shared
 * HTTP call and the release operations' defaults. Error advice lives in RlyGitAdvice.
 */
public abstract with sharing class RlyGit {

    private static final String GITHUB = 'GitHub';
    private static final String GITLAB = 'GitLab';
    /** @description Provider value for Bitbucket Cloud. */
    public static final String BITBUCKET = 'Bitbucket';
    private static final String AZURE = 'AzureDevOps';
    /** @description Every supported provider. */
    public static final Set<String> PROVIDERS = new Set<String>{ GITHUB, GITLAB, BITBUCKET, AZURE };

    private static final Integer TIMEOUT_MS = 30000;
    private static final Map<String, String> IMPLEMENTATIONS = new Map<String, String>{
        GITHUB => 'RlyGitHub', GITLAB => 'RlyGitLab', BITBUCKET => 'RlyBitbucket', AZURE => 'RlyAzureRepos'
    };

    protected RLY_Git_Connection__c conn;
    protected String base;

    /** @description A Git call failed, or the connection isn't usable. */
    public class GitException extends Exception {}

    /** @description A pipeline run. */
    public class Run {
        /** @description The provider's run id. */
        public String id;
        /** @description Link to the run. */
        public String url;
        /** @description queued, in_progress or completed. */
        public String status;
        /** @description success, failure, cancelled... (when completed). */
        public String conclusion;

        /**
         * @description Whether the run has ended.
         * @return true when completed
         */
        public Boolean completed() {
            return status == 'completed';
        }

        /**
         * @description Whether the run ended without success.
         * @return true when completed and not successful
         */
        public Boolean failed() {
            return completed() && conclusion != 'success';
        }
    }

    /** @description A pull request. */
    public class PullRequest {
        /** @description Its number. */
        public Integer prNumber;
        /** @description Link to it. */
        public String url;
        /** @description open, merged or closed. */
        public String state;
    }

    /**
     * @description The provider for a Git connection.
     * @param c the Git connection
     * @return the provider, ready to call
     */
    public static RlyGit forConnection(RLY_Git_Connection__c c) {
        String implementation = IMPLEMENTATIONS.get(c.Provider__c);
        if (implementation == null) {
            throw new GitException('Pick a Git provider: GitHub, GitLab, Bitbucket or Azure DevOps.');
        }
        RlyGit git = (RlyGit) Type.forName(implementation).newInstance();
        git.conn = c;
        git.base = 'callout:' + c.Named_Credential__c.trim();
        String repository = String.isBlank(c.Repository__c) ? '' : c.Repository__c.trim();
        if (!git.repositoryPattern().matcher(repository).matches()) {
            throw new GitException('Repository must look like ' + git.repositoryHint() + '.');
        }
        return git;
    }

    // ---------- what each provider supplies ----------

    /**
     * @description The shape a repository name must have.
     * @return the pattern
     */
    public abstract Pattern repositoryPattern();

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

    // ---------- releases (GitHub today; the other providers follow) ----------

    /**
     * @description Creates or replaces a file on a branch.
     * @param file the file and its commit
     */
    public virtual void putFile(RlyGitFile file) {
        failUnsupported('Committing files');
    }

    /**
     * @description A file's raw content.
     * @param path path in the repository
     * @param ref the branch
     * @return the content, or null when it isn't there
     */
    public virtual String getFileRaw(String path, String ref) {
        return (String) failUnsupported('Reading files');
    }

    /**
     * @description Starts the pipeline with these inputs.
     * @param inputs the pipeline inputs
     */
    public virtual void startPipeline(Map<String, String> inputs) {
        failUnsupported('Starting the pipeline');
    }

    /**
     * @description The newest pipeline run with this title.
     * @param title the run title
     * @return the run, or null
     */
    public virtual Run findRun(String title) {
        return (Run) failUnsupported('Reading pipeline runs');
    }

    /**
     * @description The newest pull request from branch into target.
     * @param branch the source branch
     * @param target the target branch
     * @return the pull request, or null
     */
    public virtual PullRequest findPullRequest(String branch, String target) {
        return (PullRequest) failUnsupported('Reading pull requests');
    }

    /**
     * @description Leaves a comment on a pull request (the reason a release was rejected).
     * @param prNumber the pull request number
     * @param comment the comment
     */
    public virtual void commentOnPullRequest(Integer prNumber, String comment) {
        failUnsupported('Commenting on pull requests');
    }

    /**
     * @description Closes a pull request without merging it (rejected releases).
     * @param prNumber the pull request number
     */
    public virtual void closePullRequest(Integer prNumber) {
        failUnsupported('Closing pull requests');
    }

    protected GitException unsupported(String what) {
        return new GitException(what + ' isn\'t available for ' + conn.Provider__c + ' in the hub yet. Use GitHub for now.');
    }

    // Always throws: the default of the release operations a provider doesn't support yet.
    private Object failUnsupported(String what) {
        throw unsupported(what);
    }

    // ---------- shared HTTP ----------

    protected HttpResponse send(String method, String path, String body) {
        return send(new RlyGitRequest(method, path, body));
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
            throw new GitException(RlyGitAdvice.forCallout(e.getMessage(), conn));
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
    public static String encPath(String path) {
        return RlyGitRequest.encodePath(path);
    }
}
