/**
 * @description GitLab REST API v4, through the Named Credential (URL https://gitlab.com/api/v4, or your own).
 * Token: project access token with api and write_repository.
 */
public with sharing class RlyGitLab extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$');

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
        return '/projects/' + enc(conn.Repository__c.trim()) + path;
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
     * @description The CI file and the pipeline script.
     * @return the paths
     */
    public override List<String> pipelineFiles() {
        return new List<String>{ String.isBlank(conn.Pipeline__c) ? '.gitlab-ci.yml' : conn.Pipeline__c.trim(), 'scripts/release-relay.js' };
    }
}
