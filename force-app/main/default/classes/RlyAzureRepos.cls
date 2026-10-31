/**
 * Azure DevOps REST API 7.1, through the Named Credential (URL https://dev.azure.com).
 * Token: personal access token with Code: Read and write, and Build: Read and execute.
 * Repository is organization/project/repository; Pipeline is the pipeline id (the number in its URL).
 */
public with sharing class RlyAzureRepos extends RlyGit {

    private static final Pattern REPO = Pattern.compile('^[A-Za-z0-9_.-]+/[A-Za-z0-9_. -]+/[A-Za-z0-9_. -]+$');
    private static final String V = 'api-version=7.1';
    private static final String ZERO = '0000000000000000000000000000000000000000';

    private String org;
    private String project;
    private String repoName;

    public override Pattern repositoryPattern() { return REPO; }
    public override String repositoryHint() { return 'organization/project/repository'; }

    protected override void init() {
        List<String> parts = conn.Repository__c.trim().split('/');
        org = parts[0];
        project = parts[1];
        repoName = parts[2];
    }

    private String git(String path) {
        return '/' + enc(org) + '/' + enc(project) + '/_apis/git/repositories/' + enc(repoName) + path;
    }

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

    public override Boolean branchExists(String branch) {
        return headSha(branch) != null;
    }

    public override Boolean fileExists(String path, String ref) {
        HttpResponse res = send('GET', git('/items?path=' + enc('/' + path) + '&versionDescriptor.version=' + enc(ref)
            + '&versionDescriptor.versionType=branch&' + V), null);
        if (res.getStatusCode() == 404) {
            return false;
        }
        assertOk(res, 'File lookup');
        return true;
    }

    public override void createBranch(String branch, String fromRef) {
        String sha = headSha(fromRef);
        if (sha == null) {
            throw new GitException('Branch ' + fromRef + ' wasn\'t found in ' + conn.Repository__c + '.');
        }
        HttpResponse res = send('POST', git('/refs?' + V), JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'name' => 'refs/heads/' + branch, 'oldObjectId' => ZERO, 'newObjectId' => sha } }));
        assertOk(res, 'Creating branch ' + branch);
    }

    public override List<String> pipelineFiles() {
        return new List<String>{ 'scripts/release-relay.js' };
    }

    public override void checkPipeline() {
        if (!Pattern.matches('[0-9]{1,9}', String.isBlank(conn.Pipeline__c) ? '' : conn.Pipeline__c.trim())) {
            throw new GitException('For Azure DevOps, Pipeline is the pipeline id: the number after definitionId= in its URL.');
        }
        HttpResponse res = send('GET', '/' + enc(org) + '/' + enc(project) + '/_apis/pipelines/' + conn.Pipeline__c.trim() + '?' + V, null);
        assertOk(res, 'Pipeline ' + conn.Pipeline__c + ' lookup');
    }
}
