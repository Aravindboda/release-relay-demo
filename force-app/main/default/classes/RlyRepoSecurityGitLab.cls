/**
 * @description Repository security (build 48) for GitLab, through the connection's Named Credential. Reads: the
 * pipeline branch's protection (GET /protected_branches/:name: nobody may push straight to it) and the merge request
 * approvals the project requires (GET /approval_rules, else /approvals; approval rules need GitLab Premium, so they can
 * show as unreadable); each org environment as a protected environment (GET /protected_environments/:name); and the
 * CI/CD variable RELAY_RUN_KEY (GET /variables): only its name and its masked and protected flags are kept, never its value.
 */
public with sharing class RlyRepoSecurityGitLab {

    private static final String MAINTAINER = 'the Maintainer role';
    private final RlyGit git;
    private final String branch;

    /**
     * @description A reader for a project.
     * @param git the Git provider (GitLab)
     * @param branch the pipeline branch
     */
    public RlyRepoSecurityGitLab(RlyGit git, String branch) {
        this.git = git;
        this.branch = branch;
    }

    /**
     * @description Every row: the branch, its approvals, the key, then one per environment.
     * @param envs the org environments
     * @return the rows
     */
    public List<RlyRepoSecurity.Item> items(List<String> envs) {
        List<RlyRepoSecurity.Item> out = new List<RlyRepoSecurity.Item>{ branchItem(), approvalItem(), keyItem() };
        for (String env : envs) {
            out.add(environmentItem(env));
        }
        return out;
    }

    private HttpResponse get(String path) {
        return git.request(new RlyGitRequest('GET', RlyGitLabRuns.project(git, path), null));
    }

    // Protected, and nobody may push to it (changes arrive by merge request).
    private RlyRepoSecurity.Item branchItem() {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('branch', branch + ' is protected (changes only by merge request)');
        String fix = 'Settings → Repository → Protected branches → ' + branch + ': Allowed to merge = Maintainers, Allowed to push = No one.';
        try {
            HttpResponse res = get('/protected_branches/' + RlyGitRequest.encode(branch));
            if (res.getStatusCode() == 404) {
                return i.found(RlyRepoSecurity.MISSING, branch + ' isn\'t a protected branch.').orFix(fix);
            }
            if (res.getStatusCode() != 200) {
                return i.cantRead(RlyRepoSecurity.why(res), MAINTAINER);
            }
            return pushers(RlyRepoSecurity.asMap(res).get('push_access_levels')) == 0
                ? i.found(RlyRepoSecurity.OK, 'Protected; nobody can push to it directly.')
                : i.found(RlyRepoSecurity.MISSING, 'Protected, but people can still push to it directly.').orFix(fix);
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), MAINTAINER);
        }
    }

    // Push access levels that let someone push (a role above No one, a user or a group).
    private static Integer pushers(Object levels) {
        Integer n = 0;
        for (Object o : levels instanceof List<Object> ? (List<Object>) levels : new List<Object>()) {
            Map<String, Object> l = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            n += RlyRepoSecurity.num(l.get('access_level')) > 0 || l.get('user_id') != null || l.get('group_id') != null ? 1 : 0;
        }
        return n;
    }

    // Merge requests need at least one approval.
    private RlyRepoSecurity.Item approvalItem() {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('approvals', 'Merge requests need an approval');
        String fix = 'Settings → Merge requests → Merge request approvals → add a rule with 1 or more required approvals '
            + '(GitLab Premium), and turn on "Prevent approval by author".';
        try {
            HttpResponse res = get('/approval_rules');
            Integer required = 0;
            if (res.getStatusCode() == 200) {
                for (Object o : RlyRepoSecurity.asList(res)) {
                    required = Math.max(required, o instanceof Map<String, Object> ? RlyRepoSecurity.num(((Map<String, Object>) o).get('approvals_required')) : 0);
                }
            } else {
                HttpResponse legacy = get('/approvals');
                if (legacy.getStatusCode() != 200) {
                    return i.cantRead(RlyRepoSecurity.why(res), MAINTAINER + ' (approval rules need GitLab Premium)');
                }
                required = RlyRepoSecurity.num(RlyRepoSecurity.asMap(legacy).get('approvals_before_merge'));
            }
            return required > 0 ? i.found(RlyRepoSecurity.OK, required + (required == 1 ? ' approval' : ' approvals') + ' required.')
                : i.found(RlyRepoSecurity.MISSING, 'No approval is required to merge.').orFix(fix);
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), MAINTAINER);
        }
    }

    // RELAY_RUN_KEY: a masked, protected CI/CD variable. Only the name and the two flags are looked at.
    private RlyRepoSecurity.Item keyItem() {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('key', 'Run-signing key ' + RlyRepoSecurity.KEY_NAME + ' in GitLab');
        String fix = 'Settings → CI/CD → Variables → Add variable ' + RlyRepoSecurity.KEY_NAME
            + ' with the key from the Run signing card: Masked, Protected, environments *.';
        try {
            HttpResponse res = get('/variables?per_page=100');
            if (res.getStatusCode() != 200) {
                return i.cantRead(RlyRepoSecurity.why(res), MAINTAINER);
            }
            for (Object o : RlyRepoSecurity.asList(res)) {
                Map<String, Object> v = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
                if (RlyRepoSecurity.KEY_NAME.equals(String.valueOf(v.get('key')))) {
                    return isSafe(v) ? i.found(RlyRepoSecurity.OK, 'CI/CD variable, masked and protected, all environments (its name and flags only).')
                        : i.found(RlyRepoSecurity.MISSING, 'There, but not masked, protected and for all environments (*).').orFix(fix);
                }
            }
            return i.found(RlyRepoSecurity.MISSING, 'No CI/CD variable named ' + RlyRepoSecurity.KEY_NAME
                + ': runs started outside the hub aren\'t refused yet.').orFix(fix);
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), MAINTAINER);
        }
    }

    // Masked, protected (only protected branches get it) and scope * (every job that verifies sees it).
    private static Boolean isSafe(Map<String, Object> v) {
        Object scope = v.get('environment_scope');
        return v.get('masked') == true && v.get('protected') == true && (scope == null || String.valueOf(scope) == '*');
    }

    // An org environment: a protected environment (GitLab Premium).
    private RlyRepoSecurity.Item environmentItem(String env) {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('env:' + env, 'Environment ' + env);
        try {
            HttpResponse res = get('/protected_environments/' + RlyGitRequest.encode(env));
            if (res.getStatusCode() == 200) {
                return i.found(RlyRepoSecurity.OK, 'A protected environment.');
            }
            if (res.getStatusCode() == 404) {
                return i.found(RlyRepoSecurity.MISSING, 'Not a protected environment: any pipeline can deploy with it.')
                    .orFix('Settings → CI/CD → Protected environments → protect ' + env + ' (GitLab Premium), and keep its variables Protected '
                        + 'so only ' + branch + ' (a protected branch) gets them.');
            }
            return i.cantRead(RlyRepoSecurity.why(res), MAINTAINER + ' (protected environments need GitLab Premium)');
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), MAINTAINER);
        }
    }
}
