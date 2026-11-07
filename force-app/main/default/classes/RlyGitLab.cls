/**
 * @description GitLab REST API v4, through the Named Credential (RLY_GitLab: URL https://gitlab.com/api/v4, or your own
 * GitLab's /api/v4), which sends the token as Authorization: Bearer. Token: a project access token (Maintainer, api and
 * write_repository). Build 45: every release operation, like RlyGitHub. Merge requests stand for pull requests (iid is
 * the number), pipelines for runs (their name comes from the CI file's workflow:name, version 25), and the hub's inputs
 * go to the pipeline as variables named in upper case (REQUEST_ID, MODE, ...). Finding runs lives in RlyGitLabRuns,
 * folder lists in RlyGitLabTree, and the Changes card's merge request files in RlyGitLabChanges and RlyGitLabDiffs.
 */
public with sharing class RlyGitLab extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$');
    private static final String MERGE_REQUESTS = '/merge_requests';

    /**
     * @description The shape of a GitLab project path.
     * @return group/project, with optional subgroups
     */
    protected override Pattern repositoryPattern() {
        return REPO;
    }

    /**
     * @description The shape of a GitLab project path, in words.
     * @return group/project
     */
    public override String repositoryHint() {
        return 'group/project';
    }

    /**
     * @description The provider's name as people know it.
     * @return GitLab
     */
    public override String providerLabel() {
        return 'GitLab';
    }

    /**
     * @description GitLab's word for a pull request.
     * @return Merge request
     */
    public override String changeRequestLabel() {
        return 'Merge request';
    }

    /**
     * @description The latest commit on a branch (GET /repository/branches/:branch, commit.id).
     * @param branch the branch name
     * @return the commit SHA, or null when the branch isn't there
     */
    public override String branchHead(String branch) {
        HttpResponse res = send('GET', p('/repository/branches/' + enc(branch)), null);
        if (res.getStatusCode() == 404) {
            return null;
        }
        assertOk(res, 'Branch lookup');
        Object commitInfo = ((Map<String, Object>) parse(res)).get('commit');
        return commitInfo == null ? null : String.valueOf(((Map<String, Object>) commitInfo).get('id'));
    }

    private String p(String path) {
        return RlyGitLabRuns.project(this, path);
    }

    /**
     * @description The project's default branch.
     * @return the branch name
     */
    public override String defaultBranch() {
        HttpResponse res = send('GET', p(''), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        return String.valueOf(((Map<String, Object>) parse(res)).get('default_branch'));
    }

    /**
     * @description Whether a branch exists.
     * @param branch the branch name
     * @return true when it exists
     */
    public override Boolean branchExists(String branch) {
        HttpResponse res = send('GET', p('/repository/branches/' + enc(branch)), null);
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
        HttpResponse res = send('GET', p('/repository/files/' + enc(path) + '?ref=' + enc(ref)), null);
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
        HttpResponse res = send('POST', p('/repository/branches?branch=' + enc(branch) + '&ref=' + enc(fromRef)), null);
        assertOk(res, 'Creating branch ' + branch);
    }

    /**
     * @description Creates or replaces a file on a branch in one commit (POST /repository/commits, content base64):
     * HEAD /repository/files says whether it's there (update) or not (create), without reading it.
     * @param file the file and its commit
     * @return link to the commit (web_url), or null
     */
    public override String putFile(RlyGitFile file) {
        HttpResponse existing = send('HEAD', p('/repository/files/' + enc(file.path) + '?ref=' + enc(file.branch)), null);
        String action = existing.getStatusCode() == 404 ? 'create' : 'update';
        if (action == 'update') {
            assertOk(existing, 'File lookup');
        }
        Map<String, Object> change = new Map<String, Object>{ 'action' => action, 'file_path' => file.path,
            'content' => file.base64Content, 'encoding' => 'base64' };
        HttpResponse res = send('POST', p('/repository/commits'), JSON.serialize(new Map<String, Object>{
            'branch' => file.branch, 'commit_message' => file.message, 'actions' => new List<Object>{ change } }));
        assertOk(res, 'Committing ' + file.path);
        return RlyGitLabRuns.textOf(res.getBody(), 'web_url');
    }

    /**
     * @description A file's raw content (GET /repository/files/:path/raw).
     * @param path path in the repository
     * @param ref the branch
     * @return the content, or null when it isn't there
     */
    public override String getFileRaw(String path, String ref) {
        HttpResponse res = send('GET', p('/repository/files/' + enc(path) + '/raw?ref=' + enc(ref)), null);
        if (res.getStatusCode() == 404) {
            return null;
        }
        assertOk(res, 'Reading ' + path);
        return res.getBody();
    }

    /**
     * @description The paths of every file on a branch under a path (GET /repository/tree, recursive, a page of 100
     * entries per call: RlyGitLabTree). Refused when the folder is cut short, rather than giving half a list.
     * @param branch the branch
     * @param path the folder, for example force-app/main/default (blank: the whole branch)
     * @return the file paths
     */
    public override List<String> listFiles(String branch, String path) {
        String folder = String.isBlank(path) ? '' : path.trim().removeEnd('/');
        RlyGitTree.Tree t = new RlyGitLabTree(this, RlyGitLabTree.folderRef(branch, folder)).below();
        if (t.truncated) {
            throw new GitException('Listing the files on ' + branch + ' stopped at ' + (RlyGitLabTree.MAX_PAGES * RlyGitLabTree.PER_PAGE).format()
                + ' entries: GitLab lists 100 per call. Set the connection\'s source path to a smaller folder.');
        }
        List<String> out = new List<String>();
        String prefix = folder == '' ? '' : folder + '/';
        for (RlyGitTree.Entry e : t.entries) {
            if (e.type == 'blob') {
                out.add(prefix + e.path);
            }
        }
        return out;
    }

    /**
     * @description Starts a pipeline on the pipeline branch (POST /pipeline), each input a variable named in upper case
     * (request_id becomes REQUEST_ID). Blank inputs are left out: the CI file treats a missing variable as blank.
     * @param inputs the pipeline inputs
     */
    public override void startPipeline(Map<String, String> inputs) {
        List<Object> variables = new List<Object>();
        for (String k : inputs.keySet()) {
            String value = inputs.get(k);
            if (String.isNotBlank(value)) {
                variables.add(new Map<String, Object>{ 'key' => k.toUpperCase(), 'value' => value });
            }
        }
        HttpResponse res = send('POST', p('/pipeline'), JSON.serialize(new Map<String, Object>{
            'ref' => conn.Pipeline_Branch__c.trim(), 'variables' => variables }));
        assertOk(res, 'Starting the pipeline');
    }

    /**
     * @description The newest pipeline with this name among the recent API-started pipelines on the pipeline branch
     * (RlyGitLabRuns.find: the name from workflow:name, matched with RlyRunTitles).
     * @param title the run title
     * @return the run, or null
     */
    public override Run findRun(String title) {
        return RlyGitLabRuns.find(this, title);
    }

    /**
     * @description The newest merge request from branch into target, in any state.
     * @param branch the source branch
     * @param target the target branch
     * @return the merge request (iid, web_url, state open, merged or closed), or null
     */
    public override PullRequest findPullRequest(String branch, String target) {
        HttpResponse res = send('GET', p(MERGE_REQUESTS + '?state=all&order_by=created_at&sort=desc&per_page=5&source_branch='
            + enc(branch) + '&target_branch=' + enc(target)), null);
        assertOk(res, 'Reading merge requests');
        List<Object> found = (List<Object>) parse(res);
        if (found.isEmpty()) {
            return null;
        }
        Map<String, Object> m = (Map<String, Object>) found[0];
        PullRequest pr = new PullRequest();
        pr.prNumber = Integer.valueOf(m.get('iid'));
        pr.url = RlyGitLabRuns.text(m.get('web_url'));
        pr.state = RlyGitLabRuns.mergeRequestState(RlyGitLabRuns.text(m.get('state')));
        return pr;
    }

    /**
     * @description Leaves a comment on a merge request (POST /merge_requests/:iid/notes).
     * @param prNumber the merge request iid
     * @param comment the comment
     */
    public override void commentOnPullRequest(Integer prNumber, String comment) {
        assertOk(send('POST', p(MERGE_REQUESTS + '/' + prNumber + '/notes'), JSON.serialize(new Map<String, Object>{ 'body' => comment })),
            'Commenting on merge request !' + prNumber);
    }

    /**
     * @description Closes a merge request without merging it (PUT state_event close).
     * @param prNumber the merge request iid
     */
    public override void closePullRequest(Integer prNumber) {
        assertOk(send('PUT', p(MERGE_REQUESTS + '/' + prNumber), JSON.serialize(new Map<String, Object>{ 'state_event' => 'close' })),
            'Closing merge request !' + prNumber);
    }

    /**
     * @description Opens a merge request from one branch into another.
     * @param head the branch with the changes
     * @param baseBranch the branch to merge into
     * @param message the title, then (after a line break) the description
     * @return the merge request's link
     */
    public override String openPullRequest(String head, String baseBranch, String message) {
        String text = message == null ? '' : message;
        HttpResponse res = send('POST', p(MERGE_REQUESTS), JSON.serialize(new Map<String, Object>{
            'source_branch' => head, 'target_branch' => baseBranch, 'title' => text.substringBefore('\n').trim(),
            'description' => text.substringAfter('\n').trim() }));
        assertOk(res, 'Opening a merge request into ' + baseBranch);
        return RlyGitLabRuns.text(((Map<String, Object>) parse(res)).get('web_url'));
    }

    /**
     * @description The CI file and the pipeline script.
     * @return the paths
     */
    public override List<String> pipelineFiles() {
        return new List<String>{ String.isBlank(conn.Pipeline__c) ? '.gitlab-ci.yml' : conn.Pipeline__c.trim(), 'scripts/release-relay.js' };
    }
}
