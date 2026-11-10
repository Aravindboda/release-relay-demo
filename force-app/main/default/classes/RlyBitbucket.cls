/**
 * @description Bitbucket Cloud REST API 2.0, through the Named Credential (URL https://api.bitbucket.org/2.0).
 * Token: repository access token with Repositories: write, Pull requests: write, Pipelines: write.
 */
public with sharing class RlyBitbucket extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

    /**
     * @description The shape of a Bitbucket repository name.
     * @return workspace/repository
     */
    protected override Pattern repositoryPattern() {
        return REPO;
    }

    /**
     * @description The shape of a Bitbucket repository name, in words.
     * @return workspace/repository
     */
    public override String repositoryHint() {
        return 'workspace/repository';
    }

    /**
     * @description The provider's name as people know it.
     * @return Bitbucket
     */
    public override String providerLabel() {
        return 'Bitbucket';
    }

    /**
     * @description The latest commit on a branch (GET /refs/branches/{name}, target.hash).
     * @param branch the branch name
     * @return the commit SHA, or null when the branch isn't there
     */
    public override String branchHead(String branch) {
        HttpResponse res = send('GET', r('/refs/branches/' + enc(branch)), null);
        if (res.getStatusCode() == 404) {
            return null;
        }
        assertOk(res, 'Branch lookup');
        Object targetInfo = ((Map<String, Object>) parse(res)).get('target');
        return targetInfo == null ? null : String.valueOf(((Map<String, Object>) targetInfo).get('hash'));
    }

    private String r(String path) {
        return '/repositories/' + conn.Repository__c.trim() + path;
    }

    /**
     * @description The repository's main branch (main when it has none).
     * @return the branch name
     */
    public override String defaultBranch() {
        HttpResponse res = send('GET', r(''), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        Object main = ((Map<String, Object>) parse(res)).get('mainbranch');
        return main == null ? 'main' : String.valueOf(((Map<String, Object>) main).get('name'));
    }

    /**
     * @description Whether a branch exists.
     * @param branch the branch name
     * @return true when it exists
     */
    public override Boolean branchExists(String branch) {
        HttpResponse res = send('GET', r('/refs/branches/' + enc(branch)), null);
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
        HttpResponse res = send('GET', r('/src/' + enc(ref) + '/' + encPath(path) + '?format=meta'), null);
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
        HttpResponse ref = send('GET', r('/refs/branches/' + enc(fromRef)), null);
        if (ref.getStatusCode() == 404) {
            throw new GitException('Branch ' + fromRef + ' wasn\'t found in ' + conn.Repository__c + '.');
        }
        assertOk(ref, 'Branch lookup');
        String hash = String.valueOf(((Map<String, Object>) ((Map<String, Object>) parse(ref)).get('target')).get('hash'));
        HttpResponse res = send('POST', r('/refs/branches'),
            JSON.serialize(new Map<String, Object>{ 'name' => branch, 'target' => new Map<String, Object>{ 'hash' => hash } }));
        assertOk(res, 'Creating branch ' + branch);
    }

    /**
     * @description The pipelines file and the pipeline script.
     * @return the paths
     */
    public override List<String> pipelineFiles() {
        return new List<String>{ 'bitbucket-pipelines.yml', 'scripts/release-relay.js' };
    }
}
