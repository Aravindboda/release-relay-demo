/**
 * @description The pipeline run endpoint (POST /services/apexrest/rly/pipeline-run), called by the Git pipeline's
 * monitor jobs signed in to the hub as its pipeline user (Release Relay Admin) with the hub environment's login, when a
 * run starts and when it ends. RlyRunMonitorInbound checks the body and upserts the run (RLY_Pipeline_Run__c by
 * Run_Id__c); the answer is JSON: 200 when saved, 400 for a bad body, 403 for a caller who isn't an admin.
 */
@RestResource(urlMapping='/rly/pipeline-run')
global with sharing class RlyRunMonitorRest {

    /**
     * @description Saves one run's status (or says why it can't).
     */
    @HttpPost
    global static void post() {
        RestRequest req = RestContext.request;
        String body = req == null || req.requestBody == null ? '' : req.requestBody.toString();
        Map<String, Object> out = RlyRunMonitorInbound.handle(body);
        RestResponse res = RestContext.response;
        res.statusCode = RlyRunMonitorInbound.httpStatus;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}
