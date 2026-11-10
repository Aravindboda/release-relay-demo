/**
 * @description Slack's Interactivity Request URL: Approve and Reject on a release card, and the reject form. Exposed
 * through a Salesforce Site (/services/apexrest/rly/slack/actions) whose guest user holds RLY_Slack_Site.
 * RlySlackAction checks Slack's signature and the linked approver before anything happens.
 */
@RestResource(urlMapping='/rly/slack/actions')
global with sharing class RlySlackActions {

    /**
     * @description Receives a Slack interaction (form post with a payload field) and answers it.
     */
    @HttpPost
    global static void receive() {
        RlySlackAction.Reply r = RlySlackAction.handle(RestContext.request);
        RestResponse res = RestContext.response;
        res.statusCode = r.status;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(r.body);
    }
}
