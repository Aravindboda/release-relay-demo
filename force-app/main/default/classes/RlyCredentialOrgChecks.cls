/**
 * @description The registered orgs' credentials for the Credentials dashboard (build 49), callouts only, through the
 * hub's own sign-in to each org (RlyOrgSession: the JWT bearer flow with the hub certificate named on the org):
 *   Org sign-in       signing in works; its expiry is that of the hub certificate the org signs in with
 *   Certificate       the org's certificates (Tooling query, the same as the hub's)
 *   Integration user  the org's integration user (Username__c) is active (RlyCredentialUsers)
 * The hub's own org needs no sign-in (RlyCredentialUsers.hubOrg). An org without a sign-in shows Unknown. Orgs are
 * checked oldest first while the pass has room (three calls each); the rest wait for the next pass. Never throws.
 */
public with sharing class RlyCredentialOrgChecks {

    /** @description Callouts one org takes at most (sign in, certificates, user). */
    public static final Integer CALLS_PER_ORG = 3;

    /**
     * @description Checks the orgs, oldest checked first, while the pass has room.
     * @param p the pass (with its saved rows)
     */
    public static void run(RlyCredentialCheck.Pass p) {
        for (RLY_Org__c o : oldestFirst(RlyCredentialStore.orgs(), p.saved)) {
            if (o.Role__c == 'Hub') {
                RlyCredentialUsers.hubOrg(p, o);
            } else if (!hasSignIn(o)) {
                p.add(RlyCredentialRows.mark(RlyCredentialRows.orgRow(signInKey(o.Id), RlyCredentialRows.KIND_SIGNIN, o),
                    RlyCredentialRows.UNKNOWN, 'No sign-in: register the org\'s username, consumer key and certificate on the Pipeline tab to check it.'));
            } else if (p.roomFor(CALLS_PER_ORG)) {
                orgWithSignIn(p, o);
                p.orgsChecked++;
            } else {
                p.orgsLeft++;
            }
        }
    }

    /**
     * @description Whether the hub can sign in to the org: a My Domain, a username, a consumer key and a certificate.
     * @param o the org
     * @return true when it can
     */
    public static Boolean hasSignIn(RLY_Org__c o) {
        return String.isNotBlank(o.My_Domain__c) && String.isNotBlank(o.Username__c) && String.isNotBlank(o.Certificate__c)
            && RlyOrgSession.consumerKey(o) != null;
    }

    /**
     * @description The org sign-in row's key.
     * @param orgId the org
     * @return the key
     */
    public static String signInKey(Id orgId) {
        return 'signin:' + orgId;
    }

    // Never-checked orgs first, then the oldest sign-in check.
    private static List<RLY_Org__c> oldestFirst(List<RLY_Org__c> orgs, Map<String, RLY_Credential_Status__c> saved) {
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        Map<Long, List<RLY_Org__c>> byTime = new Map<Long, List<RLY_Org__c>>();
        for (RLY_Org__c o : orgs) {
            RLY_Credential_Status__c s = saved.get(signInKey(o.Id));
            Long t = s == null || s.Last_Checked__c == null ? 0 : s.Last_Checked__c.getTime();
            if (!byTime.containsKey(t)) {
                byTime.put(t, new List<RLY_Org__c>());
            }
            byTime.get(t).add(o);
        }
        List<Long> times = new List<Long>(byTime.keySet());
        times.sort();
        for (Long t : times) {
            out.addAll(byTime.get(t));
        }
        return out;
    }

    private static void orgWithSignIn(RlyCredentialCheck.Pass p, RLY_Org__c o) {
        RLY_Credential_Status__c s = RlyCredentialRows.orgRow(signInKey(o.Id), RlyCredentialRows.KIND_SIGNIN, o);
        RLY_Credential_Status__c u = RlyCredentialRows.orgRow('user:' + o.Id, RlyCredentialRows.KIND_USER, o);
        u.Name = (o.Name + ' · ' + o.Username__c.trim()).left(80);
        try {
            HttpResponse res = RlyOrgSession.send(o, new RlyOrgSession.Call('GET', RlyOrgSession.toolingQueryPath(RlyCredentialHubChecks.CERT_QUERY))
                .withHeader('Accept', 'application/json'));
            RlyCredentialUsers.withCertificate(s, o, p);
            String expiryText = s.Message__c;
            String signedIn = s.Status__c == RlyCredentialRows.UNKNOWN ? RlyCredentialRows.OK : s.Status__c;
            p.add(RlyCredentialRows.mark(s, signedIn, 'Signed in as ' + o.Username__c.trim() + '.' + (String.isBlank(expiryText) ? '' : ' ' + expiryText)));
            certificates(p, o, res);
            p.add(RlyCredentialUsers.userRow(u, o));
        } catch (Exception e) {
            p.add(RlyCredentialRows.mark(s, RlyCredentialRows.FAILED, e.getMessage()));
            p.add(RlyCredentialRows.mark(u, RlyCredentialRows.UNKNOWN, 'Couldn\'t sign in to ' + o.Name + ' to read the user.'));
        }
    }

    // The org's own certificates from the Tooling answer; a refused query leaves one Unknown row.
    private static void certificates(RlyCredentialCheck.Pass p, RLY_Org__c o, HttpResponse res) {
        String prefix = 'cert:' + o.Id + ':';
        RLY_Credential_Status__c holder = RlyCredentialRows.orgRow('cert:' + o.Id, RlyCredentialRows.KIND_CERT, o);
        holder.Name = (o.Name + ' certificates').left(80);
        if (res.getStatusCode() != 200) {
            p.add(RlyCredentialRows.mark(holder, RlyCredentialRows.UNKNOWN, o.Name + ' answered HTTP ' + res.getStatusCode()
                + ' to the certificate query (the integration user needs View Setup and Configuration).'));
            return;
        }
        for (RLY_Credential_Status__c r : RlyCredentialParse.certRows(res.getBody(), prefix, o)) {
            p.add(r);
        }
        p.replaceScope(prefix);
        p.gone(holder.Key__c);
    }
}
