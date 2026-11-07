/**
 * @description Repository security (build 48) for GitHub: where the run-signing key RELAY_RUN_KEY is. It belongs in
 * every org environment as an environment secret (each environment limited to the pipeline branch), because any
 * writer's branch workflow can read a repository secret. Reads the names of each environment's secrets
 * (GET /environments/{env}/secrets) and of the repository's (GET /actions/secrets); GitHub never returns values.
 * In place only when every org environment has it; a repository-level copy gets its own row: move it.
 */
public with sharing class RlyRepoSecurityGitHubKey {

    private final RlyGit git;
    private final String repo;
    private final List<String> missing = new List<String>();
    private final List<String> unreadable = new List<String>();

    /**
     * @description A reader for a repository.
     * @param git the Git provider (GitHub)
     */
    public RlyRepoSecurityGitHubKey(RlyGit git) {
        this.git = git;
        this.repo = '/repos/' + git.connection().Repository__c.trim();
    }

    /**
     * @description The key row, and a row asking to move a repository-level copy when there is one.
     * @param envs the org environments
     * @return the rows
     */
    public List<RlyRepoSecurity.Item> items(List<String> envs) {
        List<RlyRepoSecurity.Item> out = new List<RlyRepoSecurity.Item>{ environmentsItem(envs) };
        RlyRepoSecurity.Item repoLevel = repositoryItem();
        if (repoLevel != null) {
            out.add(repoLevel);
        }
        return out;
    }

    private HttpResponse get(String path) {
        return git.request(new RlyGitRequest('GET', repo + path, null));
    }

    // Every org environment has the secret.
    private RlyRepoSecurity.Item environmentsItem(List<String> envs) {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('key', 'Run-signing key ' + RlyRepoSecurity.KEY_NAME + ' in every org environment');
        try {
            for (String env : envs) {
                sort(env, get('/environments/' + RlyGitRequest.encode(env) + '/secrets?per_page=100'));
            }
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), 'Environments: read and Secrets: read');
        }
        if (!unreadable.isEmpty()) {
            return i.cantRead('the secrets of ' + String.join(unreadable, ', ') + ' can\'t be listed', 'Environments: read and Secrets: read');
        }
        if (envs.isEmpty() || !missing.isEmpty()) {
            return i.found(RlyRepoSecurity.MISSING, envs.isEmpty() ? 'No org has a Git environment yet.'
                : 'Missing in: ' + String.join(missing, ', ') + '. Runs started outside the hub aren\'t refused there.')
                .orFix('Settings → Environments → each of ' + (missing.isEmpty() ? 'your org environments' : String.join(missing, ', '))
                    + ' → Add environment secret ' + RlyRepoSecurity.KEY_NAME + ' with the key from the Run signing card.');
        }
        return i.found(RlyRepoSecurity.OK, 'An environment secret in ' + String.join(envs, ', ') + ' (names only: values are never read).');
    }

    // An environment without the secret (or not in GitHub: 404) goes to missing; one whose secrets can't be listed to unreadable.
    private void sort(String env, HttpResponse res) {
        Integer code = res.getStatusCode();
        if (code != 200 && code != 404) {
            unreadable.add(env);
        } else if (!hasSecret(res)) {
            missing.add(env);
        }
    }

    // A repository secret RELAY_RUN_KEY: any branch's workflow can read it. Null when there is none.
    private RlyRepoSecurity.Item repositoryItem() {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('key-repo', 'No repository-level ' + RlyRepoSecurity.KEY_NAME);
        try {
            HttpResponse res = get('/actions/secrets?per_page=100');
            if (res.getStatusCode() != 200) {
                return i.cantRead(RlyRepoSecurity.why(res), 'Secrets: read');
            }
            return !hasSecret(res) ? null : i.found(RlyRepoSecurity.MISSING, 'A repository secret ' + RlyRepoSecurity.KEY_NAME
                + ': a workflow on any branch can read it.').orFix('Move it to the environments: add it to each org environment, then delete '
                + 'the repository secret (Settings → Secrets and variables → Actions).');
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), 'Secrets: read');
        }
    }

    private static Boolean hasSecret(HttpResponse res) {
        Object secrets = res.getStatusCode() == 200 ? RlyRepoSecurity.asMap(res).get('secrets') : null;
        for (Object o : secrets instanceof List<Object> ? (List<Object>) secrets : new List<Object>()) {
            if (o instanceof Map<String, Object> && RlyRepoSecurity.KEY_NAME.equals(String.valueOf(((Map<String, Object>) o).get('name')))) {
                return true;
            }
        }
        return false;
    }
}
