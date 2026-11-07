/**
 * @description The Slack reminders call (POST /services/apexrest/rly/slack-due) from the pipeline's hourly schedule
 * (pipeline files v24, job slack-due), signed in as the hub's pipeline user (Release Relay Admin). RlySlackDue decides
 * what is due and answers {done, pass, sent, skipped, reason} (or skipped:true with the reason); the job calls again
 * until done. Always HTTP 200 with JSON, so the job can log the answer.
 */
@RestResource(urlMapping='/rly/slack-due')
global with sharing class RlySlackDueRest {

    /** @description Sends what is due in one pass. */
    @HttpPost
    global static void send() {
        RestRequest req = RestContext.request;
        String body = req == null || req.requestBody == null ? '' : req.requestBody.toString();
        Map<String, Object> out = RlySlackDue.handle(body);
        RestResponse res = RestContext.response;
        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}
