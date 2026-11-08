/**
 * @description Repository security (build 48) for GitHub, through the connection's Named Credential: the pipeline
 * branch's protection (GET /branches/{b}/protection, else the rulesets that apply to it: GET /rules/branches/{b}) for a
 * required pull request review. The run-signing key: RlyRepoSecurityGitHubKey; each org environment:
 * RlyRepoSecurityGitHubEnvs.
 */
public with sharing class RlyRepoSecurityGitHub {

    private final RlyGit git;
    private final String branch;

    /**
     * @description A reader for a repository.
     * @param git the Git provider (GitHub)
     * @param branch the pipeline branch
     */
    public RlyRepoSecurityGitHub(RlyGit git, String branch) {
        this.git = git;
        this.branch = branch;
    }

    /**
     * @description The branch row.
     * @return the rows
     */
    public List<RlyRepoSecurity.Item> items() {
        return new List<RlyRepoSecurity.Item>{ branchItem() };
    }

    // The pipeline branch: protected (classic protection or a ruleset) with at least one required approval.
    private RlyRepoSecurity.Item branchItem() {
        RlyRepoSecurity.Item i = RlyRepoSecurity.row('branch', branch + ' is protected and needs a reviewed pull request');
        String fix = 'Settings → Branches (or Rules → Rulesets) → protect ' + branch + ': Require a pull request before merging, '
            + 'Required approvals 1 or more, and don\'t allow bypassing.';
        try {
            HttpResponse res = RlyRepoSecurity.gitHubGet(git, '/branches/' + RlyGitRequest.encodePath(branch) + '/protection');
            if (res.getStatusCode() == 200) {
                return fromProtection(i, RlyRepoSecurity.asMap(res)).orFix(fix);
            }
            if (res.getStatusCode() != 404) {
                return i.cantRead(RlyRepoSecurity.why(res), 'Administration: read');
            }
            return fromRulesets(i).orFix(fix);
        } catch (Exception e) {
            return i.cantRead(e.getMessage(), 'Administration: read');
        }
    }

    private static RlyRepoSecurity.Item fromProtection(RlyRepoSecurity.Item i, Map<String, Object> p) {
        Object reviews = p.get('required_pull_request_reviews');
        Integer approvals = reviews instanceof Map<String, Object> ? RlyRepoSecurity.num(((Map<String, Object>) reviews).get('required_approving_review_count')) : 0;
        if (approvals > 0) {
            return i.found(RlyRepoSecurity.OK, 'Protected; pull requests need ' + approvalsText(approvals) + '.');
        }
        return i.found(RlyRepoSecurity.MISSING, reviews == null ? 'Protected, but it doesn\'t require a pull request review.'
            : 'Protected; pull requests are required but need no approval.');
    }

    private RlyRepoSecurity.Item fromRulesets(RlyRepoSecurity.Item i) {
        HttpResponse res = RlyRepoSecurity.gitHubGet(git, '/rules/branches/' + RlyGitRequest.encodePath(branch));
        Integer approvals = 0;
        for (Object o : res.getStatusCode() == 200 ? RlyRepoSecurity.asList(res) : new List<Object>()) {
            Map<String, Object> rule = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            Object params = rule.get('parameters');
            if (String.valueOf(rule.get('type')) == 'pull_request' && params instanceof Map<String, Object>) {
                approvals = Math.max(approvals, RlyRepoSecurity.num(((Map<String, Object>) params).get('required_approving_review_count')));
            }
        }
        return approvals > 0
            ? i.found(RlyRepoSecurity.OK, 'A ruleset requires pull requests with ' + approvalsText(approvals) + '.')
            : i.found(RlyRepoSecurity.MISSING, branch + ' isn\'t protected by a branch rule or ruleset that needs a review.');
    }

    private static String approvalsText(Integer n) {
        return n + (n == 1 ? ' approval' : ' approvals');
    }
}
