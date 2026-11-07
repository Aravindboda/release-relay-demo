/**
 * @description The hub's own credentials for the Credentials dashboard (build 49), callouts only:
 *   GitHub token   one API call through the active connection; the github-authentication-token-expiration header gives
 *                  the expiry (absent: no expiry), HTTP 401 means it expired or was revoked
 *   GitLab token   GET /personal_access_tokens/self through every GitLab connection (active or not): expires_at, active
 *   other Git      one call (the pipeline branch exists); their tokens don't say when they expire
 *   Slack          auth.test, when Slack is on; no expiry
 *   certificates   the hub's own, by a Tooling query through the RLY_Org_Self Named Credential (the hub signing in to
 *                  itself); without it the row says to add it
 * RlyCredentialParse reads the answers. Each check adds its rows to the pass and never throws.
 */
public with sharing class RlyCredentialHubChecks {

    /** @description The Named Credential the hub reads itself through (created by the admin, not packaged). */
    public static final String SELF_CREDENTIAL = 'RLY_Org_Self';
    /** @description The Tooling query for certificates. */
    public static final String CERT_QUERY = 'SELECT DeveloperName, MasterLabel, ExpirationDate FROM Certificate';
    /** @description Key prefix of the hub's certificates. */
    public static final String HUB_CERT_PREFIX = 'cert:hub:';
    /** @description Key of the hub certificates placeholder (unknown or failed). */
    public static final String HUB_CERT_KEY = 'cert:hub';

    private static final Integer TIMEOUT_MS = 20000;
    // Tests can't create a Named Credential: they say RLY_Org_Self exists.
    @TestVisible private static Boolean selfCredentialForTest = false;

    /**
     * @description Checks the Git connections' tokens.
     * @param p the pass
     */
    public static void git(RlyCredentialCheck.Pass p) {
        List<RLY_Git_Connection__c> conns = RlyGitConnections.connections();
        for (Integer i = 0; i < conns.size(); i++) {
            RLY_Git_Connection__c c = conns[i];
            Boolean active = i == 0;
            if ((active || c.Provider__c == 'GitLab') && p.roomFor(1)) {
                p.add(gitRow(c, active));
            }
        }
        p.replaceScope('git:'); // connections removed since
    }

    private static RLY_Credential_Status__c gitRow(RLY_Git_Connection__c c, Boolean active) {
        String name = c.Provider__c + ' · ' + c.Repository__c + (active ? '' : ' (not active)');
        RLY_Credential_Status__c r = RlyCredentialRows.row('git:' + c.Id, RlyCredentialRows.KIND_GIT, name);
        try {
            RlyGit provider = RlyGit.forConnection(c);
            if (c.Provider__c == 'GitHub') {
                return RlyCredentialParse.gitHub(r, provider.request(new RlyGitRequest('GET', '/repos/' + c.Repository__c.trim(), null)));
            }
            if (c.Provider__c == 'GitLab') {
                return RlyCredentialParse.gitLab(r, provider.request(new RlyGitRequest('GET', '/personal_access_tokens/self', null)));
            }
            String branch = String.isBlank(c.Pipeline_Branch__c) ? provider.defaultBranch() : c.Pipeline_Branch__c.trim();
            provider.branchExists(branch);
            return RlyCredentialRows.mark(r, RlyCredentialRows.OK, 'The token answers. ' + provider.providerLabel() + ' doesn\'t say when it expires.');
        } catch (Exception e) {
            return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, e.getMessage());
        }
    }

    /**
     * @description Checks the Slack app, when Slack is on.
     * @param p the pass
     */
    public static void slack(RlyCredentialCheck.Pass p) {
        if (!RlySlack.isOn()) {
            p.gone(RlyCredentialCheck.SLACK_KEY);
            return;
        }
        if (!p.roomFor(1)) {
            return;
        }
        RLY_Credential_Status__c r = RlyCredentialRows.row(RlyCredentialCheck.SLACK_KEY, RlyCredentialRows.KIND_SLACK, 'Slack app');
        try {
            Map<String, Object> ans = RlySlackApi.call('auth.test', new Map<String, Object>());
            String team = ans.get('team') instanceof String ? ' (' + (String) ans.get('team') + ')' : '';
            p.add(RlyCredentialRows.mark(r, RlyCredentialRows.OK, 'The Slack app answers' + team + '. Bot tokens don\'t expire.'));
        } catch (Exception e) {
            p.add(RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'Slack: ' + e.getMessage()));
        }
    }

    /**
     * @description Reads the hub's own certificates through RLY_Org_Self.
     * @param p the pass (its hubCerts are filled for the org sign-in rows)
     */
    public static void certificates(RlyCredentialCheck.Pass p) {
        RLY_Credential_Status__c holder = RlyCredentialRows.row(HUB_CERT_KEY, RlyCredentialRows.KIND_CERT, 'Hub certificates');
        if (!selfCredentialForTest && !RlyCredentialStore.hasNamedCredential(SELF_CREDENTIAL)) {
            p.add(RlyCredentialRows.mark(holder, RlyCredentialRows.UNKNOWN, 'Add the RLY_Org_Self Named Credential (and the RLY_Org_Self_Access '
                + 'permission set) so the hub can read its own certificates.'));
            return;
        }
        if (!p.roomFor(1)) {
            return;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint('callout:' + SELF_CREDENTIAL + RlyOrgSession.toolingQueryPath(CERT_QUERY));
            req.setHeader('Accept', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                p.add(RlyCredentialRows.mark(holder, RlyCredentialRows.FAILED, 'The hub answered HTTP ' + res.getStatusCode()
                    + ' through RLY_Org_Self: ' + String.valueOf(res.getBody()).left(300)));
                return;
            }
            for (RLY_Credential_Status__c r : RlyCredentialParse.certRows(res.getBody(), HUB_CERT_PREFIX, null)) {
                p.hubCerts.put(r.Key__c.removeStart(HUB_CERT_PREFIX).toLowerCase(), r.Expires_On__c);
                p.add(r);
            }
            p.replaceScope(HUB_CERT_PREFIX);
            p.gone(HUB_CERT_KEY);
        } catch (Exception e) {
            p.add(RlyCredentialRows.mark(holder, RlyCredentialRows.FAILED, 'RLY_Org_Self: ' + e.getMessage()));
        }
    }
}
