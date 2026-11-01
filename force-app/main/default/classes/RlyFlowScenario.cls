/**
 * @description A release-flow scenario for the tests: how the developer org (Metadata API) and GitHub behave.
 * Set the fields, then build() the table of answers (RlyHttpMock).
 */
@IsTest
public with sharing class RlyFlowScenario {

    /** @description The retrieve id the developer org hands out. */
    public static final String RETRIEVE_ID = RlyTestData.fakeId('09S', 1);

    /** @description The release name the pipeline runs are titled with. */
    public String relName = 'REL-00001';
    /** @description Pending, Succeeded, Failed or Problems. */
    public String retrieveState = 'Succeeded';
    /** @description queued, in_progress or completed. */
    public String runStatus = 'in_progress';
    /** @description The run's conclusion, or null. */
    public String runConclusion;
    /** @description The run title's mode: hub, check or merge. */
    public String runMode = 'hub';
    /** @description open, closed, merged or none. */
    public String prState = 'open';
    /** @description Result files by step (scan, validate, merge, deploy). */
    public Map<String, String> results = new Map<String, String>();

    private static final String SOAP_HEAD = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope '
        + 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
    private static final String SOAP_TAIL = '</soapenv:Body></soapenv:Envelope>';

    /**
     * @description A scenario for a release.
     * @param rel the release (its Name titles the runs)
     * @return the scenario
     */
    public static RlyFlowScenario forRelease(RLY_Release__c rel) {
        RlyFlowScenario s = new RlyFlowScenario();
        s.relName = rel.Name;
        return s;
    }

    /**
     * @description The table of answers, in the order they're tried.
     * @return the mock
     */
    public RlyHttpMock build() {
        RlyHttpMock mock = new RlyHttpMock()
            .match('POST', '/services/Soap/m/').ifBodyHas('<met:retrieve>').reply(200, SOAP_HEAD + '<retrieveResponse><result><done>false</done><id>'
                + RETRIEVE_ID + '</id><state>Queued</state></result></retrieveResponse>' + SOAP_TAIL)
            .match('POST', '/services/Soap/m/').reply(200, SOAP_HEAD + retrieveStatus() + SOAP_TAIL)
            .match('GET', '/branches/feature/').reply(404, '{"message":"Branch not found"}')
            .match('GET', '/git/ref/heads/').reply(200, '{"object":{"sha":"abc123"}}')
            .match('POST', '/git/refs').reply(201, '{"ref":"refs/heads/feature/x"}')
            .match('PUT', '/contents/.relay-inbox/').reply(201, '{"content":{}}')
            .match('POST', '/dispatches').reply(204, '')
            .match('GET', '/runs?').reply(200, '{"workflow_runs":[' + runJson() + ']}')
            .match('POST', '/issues/').reply(201, '{"id":1}')
            .match('PATCH', '/pulls/').reply(200, '{"state":"closed"}')
            .match('GET', '/pulls?').reply(200, pullsJson());
        for (String step : results.keySet()) {
            mock.match('GET', '/' + step + '.json').reply(200, results.get(step));
        }
        return mock;
    }

    private String retrieveStatus() {
        if (retrieveState == 'Pending') {
            return '<checkRetrieveStatusResponse><result><done>false</done><id>' + RETRIEVE_ID + '</id><status>InProgress</status>'
                + '<success>false</success></result></checkRetrieveStatusResponse>';
        }
        if (retrieveState == 'Failed') {
            return '<checkRetrieveStatusResponse><result><done>true</done><errorMessage>INVALID_CROSS_REFERENCE_KEY</errorMessage>'
                + '<id>' + RETRIEVE_ID + '</id><status>Failed</status><success>false</success></result></checkRetrieveStatusResponse>';
        }
        String problems = retrieveState == 'Problems'
            ? '<messages><fileName>unpackaged/package.xml</fileName><problem>Entity of type \'ApexClass\' named \'Gone\' cannot be found</problem></messages>' : '';
        return '<checkRetrieveStatusResponse><result><done>true</done><id>' + RETRIEVE_ID + '</id>' + problems
            + '<status>Succeeded</status><success>true</success><zipFile>UEsDBBQAAAAIAA==</zipFile></result></checkRetrieveStatusResponse>';
    }

    private String runJson() {
        return '{"id":555,"html_url":"https://github.com/acme/release/actions/runs/555","display_title":"Release Relay '
            + relName + ' (' + runMode + ')","status":"' + runStatus + '","conclusion":'
            + (runConclusion == null ? 'null' : '"' + runConclusion + '"') + '}';
    }

    private String pullsJson() {
        if (prState == 'none') {
            return '[]';
        }
        Boolean merged = prState == 'merged';
        return '[{"number":42,"html_url":"https://github.com/acme/release/pull/42","state":"'
            + (merged ? 'closed' : prState) + '","merged_at":' + (merged ? '"2026-10-31T10:00:00Z"' : 'null') + '}]';
    }
}
