/**
 * @description Answers the calls the org check makes (API versions, Organization, SourceMember), as a registered
 * org would. Counts calls without the hub's bearer token, so tests can assert there are none.
 */
@IsTest
public with sharing class RlyOrgCheckMock implements HttpCalloutMock {

    /** @description The Org Id the org answers with. */
    public String orgId = UserInfo.getOrganizationId();
    /** @description Whether the org is a sandbox. */
    public Boolean sandbox = false;
    /** @description Its edition. */
    public String orgType = 'Developer Edition';
    /** @description Whether the Tooling API can query SourceMember. */
    public Boolean tracking = false;
    /** @description The status of the Organization query. */
    public Integer queryStatus = 200;
    /** @description Calls that came without a bearer token. */
    public Integer unsignedCalls = 0;

    /**
     * @description Answers like the org.
     * @param req the request
     * @return the answer
     */
    public HttpResponse respond(HttpRequest req) {
        String auth = req.getHeader('Authorization');
        if (auth == null || !auth.startsWith('Bearer ')) {
            unsignedCalls++;
        }
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
        if (url.endsWith('/services/data/')) {
            answer(res, 200, '[{"version":"62.0"},{"version":"63.0"},{"version":"64.0"}]');
        } else if (url.contains('FROM SourceMember')) {
            answer(res, tracking ? 200 : 400, tracking ? '{"size":0,"records":[]}'
                : '[{"message":"sObject type \'SourceMember\' is not supported.","errorCode":"INVALID_TYPE"}]');
        } else if (url.contains('FROM Organization')) {
            answer(res, queryStatus, queryStatus == 200 ? organization() : '[{"message":"Session expired","errorCode":"INVALID_SESSION_ID"}]');
        } else {
            answer(res, 404, '[]');
        }
        return res;
    }

    private String organization() {
        return '{"records":[{"Id":"' + orgId + '","Name":"Demo","OrganizationType":"' + orgType + '","IsSandbox":' + sandbox + '}]}';
    }

    private void answer(HttpResponse res, Integer status, String body) {
        res.setStatusCode(status);
        res.setBody(body);
    }
}
