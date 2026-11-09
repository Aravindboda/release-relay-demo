/**
 * @description Git provider for the Release Relay hub: GitHub, GitLab, Bitbucket Cloud or Azure DevOps,
 * called through the Named Credential on the hub's Git connection (the token never leaves it).
 *
 * Each provider is a small subclass with its endpoints; this class holds the factory and the release operations'
 * defaults, and RlyGitCore (its base, build 45) the repository checks, the names and links, and the shared HTTP call.
 * Error advice lives in RlyGitAdvice.
 */
public abstract with sharing class RlyGit extends RlyGitCore {

    private static final String GITHUB = 'GitHub';
    private static final String GITLAB = 'GitLab';
    /** @description Provider value for Bitbucket Cloud. */
    public static final String BITBUCKET = 'Bitbucket';
    private static final String AZURE = 'AzureDevOps';
    /** @description Every supported provider. */
    public static final Set<String> PROVIDERS = new Set<String>{ GITHUB, GITLAB, BITBUCKET, AZURE };

    private static final Map<String, String> IMPLEMENTATIONS = new Map<String, String>{
        GITHUB => 'RlyGitHub', GITLAB => 'RlyGitLab', BITBUCKET => 'RlyBitbucket', AZURE => 'RlyAzureRepos'
    };

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
        /** @description When the provider created the run, or null (build 56, D24). */
        public Datetime createdAt;

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

    // ---------- releases (GitHub and GitLab; the other providers follow) ----------

    /**
     * @description Creates or replaces a file on a branch.
     * @param file the file and its commit
     * @return link to the commit, or null when the provider gives none
     */
    public virtual String putFile(RlyGitFile file) {
        return (String) failUnsupported('Committing files');
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
     * @description The paths of every file on a branch under a path (the deletion candidates of a developer org).
     * @param branch the branch
     * @param path the folder, for example force-app/main/default (blank: the whole branch)
     * @return the file paths
     */
    public virtual List<String> listFiles(String branch, String path) {
        return (List<String>) failUnsupported('Listing files');
    }

    /**
     * @description Starts the pipeline with these inputs, signed with the run-signing key when the hub has one
     * (RlyRunSigning, build 48): every run the hub starts goes through here.
     * @param inputs the pipeline inputs
     */
    public void startPipeline(Map<String, String> inputs) {
        dispatchPipeline(RlyRunSigning.sign(inputs));
    }

    /**
     * @description The provider's call that starts the pipeline with inputs already signed (only startPipeline calls it).
     * @param inputs the pipeline inputs, as sent
     */
    protected virtual void dispatchPipeline(Map<String, String> inputs) {
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

    /**
     * @description Opens a pull request from one branch into another.
     * @param head the branch with the changes
     * @param baseBranch the branch to merge into
     * @param message the title, then (after a line break) the description, like a commit message
     * @return the pull request's link
     */
    public virtual String openPullRequest(String head, String baseBranch, String message) {
        return (String) failUnsupported('Opening pull requests');
    }

    protected GitException unsupported(String what) {
        return new GitException(what + ' isn\'t available for ' + conn.Provider__c + ' in the hub yet. Use GitHub or GitLab for now.');
    }

    // Always throws: the default of the release operations a provider doesn't support yet.
    private Object failUnsupported(String what) {
        throw unsupported(what);
    }
}
