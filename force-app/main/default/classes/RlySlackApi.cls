/**
 * @description Slack Web API calls through the Named Credential RLY_Slack (URL https://slack.com/api; the bot token is
 * on the External Credential RLY_Slack, principal Bot, and never leaves it). A call that Slack refuses throws
 * SlackException with Slack's error code; NOT_SET_UP means the credential isn't usable yet. When Slack says it is busy
 * (HTTP 429, or the error ratelimited) the call throws RATE_LIMITED and every later call in the same transaction throws it
 * too, without calling Slack: nothing is retried until the next change, which edits the card to its full current state.
 * Read methods (users.lookupByEmail, users.info) go as GET with query parameters (Slack takes no JSON body for them).
 * Every answer keeps the bot token's scopes (x-oauth-scopes header) and a 429's Retry-After for the caller.
 */
public with sharing class RlySlackApi {

    /** @description The Named Credential the calls go through. */
    public static final String NAMED_CREDENTIAL = 'RLY_Slack';
    /** @description Error code for a credential that isn't set up (no token, or no principal access). */
    public static final String NOT_SET_UP = 'not_set_up';

    /** @description Error code for Slack refusing calls for a while (HTTP 429 or ratelimited). */
    public static final String RATE_LIMITED = 'ratelimited';
    /** @description The result kept for Last_Result__c when Slack is busy. */
    public static final String BUSY_RESULT = 'Slack is busy; the card catches up on the next change.';

    /** @description Seconds to wait when Slack is busy and gives no Retry-After. */
    public static final Integer DEFAULT_RETRY_SECONDS = 30;

    private static final Integer TIMEOUT_MS = 10000;
    private static final Integer TOO_MANY_REQUESTS = 429;
    // The bot token's scopes (x-oauth-scopes) from the last answer, and Slack's Retry-After from the last 429.
    @TestVisible private static String lastScopes;
    @TestVisible private static Integer lastRetryAfter;

    // Slack said it is busy in this transaction: no more calls until the next one.
    @TestVisible private static Boolean busy = false;
    private static final Set<String> TOKEN_ERRORS = new Set<String>{ NOT_SET_UP, 'not_authed', 'invalid_auth', 'account_inactive', 'token_revoked' };

    /** @description Slack refused a call; the message starts with Slack's error code. */
    public class SlackException extends Exception {}

    /**
     * @description Calls a Web API method with a JSON body.
     * @param method for example chat.postMessage
     * @param body the arguments
     * @return Slack's answer (ok is true)
     */
    public static Map<String, Object> call(String method, Map<String, Object> body) {
        if (busy) {
            throw new SlackException(RATE_LIMITED + ' (' + method + ': not sent, Slack is busy)');
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/' + method);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json; charset=utf-8');
        req.setBody(JSON.serialize(body));
        return send(req, method);
    }

    /**
     * @description Calls a read method (GET with query parameters), for example users.lookupByEmail.
     * @param method the Web API method
     * @param params the arguments
     * @return Slack's answer (ok is true)
     */
    public static Map<String, Object> read(String method, Map<String, String> params) {
        if (busy) {
            throw new SlackException(RATE_LIMITED + ' (' + method + ': not sent, Slack is busy)');
        }
        List<String> query = new List<String>();
        for (String key : params.keySet()) {
            query.add(key + '=' + EncodingUtil.urlEncode(params.get(key) == null ? '' : params.get(key), 'UTF-8'));
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/' + method + (query.isEmpty() ? '' : '?' + String.join(query, '&')));
        req.setTimeout(TIMEOUT_MS);
        return send(req, method);
    }

    /**
     * @description The bot token's scopes as Slack sent them on the last answer (x-oauth-scopes), or null.
     * @return the scopes, comma separated
     */
    public static String scopes() {
        return lastScopes;
    }

    /**
     * @description How long Slack asked to wait after the last 429 (Retry-After), in seconds.
     * @return the seconds (DEFAULT_RETRY_SECONDS when Slack gave none)
     */
    public static Integer retryAfterSeconds() {
        return lastRetryAfter == null || lastRetryAfter < 1 ? DEFAULT_RETRY_SECONDS : lastRetryAfter;
    }

    private static Map<String, Object> send(HttpRequest req, String method) {
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new SlackException(NOT_SET_UP + ': ' + e.getMessage());
        }
        return answer(res, method);
    }

    private static Map<String, Object> answer(HttpResponse res, String method) {
        String scopeHeader = header(res, 'x-oauth-scopes');
        lastScopes = scopeHeader == null ? lastScopes : scopeHeader;
        if (res.getStatusCode() == TOO_MANY_REQUESTS) {
            tooMany(res, method);
        }
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new SlackException('HTTP ' + res.getStatusCode() + ' from ' + method);
        }
        if (parsed.get('ok') != true) {
            busy = busy || parsed.get('error') == RATE_LIMITED;
            throw new SlackException(String.valueOf(parsed.get('error')) + ' (' + method + ')');
        }
        return parsed;
    }

    // HTTP 429: no more calls in this transaction; keep Slack's Retry-After for the page.
    private static void tooMany(HttpResponse res, String method) {
        busy = true;
        String wait = header(res, 'Retry-After');
        lastRetryAfter = wait != null && wait.trim().isNumeric() ? Integer.valueOf(wait.trim()) : null;
        throw new SlackException(RATE_LIMITED + ' (' + method + ')');
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

    /**
     * @description Slack's error code of a failure (the first word of its message), lower case.
     * @param e the failure
     * @return the code, or an empty string
     */
    public static String code(Exception e) {
        String m = e == null || e.getMessage() == null ? '' : e.getMessage();
        return m.substringBefore(' ').removeEnd(':').toLowerCase();
    }

    /**
     * @description Whether a failure means the Slack credential isn't set up (or its token doesn't work).
     * @param e the failure
     * @return true for a missing or refused token
     */
    public static Boolean isNotSetUp(Exception e) {
        String code = e.getMessage() == null ? '' : e.getMessage().substringBefore(' ').removeEnd(':');
        return TOKEN_ERRORS.contains(code);
    }

    /**
     * @description Whether a failure means Slack is busy (rate limited): the caller records BUSY_RESULT and doesn't retry.
     * @param e the failure
     * @return true when Slack is rate limiting the hub
     */
    public static Boolean isRateLimited(Exception e) {
        return e != null && e.getMessage() != null && e.getMessage().startsWith(RATE_LIMITED + ' ');
    }
}
