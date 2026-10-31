/**
 * GitLab REST API v4, through the Named Credential (URL https://gitlab.com/api/v4, or your own).
 * Token: project access token with api and write_repository.
 */
public with sharing class RlyGitLab extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$');

    public override Pattern repositoryPattern() { return REPO; }
    public override String repositoryHint() { return 'group/project'; }

    private String p(String path) {
        return '/projects/' + enc(conn.Repository__c.trim()) + path;
    }

    public override String defaultBranch() {
        HttpResponse res = send('GET', p(''), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        return String.valueOf(((Map<String, Object>) parse(res)).get('default_branch'));
    }

    public override Boolean branchExists(String branch) {
        HttpResponse res = send('GET', p('/repository/branches/' + enc(branch)), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'Branch lookup');
        return true;
    }

    public override Boolean fileExists(String path, String ref) {
        HttpResponse res = send('GET', p('/repository/files/' + enc(path) + '?ref=' + enc(ref)), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'File lookup');
        return true;
    }

    public override void createBranch(String branch, String fromRef) {
        HttpResponse res = send('POST', p('/repository/branches?branch=' + enc(branch) + '&ref=' + enc(fromRef)), null);
        assertOk(res, 'Creating branch ' + branch);
    }

    public override List<String> pipelineFiles() {
        return new List<String>{ String.isBlank(conn.Pipeline__c) ? '.gitlab-ci.yml' : conn.Pipeline__c.trim(), 'scripts/release-relay.js' };
    }
}
