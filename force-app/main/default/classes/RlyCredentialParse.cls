/**
 * @description Reads the answers of the Credentials dashboard's checks (build 49): GitHub's token expiry header, GitLab's
 * /personal_access_tokens/self, and a Tooling query of certificates. No callouts and no queries.
 */
public with sharing class RlyCredentialParse {

    /** @description GitHub's token expiry header. */
    public static final String GITHUB_EXPIRY_HEADER = 'github-authentication-token-expiration';

    private static final Integer UNAUTHORIZED = 401;
    private static final String NO_EXPIRY = 'The token answers and has no expiry date.';

    /**
     * @description A GitHub answer: the token's expiry header (absent: no expiry), or why it failed.
     * @param r the row
     * @param res the answer
     * @return the row
     */
    public static RLY_Credential_Status__c gitHub(RLY_Credential_Status__c r, HttpResponse res) {
        if (res.getStatusCode() == UNAUTHORIZED) {
            return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'GitHub refused the token (HTTP 401): it expired or was revoked.');
        }
        if (res.getStatusCode() >= 300) {
            return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'GitHub answered HTTP ' + res.getStatusCode() + '.');
        }
        return RlyCredentialRows.fromExpiry(r, dateOf(header(res, GITHUB_EXPIRY_HEADER)), NO_EXPIRY);
    }

    /**
     * @description A GitLab /personal_access_tokens/self answer: expires_at and active.
     * @param r the row
     * @param res the answer
     * @return the row
     */
    public static RLY_Credential_Status__c gitLab(RLY_Credential_Status__c r, HttpResponse res) {
        if (res.getStatusCode() == UNAUTHORIZED) {
            return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'GitLab refused the token (HTTP 401): it expired or was revoked.');
        }
        if (res.getStatusCode() >= 300) {
            return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'GitLab answered HTTP ' + res.getStatusCode() + '.');
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        RlyCredentialRows.fromExpiry(r, dateOf(text(body.get('expires_at'))), NO_EXPIRY);
        if (body.get('active') == false || body.get('revoked') == true) {
            RlyCredentialRows.mark(r, RlyCredentialRows.FAILED, 'GitLab says the token isn\'t active (revoked or expired).');
        }
        return r;
    }

    /**
     * @description Certificate rows from a Tooling query answer ({"records":[{DeveloperName, MasterLabel, ExpirationDate}]}).
     * @param body the answer
     * @param keyPrefix the rows' key prefix
     * @param o the org the certificates are in, or null for the hub
     * @return the rows
     */
    public static List<RLY_Credential_Status__c> certRows(String body, String keyPrefix, RLY_Org__c o) {
        List<RLY_Credential_Status__c> out = new List<RLY_Credential_Status__c>();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> records = parsed.get('records') instanceof List<Object> ? (List<Object>) parsed.get('records') : new List<Object>();
        String suffix = o == null ? ' (hub)' : ' (' + o.Name + ')';
        for (Object rec : records) {
            Map<String, Object> c = (Map<String, Object>) rec;
            String devName = String.valueOf(c.get('DeveloperName'));
            String label = text(c.get('MasterLabel'));
            RLY_Credential_Status__c r = RlyCredentialRows.row(keyPrefix + devName, RlyCredentialRows.KIND_CERT,
                (label == null ? devName : label) + suffix);
            r.Org__c = o == null ? null : o.Id;
            out.add(RlyCredentialRows.fromExpiry(r, dateOf(text(c.get('ExpirationDate'))), 'No expiry date.'));
        }
        return out;
    }

    /**
     * @description The date at the start of a value such as 2026-12-12, 2026-12-12 10:00:00 UTC or 2026-12-12T00:00:00.000+0000.
     * @param value the value, or null
     * @return the date, or null when there is none
     */
    public static Date dateOf(String value) {
        if (String.isBlank(value) || value.trim().length() < 10) {
            return null;
        }
        try {
            return Date.valueOf(value.trim().left(10));
        } catch (Exception e) {
            return null;
        }
    }

    private static String text(Object o) {
        return o instanceof String ? (String) o : null;
    }

    // A response header, whatever its case.
    private static String header(HttpResponse res, String name) {
        for (String key : res.getHeaderKeys() == null ? new List<String>() : res.getHeaderKeys()) {
            if (key != null && key.equalsIgnoreCase(name)) {
                return res.getHeader(key);
            }
        }
        return null;
    }
}
