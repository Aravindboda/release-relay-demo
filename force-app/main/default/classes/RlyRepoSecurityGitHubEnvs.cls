/**
 * @description Repository security (build 48) for GitHub: each org environment's deployment branch policy
 * (GET /environments/{env}, and /deployment-branch-policies when it lists branches). In place when only the pipeline
 * branch, or only protected branches, may deploy with it; missing when the environment isn't in GitHub yet (a run
 * makes it open to every branch) or any branch may use it.
 */
public with sharing class RlyRepoSecurityGitHubEnvs {

    private final RlyGit git;
    private final String branch;

    /**
     * @description A reader for a repository.
     * @param git the Git provider (GitHub)
     * @param branch the pipeline branch
     */
    public RlyRepoSecurityGitHubEnvs(RlyGit git, String branch) {
        this.git = git;
        this.branch = branch;
    }

    /**
     * @description One row per environment.
     * @param envs the org environments
     * @return the rows
     */
    public List<RlyRepoSecurity.Item> items(List<String> envs) {
        List<RlyRepoSecurity.Item> out = new List<RlyRepoSecurity.Item>();
        for (String env : envs) {
            out.add(environmentItem(env));
        }
        return out;
    }

    private RlyRepoSecurity.Item environmentItem(String env) {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('env:' + env, 'Environment ' + env);
        String fix = 'Settings → Environments → ' + env + ' → Deployment branches and tags → Selected branches → add ' + branch + ' only.';
        try {
            HttpResponse res = RlyRepoSecurity.gitHubGet(git, '/environments/' + RlyGitRequest.encode(env));
            if (res.getStatusCode() == 404) {
                return i.found(RlyRepoSecurity.MISSING, 'Not in GitHub yet: a run makes it open to every branch.')
                    .orFix('Settings → Environments → New environment ' + env + ', then limit its deployment branches to ' + branch + '.');
            }
            if (res.getStatusCode() != 200) {
                return i.cantRead(RlyRepoSecurity.why(res), 'Environments: read');
            }
            Object policy = RlyRepoSecurity.asMap(res).get('deployment_branch_policy');
            Map<String, Object> p = policy instanceof Map<String, Object> ? (Map<String, Object>) policy : null;
            if (p == null) {
                return i.found(RlyRepoSecurity.MISSING, 'Any branch can deploy with it.').orFix(fix);
            }
            if (p.get('protected_branches') == true) {
                return i.found(RlyRepoSecurity.OK, 'Deploys only from protected branches.');
            }
            return customPolicies(i, env).orFix(fix);
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), 'Environments: read');
        }
    }

    private RlyRepoSecurity.Item customPolicies(RlyRepoSecurity.Item i, String env) {
        HttpResponse res = RlyRepoSecurity.gitHubGet(git, '/environments/' + RlyGitRequest.encode(env) + '/deployment-branch-policies?per_page=100');
        if (res.getStatusCode() != 200) {
            return i.cantRead(RlyRepoSecurity.why(res), 'Environments: read');
        }
        Object rows = RlyRepoSecurity.asMap(res).get('branch_policies');
        List<String> others = new List<String>();
        Boolean pipelineBranch = false;
        for (Object o : rows instanceof List<Object> ? (List<Object>) rows : new List<Object>()) {
            String name = o instanceof Map<String, Object> ? String.valueOf(((Map<String, Object>) o).get('name')) : '';
            if (name.equals(branch)) {
                pipelineBranch = true;
            } else {
                others.add(name);
            }
        }
        if (pipelineBranch && others.isEmpty()) {
            return i.found(RlyRepoSecurity.OK, 'Deploys only from ' + branch + '.');
        }
        return i.found(RlyRepoSecurity.MISSING, others.isEmpty() ? 'No branch may deploy with it, not even ' + branch + '.'
            : 'Also allows: ' + String.join(others, ', ') + '.');
    }
}
