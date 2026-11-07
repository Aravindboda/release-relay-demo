/**
 * @description Integration users and the hub's own sign-in for the Credentials dashboard (build 49): whether an org's
 * integration user is active (a REST query through the hub's sign-in to that org, or a plain query for the hub's own
 * user), with the org's last saved sign-in check (Status__c, Last_Checked__c); the hub's sign-in row from that saved
 * check; and the expiry of the hub certificate an org signs in with. Never throws.
 */
public with sharing class RlyCredentialUsers {

    /** @description The user is active. */
    public static final String ACTIVE = 'active';
    /** @description The user is inactive. */
    public static final String INACTIVE = 'inactive';

    /**
     * @description The hub's own org: its sign-in row from its saved check and its integration user (no callout).
     * @param p the pass
     * @param o the hub's org record
     */
    public static void hubOrg(RlyCredentialCheck.Pass p, RLY_Org__c o) {
        RLY_Credential_Status__c s = RlyCredentialRows.orgRow(RlyCredentialOrgChecks.signInKey(o.Id), RlyCredentialRows.KIND_SIGNIN, o);
        s.Name = (o.Name + ' (hub)').left(80);
        p.add(fromSavedCheck(withCertificate(s, o, p), o));
        if (String.isNotBlank(o.Username__c)) {
            RLY_Credential_Status__c u = RlyCredentialRows.orgRow('user:' + o.Id, RlyCredentialRows.KIND_USER, o);
            u.Name = (o.Name + ' · ' + o.Username__c.trim()).left(80);
            p.add(user(u, stateOf(RlyCredentialStore.hubUserActive(o.Username__c.trim())), o));
        }
    }

    /**
     * @description Sets the sign-in row's expiry from the hub certificate the org signs in with (Certificate__c), when
     * the hub's certificates were read.
     * @param s the sign-in row
     * @param o the org
     * @param p the pass, with hubCerts
     * @return the row
     */
    public static RLY_Credential_Status__c withCertificate(RLY_Credential_Status__c s, RLY_Org__c o, RlyCredentialCheck.Pass p) {
        String cert = String.isBlank(o.Certificate__c) ? null : o.Certificate__c.trim().toLowerCase();
        if (cert != null && p.hubCerts.containsKey(cert)) {
            RlyCredentialRows.expiring(s, p.hubCerts.get(cert), null);
            s.Message__c = s.Message__c == null ? null : 'Hub certificate ' + o.Certificate__c.trim() + ': ' + s.Message__c.uncapitalize();
        }
        return s;
    }

    /**
     * @description The user row after signing in to the org; a refused query leaves it Unknown.
     * @param u the row
     * @param o the org
     * @return the row
     */
    public static RLY_Credential_Status__c userRow(RLY_Credential_Status__c u, RLY_Org__c o) {
        try {
            return user(u, userActive(o), o);
        } catch (Exception e) {
            return RlyCredentialRows.mark(u, RlyCredentialRows.UNKNOWN, 'Couldn\'t read the user: ' + e.getMessage());
        }
    }

    /**
     * @description The user row from whether the user is active.
     * @param u the row
     * @param state ACTIVE, INACTIVE or null (not found)
     * @param o the org
     * @return the row
     */
    public static RLY_Credential_Status__c user(RLY_Credential_Status__c u, String state, RLY_Org__c o) {
        String last = o.Last_Checked__c == null ? 'No saved sign-in check.'
            : 'Last sign-in check ' + (o.Status__c == 'Failed' ? 'failed' : 'OK') + ' ' + o.Last_Checked__c.format('d MMM yyyy') + '.';
        if (state == null) {
            return RlyCredentialRows.mark(u, RlyCredentialRows.FAILED, 'No user ' + o.Username__c.trim() + ' in ' + o.Name + '. ' + last);
        }
        return state == ACTIVE ? RlyCredentialRows.mark(u, RlyCredentialRows.OK, 'Active. ' + last)
            : RlyCredentialRows.mark(u, RlyCredentialRows.FAILED, 'The integration user is inactive. ' + last);
    }

    // The hub's sign-in row: the org's saved check (Pipeline tab), with the certificate's expiry.
    private static RLY_Credential_Status__c fromSavedCheck(RLY_Credential_Status__c s, RLY_Org__c o) {
        String expiry = s.Message__c;
        String last = o.Last_Checked__c == null ? '' : ' (checked ' + o.Last_Checked__c.format('d MMM yyyy, h:mm a') + ')';
        String base = s.Status__c == RlyCredentialRows.UNKNOWN ? RlyCredentialRows.OK : s.Status__c;
        if (o.Status__c == 'Connected' || o.Status__c == 'Refreshed') {
            return RlyCredentialRows.mark(s, base, 'Last sign-in check OK' + last + '.' + (expiry == null ? '' : ' ' + expiry));
        }
        if (o.Status__c == 'Failed') {
            return RlyCredentialRows.mark(s, RlyCredentialRows.FAILED, 'The last sign-in check failed' + last + '.');
        }
        return RlyCredentialRows.mark(s, RlyCredentialRows.UNKNOWN, 'Not checked yet: Check the org on the Pipeline tab.');
    }

    private static String stateOf(Boolean active) {
        return active == null ? null : (active ? ACTIVE : INACTIVE);
    }

    // The org's integration user: ACTIVE, INACTIVE, or null when not found.
    private static String userActive(RLY_Org__c o) {
        String soql = 'SELECT IsActive FROM User WHERE Username = \'' + String.escapeSingleQuotes(o.Username__c.trim()) + '\'';
        Map<String, Object> ans = (Map<String, Object>) RlyOrgSession.getJson(o, RlyOrgSession.queryPath(soql));
        List<Object> records = ans.get('records') instanceof List<Object> ? (List<Object>) ans.get('records') : new List<Object>();
        return records.isEmpty() ? null : stateOf(((Map<String, Object>) records[0]).get('IsActive') == true);
    }
}
