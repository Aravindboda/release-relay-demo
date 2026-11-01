/**
 * @description The nightly archive endpoint (POST /services/apexrest/rly/archive), called by the Git pipeline's
 * scheduled job signed in as the hub's pipeline user (RLY_Admin). One pass per call; RlyArchiveNightly does the work
 * and answers JSON. An unexpected error answers 500 (Salesforce's error body), which fails the job's call.
 */
@RestResource(urlMapping='/rly/archive')
global with sharing class RlyArchiveRest {

    /**
     * @description Makes one archive pass (or says why the call is skipped).
     */
    @HttpPost
    global static void archive() {
        RestRequest req = RestContext.request;
        String body = req == null || req.requestBody == null ? '' : req.requestBody.toString();
        Map<String, Object> out = RlyArchiveNightly.handle(body);
        RestResponse res = RestContext.response;
        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}
