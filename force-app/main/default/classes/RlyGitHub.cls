/**
 * @description GitHub REST API, through the Named Credential (URL https://api.github.com).
 * Token: fine-grained, on this repository, with Contents and Pull requests: Read and write,
 * Actions: Read and write, and Workflows: Read and write (to update the workflow file).
 */
public with sharing class RlyGitHub extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

    /**
     * @description The shape of a GitHub repository name.
     * @return owner/repository
     */
    public override Pattern repositoryPattern() {
        return REPO;
    }

    /**
     * @description The shape of a GitHub repository name, in words.
     * @return owner/repository
     */
    public override String repositoryHint() {
        return 'owner/repository';
    }

    protected override Map<String, String> headers() {
        return new Map<String, String>{ 'Accept' => 'application/vnd.github+json', 'X-GitHub-Api-Version' => '2022-11-28' };
    }

    private String repo() {
        return '/repos/' + conn.Repository__c.trim();
    }

    /**
     * @description The repository's default branch.
     * @return the branch name
     */
    public override String defaultBranch() {
        HttpResponse res = send('GET', repo(), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        return String.valueOf(((Map<String, Object>) parse(res)).get('default_branch'));
    }

    /**
     * @description Whether a branch exists.
     * @param branch the branch name
     * @return true when it exists
     */
    public override Boolean branchExists(String branch) {
        HttpResponse res = send('GET', repo() + '/branches/' + enc(branch), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'Branch lookup');
        return true;
    }

    /**
     * @description Whether a file exists on a branch.
     * @param path path in the repository
     * @param ref the branch
     * @return true when it exists
     */
    public override Boolean fileExists(String path, String ref) {
        HttpResponse res = send('GET', repo() + '/contents/' + encPath(path) + '?ref=' + enc(ref), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'File lookup');
        return true;
    }

    /**
     * @description Creates a branch at another branch's latest commit.
     * @param branch the new branch
     * @param fromRef the branch to start from
     */
    public override void createBranch(String branch, String fromRef) {
        HttpResponse ref = send('GET', repo() + '/git/ref/heads/' + encPath(fromRef), null);
        if (ref.getStatusCode() == 404) {
            throw new GitException('Branch ' + fromRef + ' wasn\'t found in ' + conn.Repository__c + '.');
        }
        assertOk(ref, 'Branch lookup');
        String sha = String.valueOf(((Map<String, Object>) ((Map<String, Object>) parse(ref)).get('object')).get('sha'));
        HttpResponse res = send('POST', repo() + '/git/refs',
            JSON.serialize(new Map<String, Object>{ 'ref' => 'refs/heads/' + branch, 'sha' => sha }));
        assertOk(res, 'Creating branch ' + branch);
    }

    /**
     * @description Creates or replaces a file on a branch (the current sha is sent when the file exists).
     * @param file the file and its commit
     */
    public override void putFile(RlyGitFile file) {
        String url = repo() + '/contents/' + encPath(file.path);
        Map<String, Object> body = new Map<String, Object>{ 'message' => file.message, 'content' => file.base64Content, 'branch' => file.branch };
        HttpResponse existing = send('GET', url + '?ref=' + enc(file.branch), null);
        if (existing.getStatusCode() == 200) {
            body.put('sha', ((Map<String, Object>) parse(existing)).get('sha'));
        }
        assertOk(send('PUT', url, JSON.serialize(body)), 'Committing ' + file.path);
    }

    /**
     * @description A file's raw content.
     * @param path path in the repository
     * @param ref the branch
     * @return the content, or null when it isn't there
     */
    public override String getFileRaw(String path, String ref) {
        HttpResponse res = send(new RlyGitRequest('GET', repo() + '/contents/' + encPath(path) + '?ref=' + enc(ref), null)
            .withHeader('Accept', 'application/vnd.github.raw'));
        if (res.getStatusCode() == 404) {
            return null;
        }
        assertOk(res, 'Reading ' + path);
        return res.getBody();
    }

    /**
     * @description Starts the workflow (workflow_dispatch) with these inputs.
     * @param inputs the workflow inputs
     */
    public override void startPipeline(Map<String, String> inputs) {
        HttpResponse res = send('POST', repo() + '/actions/workflows/' + enc(conn.Pipeline__c.trim()) + '/dispatches',
            JSON.serialize(new Map<String, Object>{ 'ref' => conn.Pipeline_Branch__c.trim(), 'inputs' => inputs }));
        assertOk(res, 'Starting the pipeline');
    }

    /**
     * @description The newest workflow run with this title.
     * @param title the run title
     * @return the run, or null
     */
    public override Run findRun(String title) {
        HttpResponse res = send('GET', repo() + '/actions/workflows/' + enc(conn.Pipeline__c.trim())
            + '/runs?event=workflow_dispatch&per_page=50', null);
        assertOk(res, 'Reading pipeline runs');
        Object runs = ((Map<String, Object>) parse(res)).get('workflow_runs');
        for (Object o : runs == null ? new List<Object>() : (List<Object>) runs) {
            Map<String, Object> r = (Map<String, Object>) o;
            if (String.valueOf(r.get('display_title')) == title) {
                return toRun(r); // newest first
            }
        }
        return null;
    }

    private Run toRun(Map<String, Object> r) {
        Run run = new Run();
        run.id = String.valueOf(r.get('id'));
        run.url = String.valueOf(r.get('html_url'));
        run.status = String.valueOf(r.get('status'));
        run.conclusion = r.get('conclusion') == null ? null : String.valueOf(r.get('conclusion'));
        return run;
    }

    /**
     * @description The newest pull request from branch into target.
     * @param branch the source branch
     * @param target the target branch
     * @return the pull request, or null
     */
    public override PullRequest findPullRequest(String branch, String target) {
        String owner = conn.Repository__c.trim().substringBefore('/');
        HttpResponse res = send('GET', repo() + '/pulls?state=all&per_page=5&head=' + enc(owner + ':' + branch) + '&base=' + enc(target), null);
        assertOk(res, 'Reading pull requests');
        List<Object> prs = (List<Object>) parse(res);
        if (prs.isEmpty()) {
            return null;
        }
        Map<String, Object> p = (Map<String, Object>) prs[0];
        PullRequest pr = new PullRequest();
        pr.prNumber = Integer.valueOf(p.get('number'));
        pr.url = String.valueOf(p.get('html_url'));
        pr.state = p.get('merged_at') != null ? 'merged' : String.valueOf(p.get('state'));
        return pr;
    }

    /**
     * @description Comments on a pull request, then closes it.
     * @param prNumber the pull request number
     * @param comment the comment to leave (none when blank)
     */
    public override void closePullRequest(Integer prNumber, String comment) {
        if (String.isNotBlank(comment)) {
            assertOk(send('POST', repo() + '/issues/' + prNumber + '/comments', JSON.serialize(new Map<String, Object>{ 'body' => comment })),
                'Commenting on pull request #' + prNumber);
        }
        assertOk(send('PATCH', repo() + '/pulls/' + prNumber, JSON.serialize(new Map<String, Object>{ 'state' => 'closed' })),
            'Closing pull request #' + prNumber);
    }

    /**
     * @description The workflow file and the pipeline script.
     * @return the paths
     */
    public override List<String> pipelineFiles() {
        return new List<String>{ '.github/workflows/' + conn.Pipeline__c.trim(), 'scripts/release-relay.js' };
    }
}
