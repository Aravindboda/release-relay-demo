/**
 * Git provider for the Release Relay hub: GitHub, GitLab, Bitbucket Cloud or Azure DevOps,
 * called through the Named Credential on the hub's Git connection (the token never leaves it).
 *
 * Each provider is a small subclass with its endpoints; this class holds the shared HTTP,
 * error advice and the factory. New operations are added here as the hub grows.
 */
public abstract with sharing class RlyGit {

    public class GitException extends Exception {}

    public static final String GITHUB = 'GitHub';
    public static final String GITLAB = 'GitLab';
    public static final String BITBUCKET = 'Bitbucket';
    public static final String AZURE = 'AzureDevOps';
    public static final Set<String> PROVIDERS = new Set<String>{ GITHUB, GITLAB, BITBUCKET, AZURE };

    private static final Integer TIMEOUT_MS = 30000;

    protected RLY_Git_Connection__c conn;
    protected String base;

    public static RlyGit forConnection(RLY_Git_Connection__c c) {
        RlyGit git;
        if (c.Provider__c == GITHUB) {
            git = new RlyGitHub();
        } else if (c.Provider__c == GITLAB) {
            git = new RlyGitLab();
        } else if (c.Provider__c == BITBUCKET) {
            git = new RlyBitbucket();
        } else if (c.Provider__c == AZURE) {
            git = new RlyAzureRepos();
        } else {
            throw new GitException('Pick a Git provider: GitHub, GitLab, Bitbucket or Azure DevOps.');
        }
        git.conn = c;
        git.base = 'callout:' + c.Named_Credential__c.trim();
        if (!git.repositoryPattern().matcher(String.isBlank(c.Repository__c) ? '' : c.Repository__c.trim()).matches()) {
            throw new GitException('Repository must look like ' + git.repositoryHint() + '.');
        }
        git.init();
        return git;
    }

    // ---------- what each provider supplies ----------

    public abstract Pattern repositoryPattern();
    public abstract String repositoryHint();
    protected virtual void init() {}

    /** The repository's default branch. Throws when the repository can't be reached. */
    public abstract String defaultBranch();
    public abstract Boolean branchExists(String branch);
    public abstract Boolean fileExists(String path, String ref);
    /** Creates a branch at another branch's latest commit. */
    public abstract void createBranch(String branch, String fromRef);
    /** Files the pipeline needs in the repository, to check they're there. Empty when it can't be checked by path. */
    public abstract List<String> pipelineFiles();
    /** Checks the pipeline exists when it isn't a file (Azure DevOps). */
    public virtual void checkPipeline() {}

    // ---------- releases (GitHub today; the other providers follow) ----------

    public class Run {
        public String id;
        public String url;
        public String status;      // queued, in_progress, completed
        public String conclusion;  // success, failure, cancelled... (when completed)
        public Boolean completed() { return status == 'completed'; }
        public Boolean failed() { return completed() && conclusion != 'success'; }
    }

    public class PullRequest {
        public Integer prNumber;
        public String url;
        public String state;       // open, merged, closed
    }

    /** Creates or replaces a file on a branch; content is base64. */
    public virtual void putFile(String path, String branch, String base64Content, String message) { throw unsupported('Committing files'); }
    /** A file's raw content, or null when it isn't there. */
    public virtual String getFileRaw(String path, String ref) { throw unsupported('Reading files'); }
    /** Starts the pipeline with these inputs. */
    public virtual void startPipeline(Map<String, String> inputs) { throw unsupported('Starting the pipeline'); }
    /** The newest pipeline run with this title, or null. */
    public virtual Run findRun(String title) { throw unsupported('Reading pipeline runs'); }
    /** The newest pull request from branch into target, or null. */
    public virtual PullRequest findPullRequest(String branch, String target) { throw unsupported('Reading pull requests'); }

    /** Closes a pull request with a comment (rejected releases). */
    public virtual void closePullRequest(Integer prNumber, String comment) { throw unsupported('Closing pull requests'); }

    protected GitException unsupported(String what) {
        return new GitException(what + ' isn\'t available for ' + conn.Provider__c + ' in the hub yet. Use GitHub for now.');
    }

    // ---------- shared HTTP ----------

    protected HttpResponse send(String method, String path, String body) {
        return send(method, path, body, null);
    }

    protected HttpResponse send(String method, String path, String body, Map<String, String> overrides) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(base + path);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('User-Agent', 'Release-Relay-Salesforce');
        req.setHeader('Accept', 'application/json');
        Map<String, String> extra = headers();
        if (overrides != null) {
            extra.putAll(overrides);
        }
        for (String h : extra.keySet()) {
            req.setHeader(h, extra.get(h));
        }
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        try {
            return new Http().send(req);
        } catch (CalloutException e) {
            throw new GitException(explainCallout(e.getMessage()));
        }
    }

    protected virtual Map<String, String> headers() {
        return new Map<String, String>();
    }

    protected Object parse(HttpResponse res) {
        return JSON.deserializeUntyped(res.getBody());
    }

    protected void assertOk(HttpResponse res, String action) {
        Integer code = res.getStatusCode();
        if (code >= 200 && code < 300) {
            return;
        }
        String advice = code == 401 ? 'The token in Named Credential ' + conn.Named_Credential__c + ' was refused: check or renew it.'
            : code == 403 ? 'The token lacks permission for this (or the provider rate-limited the request).'
            : code == 404 ? 'Not found: check the repository name and that the token can see it.'
            : (code == 400 || code == 422) ? 'The provider rejected the request.'
            : '';
        throw new GitException((action + ' failed with HTTP ' + code + '. ' + advice + ' ' + String.valueOf(res.getBody()).left(300)).trim());
    }

    private String explainCallout(String raw) {
        String m = raw == null ? '' : raw;
        if (m.containsIgnoreCase('named credential') || m.containsIgnoreCase('callout:') || m.containsIgnoreCase('credential')) {
            return 'Named Credential ' + conn.Named_Credential__c + ' wasn\'t found or you can\'t use it. Check it exists, and that your '
                + 'permission set has its principal under External Credential Principal Access. (' + m.left(300) + ')';
        }
        return 'Couldn\'t reach ' + conn.Provider__c + ': ' + m.left(300);
    }

    public static String enc(String value) {
        return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8').replace('+', '%20');
    }

    /** Encodes each path segment, keeping the slashes. */
    public static String encPath(String path) {
        List<String> parts = new List<String>();
        for (String p : (path == null ? '' : path).split('/')) {
            parts.add(enc(p));
        }
        return String.join(parts, '/');
    }
}
