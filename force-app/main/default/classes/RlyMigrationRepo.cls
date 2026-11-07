/**
 * @description The repository reads the Migration tab needs that RlyGit has no operation for (build 46), each provider's
 * own address through the connection's Named Credential (RlyGit.request): the first page of branches (what the current
 * repository holds; whether the new one is empty), the open pull or merge requests (they don't move), and the https
 * address the migrate job pushes to (never with credentials). Callouts only.
 */
public with sharing class RlyMigrationRepo {

    private static final Integer PAGE = 50;
    private static final String AZURE_VERSION = 'api-version=7.1';

    /** @description The first page of a repository's branches. */
    public class Refs {
        /** @description The branch names. */
        public List<String> branches = new List<String>();
        /** @description A full page: there may be more. */
        public Boolean more = false;
    }

    /** @description An open pull or merge request in the current repository. */
    public class OpenRequest {
        /** @description #41 or !12. */
        @AuraEnabled public String label;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description Its page on the provider. */
        @AuraEnabled public String url;
        /** @description source → target. */
        @AuraEnabled public String branches;
    }

    /**
     * @description The first page of the repository's branches.
     * @param git the provider
     * @return the branches
     */
    public static Refs refs(RlyGit git) {
        String provider = git.connection().Provider__c;
        HttpResponse res = git.request(new RlyGitRequest('GET', branchesPath(git, provider), null));
        git.requireOk(res, 'Listing the branches of ' + git.connection().Repository__c);
        Refs out = new Refs();
        for (Object o : rows(res.getBody(), provider)) {
            String name = String.valueOf(((Map<String, Object>) o).get('name'));
            out.branches.add(name.removeStart('refs/heads/'));
        }
        out.more = out.branches.size() >= PAGE;
        return out;
    }

    /**
     * @description The open pull or merge requests (the first page).
     * @param git the provider
     * @return the requests
     */
    public static List<OpenRequest> openRequests(RlyGit git) {
        String provider = git.connection().Provider__c;
        HttpResponse res = git.request(new RlyGitRequest('GET', requestsPath(git, provider), null));
        git.requireOk(res, 'Listing the open ' + git.changeRequestLabel().toLowerCase() + 's');
        List<OpenRequest> out = new List<OpenRequest>();
        for (Object o : rows(res.getBody(), provider)) {
            out.add(requestOf((Map<String, Object>) o, provider, git));
        }
        return out;
    }

    /**
     * @description The https address the migrate job pushes to, without credentials.
     * @param git the provider (the new connection)
     * @return for example https://gitlab.com/group/project.git
     */
    public static String pushUrl(RlyGit git) {
        String web = git.webUrl();
        if (git.connection().Provider__c == 'AzureDevOps') {
            List<String> p = git.connection().Repository__c.trim().split('/');
            return 'https://dev.azure.com/' + enc(p[0]) + '/' + enc(p[1]) + '/_git/' + enc(p[2]);
        }
        return web == null ? null : web + '.git';
    }

    /**
     * @description The migrate job's name for a provider.
     * @param provider GitHub, GitLab, Bitbucket or AzureDevOps
     * @return github, gitlab, bitbucket or azure
     */
    public static String providerKey(String provider) {
        return provider == 'AzureDevOps' ? 'azure' : (provider == null ? '' : provider.toLowerCase());
    }

    private static String branchesPath(RlyGit git, String provider) {
        String repo = git.connection().Repository__c.trim();
        if (provider == 'GitLab') {
            return RlyGitLabRuns.project(git, '/repository/branches?per_page=' + PAGE);
        }
        if (provider == RlyGit.BITBUCKET) {
            return '/repositories/' + repo + '/refs/branches?pagelen=' + PAGE;
        }
        if (provider == 'AzureDevOps') {
            return azure(repo, '/refs?filter=heads/&$top=' + PAGE + '&' + AZURE_VERSION);
        }
        return '/repos/' + repo + '/branches?per_page=' + PAGE;
    }

    private static String requestsPath(RlyGit git, String provider) {
        String repo = git.connection().Repository__c.trim();
        if (provider == 'GitLab') {
            return RlyGitLabRuns.project(git, '/merge_requests?state=opened&per_page=' + PAGE);
        }
        if (provider == RlyGit.BITBUCKET) {
            return '/repositories/' + repo + '/pullrequests?state=OPEN&pagelen=' + PAGE;
        }
        if (provider == 'AzureDevOps') {
            return azure(repo, '/pullrequests?searchCriteria.status=active&$top=' + PAGE + '&' + AZURE_VERSION);
        }
        return '/repos/' + repo + '/pulls?state=open&per_page=' + PAGE;
    }

    // organization/project/repository → /{org}/{project}/_apis/git/repositories/{repo}{path}
    private static String azure(String repo, String path) {
        List<String> p = repo.split('/');
        return '/' + enc(p[0]) + '/' + enc(p[1]) + '/_apis/git/repositories/' + enc(p[2]) + path;
    }

    // The list in an answer: an array (GitHub, GitLab), values (Bitbucket) or value (Azure DevOps).
    private static List<Object> rows(String body, String provider) {
        Object parsed = JSON.deserializeUntyped(String.isBlank(body) ? '[]' : body);
        if (parsed instanceof List<Object>) {
            return (List<Object>) parsed;
        }
        Object listed = ((Map<String, Object>) parsed).get(provider == 'AzureDevOps' ? 'value' : 'values');
        return listed instanceof List<Object> ? (List<Object>) listed : new List<Object>();
    }

    private static OpenRequest requestOf(Map<String, Object> m, String provider, RlyGit git) {
        OpenRequest r = new OpenRequest();
        r.title = str(m.get('title'));
        if (provider == 'GitLab') {
            r.label = '!' + str(m.get('iid'));
            r.url = str(m.get('web_url'));
            r.branches = str(m.get('source_branch')) + ' → ' + str(m.get('target_branch'));
        } else if (provider == RlyGit.BITBUCKET) {
            r.label = '#' + str(m.get('id'));
            r.url = str(dig(m, new List<String>{ 'links', 'html', 'href' }));
            r.branches = str(dig(m, new List<String>{ 'source', 'branch', 'name' })) + ' → ' + str(dig(m, new List<String>{ 'destination', 'branch', 'name' }));
        } else if (provider == 'AzureDevOps') {
            r.label = '#' + str(m.get('pullRequestId'));
            r.url = git.webUrl() + '/pullrequest/' + str(m.get('pullRequestId'));
            r.branches = str(m.get('sourceRefName')).removeStart('refs/heads/') + ' → ' + str(m.get('targetRefName')).removeStart('refs/heads/');
        } else {
            r.label = '#' + str(m.get('number'));
            r.url = str(m.get('html_url'));
            r.branches = str(dig(m, new List<String>{ 'head', 'ref' })) + ' → ' + str(dig(m, new List<String>{ 'base', 'ref' }));
        }
        return r;
    }

    private static Object dig(Map<String, Object> m, List<String> keys) {
        Object cur = m;
        for (String k : keys) {
            if (!(cur instanceof Map<String, Object>)) {
                return null;
            }
            cur = ((Map<String, Object>) cur).get(k);
        }
        return cur;
    }

    private static String str(Object o) {
        return o == null ? '' : String.valueOf(o);
    }

    private static String enc(String value) {
        return RlyGitRequest.encode(value);
    }
}
