/**
 * @description Azure DevOps REST API 7.1, through the Named Credential (URL https://dev.azure.com).
 * Token: personal access token with Code: Read and write, and Build: Read and execute.
 * Repository is organization/project/repository; Pipeline is the pipeline id (the number in its URL).
 */
public with sharing class RlyAzureRepos extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+/[A-Za-z0-9_. -]+/[A-Za-z0-9_. -]+$');
    private static final String V = 'api-version=7.1';
    private static final String ZERO = '0000000000000000000000000000000000000000';

    /**
     * @description The shape of an Azure DevOps repository.
     * @return organization/project/repository
     */
    protected override Pattern repositoryPattern() {
        return REPO;
    }

    /**
     * @description The shape of an Azure DevOps repository, in words.
     * @return organization/project/repository
     */
    public override String repositoryHint() {
        return 'organization/project/repository';
    }

    /**
     * @description The provider's name as people know it.
     * @return Azure DevOps
     */
    public override String providerLabel() {
        return 'Azure DevOps';
    }

    /**
     * @description The latest commit on a branch (GET git/refs?filter=heads/{name}, value[0].objectId).
     * @param branch the branch name
     * @return the commit SHA, or null when the branch isn't there
     */
    public override String branchHead(String branch) {
        return headSha(branch);
    }

    // organization, project and repository, from the connection's Repository__c
    private List<String> parts() {
        return conn.Repository__c.trim().split('/');
    }

    private String project(String path) {
        List<String> p = parts();
        return '/' + enc(p[0]) + '/' + enc(p[1]) + path;
    }

    private String git(String path) {
        return project('/_apis/git/repositories/' + enc(parts()[2]) + path);
    }

    /**
     * @description The repository's default branch.
     * @return the branch name
     */
    public override String defaultBranch() {
        HttpResponse res = send('GET', git('?' + V), null);
        assertOk(res, 'Opening ' + conn.Repository__c);
        return String.valueOf(((Map<String, Object>) parse(res)).get('defaultBranch')).removeStart('refs/heads/');
    }

    private String headSha(String branch) {
        HttpResponse res = send('GET', git('/refs?filter=' + enc('heads/' + branch) + '&' + V), null);
        assertOk(res, 'Branch lookup');
        for (Object o : (List<Object>) ((Map<String, Object>) parse(res)).get('value')) {
            Map<String, Object> ref = (Map<String, Object>) o;
            if (ref.get('name') == 'refs/heads/' + branch) {
                return String.valueOf(ref.get('objectId'));
            }
        }
        return null;
    }

    /**
     * @description Whether a branch exists.
     * @param branch the branch name
     * @return true when it exists
     */
    public override Boolean branchExists(String branch) {
        return headSha(branch) != null;
    }

    /**
     * @description Whether a file exists on a branch.
     * @param path path in the repository
     * @param ref the branch
     * @return true when it exists
     */
    public override Boolean fileExists(String path, String ref) {
        HttpResponse res = send('GET', git('/items?path=' + enc('/' + path) + '&versionDescriptor.version=' + enc(ref)
            + '&versionDescriptor.versionType=branch&' + V), null);
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
        String sha = headSha(fromRef);
        if (sha == null) {
            throw new GitException('Branch ' + fromRef + ' wasn\'t found in ' + conn.Repository__c + '.');
        }
        HttpResponse res = send('POST', git('/refs?' + V), JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'name' => 'refs/heads/' + branch, 'oldObjectId' => ZERO, 'newObjectId' => sha } }));
        assertOk(res, 'Creating branch ' + branch);
    }

    /**
     * @description The pipeline script (the pipeline itself is checked by id).
     * @return the paths
     */
    public override List<String> pipelineFiles() {
        return new List<String>{ 'scripts/release-relay.js' };
    }

    /**
     * @description Checks Pipeline is a pipeline id and that the pipeline exists.
     */
    public override void checkPipeline() {
        if (!Pattern.matches('[0-9]{1,9}', String.isBlank(conn.Pipeline__c) ? '' : conn.Pipeline__c.trim())) {
            throw new GitException('For Azure DevOps, Pipeline is the pipeline id: the number after definitionId= in its URL.');
        }
        HttpResponse res = send('GET', project('/_apis/pipelines/' + conn.Pipeline__c.trim() + '?' + V), null);
        assertOk(res, 'Pipeline ' + conn.Pipeline__c + ' lookup');
    }
}
