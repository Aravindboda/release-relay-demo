/**
 * @description Signs the Release Relay hub in to a registered org and calls that org's APIs.
 *
 * The hub uses the OAuth 2.0 JWT bearer flow, signed in Apex with the hub's own certificate
 * (Auth.JWT, Auth.JWS, Auth.JWTBearerTokenExchange). No Named Credential and no stored secret:
 * the RLY_Org__c record holds the username, the consumer key of the org's External Client App
 * (encrypted in Consumer_Key__c; older records still have it in Client_Id__c) and the name of the
 * hub certificate. The raw access token works for REST, Tooling and the SOAP Metadata API alike.
 *
 * Each org's My Domain must be a Remote Site Setting in the hub, because the token exchange and
 * the API calls are ordinary Apex callouts.
 *
 * A token is reused across transactions through Platform Cache (RlyTokenCache, 15 minutes), so many people reading
 * releases don't each sign in again. A call made with a reused token that the org refuses as expired (HTTP 401, or
 * INVALID_SESSION_ID) drops it, signs in once more and is sent again, once. Without the cache partition the token is
 * kept for the transaction only, as before.
 */
public with sharing class RlyOrgSession {

    /** @description The API version the hub calls, and the newest it knows. */
    public static final String API_VERSION = '63.0';
    private static final Integer TIMEOUT_MS = 30000;
    private static final String KEY_MASK = '••••••••';

    // How many times this transaction signed in (tests check that a kept token saves the sign-in).
    @TestVisible private static Integer signIns = 0;

    // Tests replace the JWT exchange, which needs a real certificate.
    @TestVisible private static String testToken;
    @TestVisible private static String testSignInError;

    /** @description The hub couldn't sign in to the org, or the org couldn't be reached. */
    public class SignInException extends Exception {}

    /** @description One call to the org: method and path, with an optional body and headers. */
    public class Call {
        /** @description GET, POST and so on. */
        public String method;
        /** @description Starts with /services/. */
        public String path;
        /** @description The request body, or null. */
        public String body;
        /** @description Extra request headers. */
        public Map<String, String> headers = new Map<String, String>();

        /**
         * @description A call without a body.
         * @param method HTTP method
         * @param path path on the org, starting with /services/
         */
        public Call(String method, String path) {
            this.method = method;
            this.path = path;
        }

        /**
         * @description Sets the request body.
         * @param body the body
         * @return this call
         */
        public Call withBody(String body) {
            this.body = body;
            return this;
        }

        /**
         * @description Adds a request header.
         * @param name header name
         * @param value header value
         * @return this call
         */
        public Call withHeader(String name, String value) {
            headers.put(name, value);
            return this;
        }

        /**
         * @description Puts a new token where the body carries the old one (a SOAP envelope's session header).
         * @param stale the refused token
         * @param fresh the new token
         */
        public void swapToken(String stale, String fresh) {
            if (body != null) {
                body = body.replace(stale, fresh);
            }
        }

        /**
         * @description The request for this call, without its Authorization header (RlyOrgSession.send adds it).
         * @param base the org's base URL
         * @return the request
         */
        public HttpRequest request(String base) {
            HttpRequest req = new HttpRequest();
            req.setMethod(method);
            req.setEndpoint(base + path);
            req.setTimeout(TIMEOUT_MS);
            for (String h : headers.keySet()) {
                req.setHeader(h, headers.get(h));
            }
            if (body != null) {
                req.setBody(body);
            }
            return req;
        }
    }

    /**
     * @description The org's base URL, without a trailing slash.
     * @param org the registered org
     * @return the My Domain URL
     */
    public static String baseUrl(RLY_Org__c org) {
        return String.isBlank(org.My_Domain__c) ? '' : org.My_Domain__c.trim().removeEnd('/');
    }

    /**
     * @description login.salesforce.com for production and Developer Edition orgs, test.salesforce.com for sandboxes.
     * @param org the registered org
     * @return the JWT audience
     */
    public static String audience(RLY_Org__c org) {
        return org.Login_Type__c == 'Sandbox' ? 'https://test.salesforce.com' : 'https://login.salesforce.com';
    }

    /**
     * @description The consumer key the JWT is issued by: the encrypted Consumer_Key__c, or Client_Id__c
     * for records saved before it existed.
     * @param org the registered org, queried with both key fields
     * @return the consumer key, or null when none is saved
     */
    public static String consumerKey(RLY_Org__c org) {
        if (String.isNotBlank(org.Consumer_Key__c)) {
            return org.Consumer_Key__c.trim();
        }
        return String.isBlank(org.Client_Id__c) ? null : org.Client_Id__c.trim();
    }

    /**
     * @description A masked hint of the saved consumer key (its last four characters), safe to show on the page.
     * @param org the registered org, queried with both key fields
     * @return for example ••••••••Rpu1, or null when no key is saved
     */
    public static String keyHint(RLY_Org__c org) {
        String key = consumerKey(org);
        if (key == null) {
            return null;
        }
        return KEY_MASK + (key.length() > 4 ? key.right(4) : '');
    }

    /**
     * @description An access token for the org's integration user. Throws SignInException with a plain-language hint.
     * @param org the registered org, queried with its sign-in fields
     * @return the access token
     */
    public static String accessToken(RLY_Org__c org) {
        String token = RlyTokenCache.current(org);
        if (token == null) {
            token = signIn(org);
            RlyTokenCache.remember(org, token);
        }
        return token;
    }

    // A new token from the JWT exchange; throws SignInException with a plain-language hint.
    private static String signIn(RLY_Org__c org) {
        String token;
        try {
            token = Test.isRunningTest() ? fakeToken() : exchange(org);
        } catch (SignInException e) {
            throw e;
        } catch (Exception e) {
            throw new SignInException(RlySignInAdvice.explain(e.getMessage(), org));
        }
        if (String.isBlank(token)) {
            throw new SignInException(RlySignInAdvice.explain('No access token was returned.', org));
        }
        signIns++;
        return token;
    }

    // A fresh token when the org refused a reused one as expired (only once per org per transaction); otherwise null.
    private static String renewed(RLY_Org__c org, HttpResponse res) {
        if (!RlyTokenCache.refused(org, res)) {
            return null;
        }
        String token = signIn(org);
        RlyTokenCache.remember(org, token);
        return token;
    }

    private static String exchange(RLY_Org__c org) {
        Auth.JWT jwt = new Auth.JWT();
        jwt.setSub(org.Username__c.trim());
        jwt.setAud(audience(org));
        jwt.setIss(consumerKey(org));
        Auth.JWS jws = new Auth.JWS(jwt, org.Certificate__c.trim());
        Auth.JWTBearerTokenExchange bearer = new Auth.JWTBearerTokenExchange(baseUrl(org) + '/services/oauth2/token', jws);
        String token;
        try {
            token = bearer.getAccessToken();
        } catch (Exception e) {
            HttpResponse res = bearer.getHttpResponse();
            String detail = res == null ? e.getMessage() : e.getMessage() + ' ' + String.valueOf(res.getBody()).left(500);
            throw new SignInException(RlySignInAdvice.explain(detail, org));
        }
        return token;
    }

    private static String fakeToken() {
        if (String.isNotBlank(testSignInError)) {
            throw new CalloutException(testSignInError);
        }
        return testToken;
    }

    // ---------- calls ----------

    /**
     * @description Sends a request to the org with the hub's token. The Authorization header carries a token
     * obtained at runtime from Auth.JWTBearerTokenExchange: orgs are registered at runtime, so a Named
     * Credential per org isn't possible, and that's why the Named Credential suggestion is suppressed here. A reused
     * token the org refuses as expired is renewed and the call sent again, once.
     * @param org the registered org
     * @param c the call to make
     * @return the org's response
     */
    @SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
    public static HttpResponse send(RLY_Org__c org, Call c) {
        String token = accessToken(org);
        HttpRequest req = c.request(baseUrl(org));
        req.setHeader('Authorization', 'Bearer ' + token);
        HttpResponse res = transmit(org, req);
        String fresh = renewed(org, res);
        if (fresh != null) {
            c.swapToken(token, fresh);
            req = c.request(baseUrl(org));
            req.setHeader('Authorization', 'Bearer ' + fresh);
            res = transmit(org, req);
        }
        return res;
    }

    private static HttpResponse transmit(RLY_Org__c org, HttpRequest req) {
        try {
            return new Http().send(req);
        } catch (CalloutException e) {
            throw new SignInException(RlySignInAdvice.explain(e.getMessage(), org));
        }
    }

    /**
     * @description GET returning parsed JSON; throws SignInException on any status but 200.
     * @param org the registered org
     * @param path path on the org
     * @return the parsed body
     */
    public static Object getJson(RLY_Org__c org, String path) {
        HttpResponse res = send(org, new Call('GET', path).withHeader('Accept', 'application/json'));
        if (res.getStatusCode() != 200) {
            throw new SignInException(org.Name + ' answered HTTP ' + res.getStatusCode() + ' for ' + path.substringBefore('?') + ': '
                + String.valueOf(res.getBody()).left(400));
        }
        return JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description A SOQL query through the REST API.
     * @param soql the query
     * @return the path to GET
     */
    public static String queryPath(String soql) {
        return '/services/data/v' + API_VERSION + '/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
    }

    /**
     * @description A SOQL query through the Tooling API.
     * @param soql the query
     * @return the path to GET
     */
    public static String toolingQueryPath(String soql) {
        return '/services/data/v' + API_VERSION + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
    }
}
