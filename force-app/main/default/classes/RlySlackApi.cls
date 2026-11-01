/**
 * @description Slack Web API calls through the Named Credential RLY_Slack (URL https://slack.com/api; the bot token is
 * on the External Credential RLY_Slack, principal Bot, and never leaves it). A call that Slack refuses throws
 * SlackException with Slack's error code; NOT_SET_UP means the credential isn't usable yet.
 */
public with sharing class RlySlackApi {

    /** @description The Named Credential the calls go through. */
    public static final String NAMED_CREDENTIAL = 'RLY_Slack';
    /** @description Error code for a credential that isn't set up (no token, or no principal access). */
    public static final String NOT_SET_UP = 'not_set_up';

    private static final Integer TIMEOUT_MS = 10000;
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
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new SlackException('HTTP ' + res.getStatusCode() + ' from ' + method);
        }
        if (parsed.get('ok') != true) {
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
}
