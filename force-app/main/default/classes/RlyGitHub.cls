/**
 * GitHub REST API, through the Named Credential (URL https://api.github.com).
 * Token: fine-grained, on this repository, with Contents and Pull requests: Read and write,
 * Actions: Read and write, and Workflows: Read and write (to update the workflow file).
 */
public with sharing class RlyGitHub extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

    public override Pattern repositoryPattern() { return REPO; }
    public override String repositoryHint() { return 'owner/repository'; }

    protected override Map<String, String> headers() {
        return new Map<String, String>{ 'Accept' => 'application/vnd.github+json', 'X-GitHub-Api-Version' => '2022-11-28' };
    }

    private String repo() {
        return '/repos/' + conn.Repository__c.trim();
    }

    public override String defaultBranch() {
        HttpResponse res = send('GET', repo(), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        return String.valueOf(((Map<String, Object>) parse(res)).get('default_branch'));
    }

    public override Boolean branchExists(String branch) {
        HttpResponse res = send('GET', repo() + '/branches/' + enc(branch), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'Branch lookup');
        return true;
    }

    public override Boolean fileExists(String path, String ref) {
        HttpResponse res = send('GET', repo() + '/contents/' + encPath(path) + '?ref=' + enc(ref), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'File lookup');
        return true;
    }

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

    public override void putFile(String path, String branch, String base64Content, String message) {
        String url = repo() + '/contents/' + encPath(path);
        Map<String, Object> body = new Map<String, Object>{ 'message' => message, 'content' => base64Content, 'branch' => branch };
        HttpResponse existing = send('GET', url + '?ref=' + enc(branch), null);
        if (existing.getStatusCode() == 200) {
            body.put('sha', ((Map<String, Object>) parse(existing)).get('sha'));
        }
        assertOk(send('PUT', url, JSON.serialize(body)), 'Committing ' + path);
    }

    public override String getFileRaw(String path, String ref) {
        HttpResponse res = send('GET', repo() + '/contents/' + encPath(path) + '?ref=' + enc(ref), null,
            new Map<String, String>{ 'Accept' => 'application/vnd.github.raw' });
        if (res.getStatusCode() == 404) {
            return null;
        }
        assertOk(res, 'Reading ' + path);
        return res.getBody();
    }

    public override void startPipeline(Map<String, String> inputs) {
        HttpResponse res = send('POST', repo() + '/actions/workflows/' + enc(conn.Pipeline__c.trim()) + '/dispatches',
            JSON.serialize(new Map<String, Object>{ 'ref' => conn.Pipeline_Branch__c.trim(), 'inputs' => inputs }));
        assertOk(res, 'Starting the pipeline');
    }

    public override Run findRun(String title) {
        HttpResponse res = send('GET', repo() + '/actions/workflows/' + enc(conn.Pipeline__c.trim())
            + '/runs?event=workflow_dispatch&per_page=50', null);
        assertOk(res, 'Reading pipeline runs');
        Object runs = ((Map<String, Object>) parse(res)).get('workflow_runs');
        for (Object o : runs == null ? new List<Object>() : (List<Object>) runs) {
            Map<String, Object> r = (Map<String, Object>) o;
            if (String.valueOf(r.get('display_title')) == title) {
                Run run = new Run();
                run.id = String.valueOf(r.get('id'));
                run.url = String.valueOf(r.get('html_url'));
                run.status = String.valueOf(r.get('status'));
                run.conclusion = r.get('conclusion') == null ? null : String.valueOf(r.get('conclusion'));
                return run; // newest first
            }
        }
        return null;
    }

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

    public override void closePullRequest(Integer prNumber, String comment) {
        if (String.isNotBlank(comment)) {
            assertOk(send('POST', repo() + '/issues/' + prNumber + '/comments', JSON.serialize(new Map<String, Object>{ 'body' => comment })),
                'Commenting on pull request #' + prNumber);
        }
        assertOk(send('PATCH', repo() + '/pulls/' + prNumber, JSON.serialize(new Map<String, Object>{ 'state' => 'closed' })),
            'Closing pull request #' + prNumber);
    }

    public override List<String> pipelineFiles() {
        return new List<String>{ '.github/workflows/' + conn.Pipeline__c.trim(), 'scripts/release-relay.js' };
    }
}
