/**
 * @description Slack Web API calls through the Named Credential RLY_Slack (URL https://slack.com/api; the bot token is
 * on the External Credential RLY_Slack, principal Bot, and never leaves it). A call that Slack refuses throws
 * SlackException with Slack's error code; NOT_SET_UP means the credential isn't usable yet. When Slack says it is busy
 * (HTTP 429, or the error ratelimited) the call throws RATE_LIMITED and every later call in the same transaction throws it
 * too, without calling Slack: nothing is retried until the next change, which edits the card to its full current state.
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

    private static final Integer TIMEOUT_MS = 10000;
    private static final Integer TOO_MANY_REQUESTS = 429;

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
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new SlackException(NOT_SET_UP + ': ' + e.getMessage());
        }
        return answer(res, method);
    }

    private static Map<String, Object> answer(HttpResponse res, String method) {
        if (res.getStatusCode() == TOO_MANY_REQUESTS) {
            busy = true;
            throw new SlackException(RATE_LIMITED + ' (' + method + ')');
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
