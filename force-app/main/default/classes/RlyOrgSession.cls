/**
 * Signs the Release Relay hub in to a registered org and calls that org's APIs.
 *
 * The hub uses the OAuth 2.0 JWT bearer flow, signed in Apex with the hub's own certificate
 * (Auth.JWT, Auth.JWS, Auth.JWTBearerTokenExchange). No Named Credential and no stored secret:
 * the RLY_Org__c record holds only the username, the client id of the org's External Client App,
 * and the name of the hub certificate. The raw access token works for REST, Tooling and the
 * SOAP Metadata API alike.
 *
 * Each org's My Domain must be a Remote Site Setting in the hub, because the token exchange and
 * the API calls are ordinary Apex callouts.
 */
public with sharing class RlyOrgSession {

    public class SignInException extends Exception {}

    public static final String API_VERSION = '63.0';
    private static final Integer TIMEOUT_MS = 30000;

    /** One token per org per transaction. */
    private static final Map<String, String> TOKENS = new Map<String, String>();

    /** Tests replace the JWT exchange, which needs a real certificate. */
    @TestVisible private static String testToken;
    @TestVisible private static String testSignInError;

    /** The org's base URL, without a trailing slash. */
    public static String baseUrl(RLY_Org__c org) {
        return String.isBlank(org.My_Domain__c) ? '' : org.My_Domain__c.trim().removeEnd('/');
    }

    /** login.salesforce.com for production and Developer Edition orgs, test.salesforce.com for sandboxes. */
    public static String audience(RLY_Org__c org) {
        return org.Login_Type__c == 'Sandbox' ? 'https://test.salesforce.com' : 'https://login.salesforce.com';
    }

    /** An access token for the org's integration user. Throws SignInException with a plain-language hint. */
    public static String accessToken(RLY_Org__c org) {
        String key = baseUrl(org) + '|' + org.Username__c;
        if (TOKENS.containsKey(key)) {
            return TOKENS.get(key);
        }
        String token;
        try {
            token = Test.isRunningTest() ? fakeToken() : exchange(org);
        } catch (SignInException e) {
            throw e;
        } catch (Exception e) {
            throw new SignInException(explain(e.getMessage(), org));
        }
        if (String.isBlank(token)) {
            throw new SignInException(explain('No access token was returned.', org));
        }
        TOKENS.put(key, token);
        return token;
    }

    private static String exchange(RLY_Org__c org) {
        Auth.JWT jwt = new Auth.JWT();
        jwt.setSub(org.Username__c.trim());
        jwt.setAud(audience(org));
        jwt.setIss(org.Client_Id__c.trim());
        Auth.JWS jws = new Auth.JWS(jwt, org.Certificate__c.trim());
        Auth.JWTBearerTokenExchange bearer = new Auth.JWTBearerTokenExchange(baseUrl(org) + '/services/oauth2/token', jws);
        String token;
        try {
            token = bearer.getAccessToken();
        } catch (Exception e) {
            HttpResponse res = bearer.getHttpResponse();
            String detail = res == null ? e.getMessage() : e.getMessage() + ' ' + String.valueOf(res.getBody()).left(500);
            throw new SignInException(explain(detail, org));
        }
        return token;
    }

    private static String fakeToken() {
        if (String.isNotBlank(testSignInError)) {
            throw new CalloutException(testSignInError);
        }
        return testToken;
    }

    /** Turns the platform's sign-in errors into the step to fix. */
    @TestVisible
    private static String explain(String raw, RLY_Org__c org) {
        String m = String.isBlank(raw) ? '' : raw;
        String lower = m.toLowerCase();
        String fix;
        if (lower.contains('unauthorized endpoint') || lower.contains('remote site')) {
            fix = 'Add ' + baseUrl(org) + ' as a Remote Site Setting in the hub (Setup > Remote Site Settings).';
        } else if (lower.contains('certificate') || lower.contains('keystore') || lower.contains('key not found')) {
            fix = 'Check Hub certificate: "' + org.Certificate__c + '" must be the API name of a certificate in this hub (Setup > Certificate and Key Management).';
        } else if (lower.contains('client identifier') || lower.contains('invalid_client_id') || lower.contains('invalid_client')) {
            fix = 'Check Client Id: it must be the consumer key of the External Client App in ' + org.Name + '.';
        } else if (lower.contains('hasn\'t approved') || lower.contains('has not approved') || lower.contains('not approved')) {
            fix = 'Pre-authorize the integration user in ' + org.Name + '\'s External Client App: Permitted Users = Admin approved users are pre-authorized, then add the user\'s profile or permission set.';
        } else if (lower.contains('audience')) {
            fix = 'Check Login type: Production for production and Developer Edition orgs, Sandbox for sandboxes.';
        } else if (lower.contains('user') && (lower.contains('inactive') || lower.contains('not found') || lower.contains('invalid'))) {
            fix = 'Check Integration username: it must be an active user in ' + org.Name + '.';
        } else if (lower.contains('invalid_grant')) {
            fix = 'The org refused the login. Check that its External Client App has the JWT bearer flow on, the hub certificate uploaded, and the user pre-authorized.';
        } else {
            fix = 'The hub couldn\'t sign in to ' + org.Name + '.';
        }
        return (fix + (String.isBlank(m) ? '' : ' (' + m.left(400) + ')')).left(2000);
    }

    // ---------- calls ----------

    /** Sends a request to the org with the hub's token. path starts with /services/. */
    public static HttpResponse send(RLY_Org__c org, String method, String path, String body, Map<String, String> headers) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(baseUrl(org) + path);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Authorization', 'Bearer ' + accessToken(org));
        if (headers != null) {
            for (String h : headers.keySet()) {
                req.setHeader(h, headers.get(h));
            }
        }
        if (body != null) {
            req.setBody(body);
        }
        try {
            return new Http().send(req);
        } catch (CalloutException e) {
            throw new SignInException(explain(e.getMessage(), org));
        }
    }

    /** GET returning parsed JSON; throws SignInException on any status but 200. */
    public static Object getJson(RLY_Org__c org, String path) {
        HttpResponse res = send(org, 'GET', path, null, new Map<String, String>{ 'Accept' => 'application/json' });
        if (res.getStatusCode() != 200) {
            throw new SignInException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' for ' + path.substringBefore('?') + ': '
                + String.valueOf(res.getBody()).left(400));
        }
        return JSON.deserializeUntyped(res.getBody());
    }

    /** A SOQL query through REST (tooling = true for the Tooling API). */
    public static String queryPath(String soql, Boolean tooling) {
        return '/services/data/v' + API_VERSION + (tooling ? '/tooling' : '') + '/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
    }
}
