/**
 * Tests for the hub release flow (RlyReleaseFlow, RlyReleasesController, the release parts of
 * RlyGitHub and RlyMetadata). Each test runs as an active System Administrator via System.runAs.
 * Records are inserted before Test.startTest, so each test makes one callout sequence followed
 * by its DML (a callout can't follow DML in the same transaction).
 */
@IsTest
private class RlyReleaseFlowTest {

    /** Plays the developer org (Metadata API) and GitHub. */
    private class FlowMock implements HttpCalloutMock {
        public String relName = 'REL-00001';
        public String retrieveState = 'Succeeded'; // Pending, Succeeded, Failed, Problems
        public String runStatus = 'in_progress';
        public String runConclusion = null;
        public Boolean hasRun = true;
        public String prState = 'open';           // open, closed, none
        public Map<String, String> results = new Map<String, String>();
        public List<String> calls = new List<String>();
        public String dispatched;

        public HttpResponse respond(HttpRequest req) {
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            String m = req.getMethod();
            calls.add(m + ' ' + url);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (url.contains('/services/Soap/m/')) {
                res.setHeader('Content-Type', 'text/xml');
                res.setBody(soap(req.getBody()));
                return res;
            }
            res.setHeader('Content-Type', 'application/json');
            if (m == 'GET' && url.contains('/branches/feature/')) {
                return status(res, 404, '{"message":"Branch not found"}');
            }
            if (m == 'GET' && url.contains('/git/ref/heads/')) {
                return status(res, 200, '{"object":{"sha":"abc123"}}');
            }
            if (m == 'POST' && url.endsWith('/git/refs')) {
                return status(res, 201, '{"ref":"refs/heads/feature/x"}');
            }
            if (url.contains('/contents/.relay-inbox/')) {
                return m == 'PUT' ? status(res, 201, '{"content":{}}') : status(res, 404, '{"message":"Not Found"}');
            }
            if (m == 'POST' && url.contains('/dispatches')) {
                dispatched = req.getBody();
                return status(res, 204, '');
            }
            if (m == 'GET' && url.contains('/runs?')) {
                String runs = hasRun ? '{"id":555,"html_url":"https://github.com/acme/release/actions/runs/555","display_title":"Release Relay '
                    + relName + ' (' + mode() + ')","status":"' + runStatus + '","conclusion":'
                    + (runConclusion == null ? 'null' : '"' + runConclusion + '"') + '}' : '';
                return status(res, 200, '{"workflow_runs":[' + runs + ']}');
            }
            if (m == 'POST' && url.contains('/issues/')) {
                return status(res, 201, '{"id":1}');
            }
            if (m == 'PATCH' && url.contains('/pulls/')) {
                return status(res, 200, '{"state":"closed"}');
            }
            if (m == 'GET' && url.contains('/pulls?')) {
                if (prState == 'none') {
                    return status(res, 200, '[]');
                }
                return status(res, 200, '[{"number":42,"html_url":"https://github.com/acme/release/pull/42","state":"'
                    + (prState == 'merged' ? 'closed' : prState) + '","merged_at":' + (prState == 'merged' ? '"2026-10-31T10:00:00Z"' : 'null') + '}]');
            }
            if (m == 'GET' && url.contains('/contents/results/')) {
                String step = url.substringAfterLast('/').substringBefore('.json');
                return results.containsKey(step) ? status(res, 200, results.get(step)) : status(res, 404, '{"message":"Not Found"}');
            }
            return status(res, 404, '{"message":"Not Found"}');
        }

        public String runMode = 'hub';
        private String mode() { return runMode; }

        private HttpResponse status(HttpResponse res, Integer code, String body) {
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }

        private String soap(String body) {
            String head = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
                + ' xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
            String tail = '</soapenv:Body></soapenv:Envelope>';
            if (body.contains('<met:retrieve>')) {
                return head + '<retrieveResponse><result><done>false</done><id>09Sxx0000000001</id><state>Queued</state></result></retrieveResponse>' + tail;
            }
            if (retrieveState == 'Pending') {
                return head + '<checkRetrieveStatusResponse><result><done>false</done><id>09Sxx0000000001</id><status>InProgress</status>'
                    + '<success>false</success></result></checkRetrieveStatusResponse>' + tail;
            }
            if (retrieveState == 'Failed') {
                return head + '<checkRetrieveStatusResponse><result><done>true</done><errorMessage>INVALID_CROSS_REFERENCE_KEY</errorMessage>'
                    + '<id>09Sxx0000000001</id><status>Failed</status><success>false</success></result></checkRetrieveStatusResponse>' + tail;
            }
            String problems = retrieveState == 'Problems'
                ? '<messages><fileName>unpackaged/package.xml</fileName><problem>Entity of type \'ApexClass\' named \'Gone\' cannot be found</problem></messages>' : '';
            return head + '<checkRetrieveStatusResponse><result><done>true</done><id>09Sxx0000000001</id>' + problems
                + '<status>Succeeded</status><success>true</success><zipFile>UEsDBBQAAAAIAA==</zipFile></result></checkRetrieveStatusResponse>' + tail;
        }
    }

    @TestSetup
    static void setup() {
        User admin = admin();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Approver']) {
            if ([SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :admin.Id AND PermissionSetId = :ps.Id].isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id);
            }
        }
    }

    private static User admin() {
        return [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true ORDER BY CreatedDate ASC LIMIT 1];
    }

    private static RLY_Org__c org(String name, String role, String branch, Decimal stageOrder) {
        return new RLY_Org__c(Name = name, Role__c = role, Branch__c = branch, Stage_Order__c = stageOrder,
            Git_Environment__c = branch, My_Domain__c = 'https://' + name.toLowerCase() + '.my.salesforce.com',
            Login_Type__c = 'Production', Username__c = 'relay@' + name.toLowerCase() + '.demo',
            Client_Id__c = '3MVG9demo', Certificate__c = 'release_relay', Status__c = 'Connected');
    }

    /** DEV1 -> SIT -> hub, a checked GitHub connection. Returns DEV1. */
    private static RLY_Org__c route() {
        RLY_Org__c dev = org('DEV1', 'Developer', 'dev1', null);
        RLY_Org__c sit = org('SIT', 'Stage', 'sit', 1);
        insert new List<RLY_Org__c>{ dev, sit, org('PROD', 'Hub', 'prod', null) };
        insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
            Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default',
            Code_Scan__c = true, Status__c = 'Connected');
        return dev;
    }

    /** A release already at a status, with one Apex class and its test. */
    private static RLY_Release__c release(String status, String pendingRun) {
        RLY_Org__c dev = route();
        Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Source_Org__c = dev.Id, Target_Org__c = sitId, Org_Label__c = 'DEV1',
            Target_Branch__c = 'sit', Source_Environment__c = 'dev1', Target_Environment__c = 'sit', Retrieve_Id__c = '09Sxx0000000001',
            Test_Classes__c = 'AccountServiceTest', Scan_Status__c = 'Pending', Validation_Status__c = 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Pending_Run__c = pendingRun,
            Checks_Requested__c = System.now().addMinutes(-1), Component_Count__c = 2);
        insert rel;
        rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
        update new RLY_Release__c(Id = rel.Id, Source_Branch__c = 'feature/' + rel.Name.toLowerCase());
        insert new List<RLY_Release_Item__c>{
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService'),
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountServiceTest')
        };
        return rel;
    }

    private static String result(String step, String body) {
        return '{"request":"x","step":"' + step + '",' + body + ',"finishedAt":"' + System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') + '"}';
    }

    private static RLY_Release__c reload(Id relId) {
        return [SELECT Status__c, Source_Branch__c, Pending_Run__c, PR_Number__c, PR_URL__c, Run_URL__c, Scan_Status__c,
                       Scan_Violations__c, Scan_Blocking__c, Validation_Status__c, Error_Message__c, Approval_Status__c,
                       Deploy_Status__c, Merge_Commit__c, Scan_Bypass_Reason__c, Retrieve_Id__c, Test_Classes__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    private static RlyReleaseFlow.Item item(String type, String name) {
        RlyReleaseFlow.Item i = new RlyReleaseFlow.Item();
        i.type = type;
        i.name = name;
        i.deleted = false;
        i.standard = false;
        return i;
    }

    // ---------- raise ----------

    @IsTest
    static void raiseStartsTheRetrieve() {
        System.runAs(admin()) {
            RLY_Org__c dev = route();
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            Test.setMock(HttpCalloutMock.class, mock);
            RlyReleaseFlow.RaiseRequest req = new RlyReleaseFlow.RaiseRequest();
            req.sourceOrgId = dev.Id;
            req.title = 'Region field';
            req.items = new List<RlyReleaseFlow.Item>{ item('ApexClass', 'AccountService'), item('ApexClass', 'AccountServiceTest'),
                item('CustomField', 'Account.Region__c'), item('ReportFolder', 'Sales') };
            req.testClasses = new List<String>{ 'AccountServiceTest' };
            Test.startTest();
            Id relId = RlyNewReleaseController.raise(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = reload(relId);
            System.assertEquals('Retrieving', rel.Status__c, 'Waiting for the retrieve');
            System.assertEquals('09Sxx0000000001', rel.Retrieve_Id__c, 'Retrieve id saved');
            System.assertEquals('AccountServiceTest', rel.Test_Classes__c, 'Tests saved');
            System.assertEquals(4, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c = :relId], 'Items saved');
        }
    }

    @IsTest
    static void raiseRefusesBadRequests() {
        System.runAs(admin()) {
            RLY_Org__c dev = route();
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
            List<RlyReleaseFlow.RaiseRequest> bad = new List<RlyReleaseFlow.RaiseRequest>();
            for (Integer n = 0; n < 7; n++) {
                RlyReleaseFlow.RaiseRequest r = new RlyReleaseFlow.RaiseRequest();
                r.sourceOrgId = dev.Id;
                r.title = 'Release';
                r.items = new List<RlyReleaseFlow.Item>{ item('Layout', 'Account-Account Layout') };
                r.testClasses = new List<String>();
                bad.add(r);
            }
            bad[0].items = new List<RlyReleaseFlow.Item>();
            bad[1].title = ' ';
            bad[2].items = new List<RlyReleaseFlow.Item>{ item('ApexTrigger', 'AccountTrigger') };
            bad[3].testClasses = new List<String>{ 'NotSelectedTest' };
            bad[4].items[0].deleted = true;
            bad[5].items = new List<RlyReleaseFlow.Item>{ item('Layout', 'A,B') };
            bad[6].sourceOrgId = sitId;
            Integer refused = 0;
            for (RlyReleaseFlow.RaiseRequest r : bad) {
                try {
                    RlyReleaseFlow.raise(r);
                } catch (RlyReleaseFlow.FlowException e) {
                    refused++;
                }
            }
            System.assertEquals(bad.size(), refused, 'Every bad request is refused before any callout');
            Boolean wrapped = false;
            try {
                RlyNewReleaseController.raise(JSON.serialize(bad[2]));
            } catch (AuraHandledException e) {
                wrapped = e.getMessage().contains('test class');
            }
            System.assert(wrapped, 'The test rule message reaches the page');
        }
    }

    // ---------- saved the retrieve ----------

    @IsTest
    static void retrieveDoneStartsThePipeline() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Retrieving', null);
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id, true);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Workflow running', saved.Status__c, 'Pipeline started: ' + saved.Error_Message__c);
            System.assertEquals('feature/' + rel.Name.toLowerCase(), saved.Source_Branch__c, 'Release branch');
            System.assertEquals('hub', saved.Pending_Run__c, 'Hub mode');
            System.assert(mock.dispatched.contains('"mode":"hub"'), 'Hub mode dispatched: ' + mock.dispatched);
            System.assert(mock.dispatched.contains('AccountServiceTest'), 'Tests go in the options');
            System.assert(String.join(mock.calls, '\n').contains('PUT callout:RLY_GitHub/repos/acme/release/contents/.relay-inbox/'), 'Zip committed');
            System.assert(d.running, 'Still running');
        }
    }

    @IsTest
    static void retrieveStillRunning() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Retrieving', null);
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.retrieveState = 'Pending';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Retrieving', reload(rel.Id).Status__c, 'Keeps waiting');
        }
    }

    @IsTest
    static void retrieveProblemsFailTheRelease() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Retrieving', null);
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.retrieveState = 'Problems';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Failed', saved.Status__c, 'A missing component fails it');
            System.assert(saved.Error_Message__c.contains('Gone'), 'Names the component: ' + saved.Error_Message__c);
        }
    }

    @IsTest
    static void retrieveErrorFailsTheRelease() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Retrieving', null);
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.retrieveState = 'Failed';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Failed', saved.Status__c, 'Retrieve failed');
            System.assert(saved.Error_Message__c.contains('INVALID_CROSS_REFERENCE_KEY'), saved.Error_Message__c);
        }
    }

    // ---------- checks ----------

    @IsTest
    static void cleanChecksAreReadyForApproval() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Workflow running', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.results.put('scan', result('scan', '"status":"Passed","total":2,"blocking":0,"thresholdLabel":"High"'));
            mock.results.put('validate', result('validate', '"status":"Passed","testLevel":"RunSpecifiedTests","testsRun":3'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Low findings don\'t block: ' + saved.Error_Message__c);
            System.assertEquals(42, saved.PR_Number__c, 'Pull request read');
            System.assertEquals(2, saved.Scan_Violations__c, 'Findings counted');
            System.assert(saved.Run_URL__c.contains('/runs/555'), 'Run linked');
        }
    }

    @IsTest
    static void blockingScanCanBeBypassed() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.results.put('scan', result('scan', '"status":"Failed","total":3,"blocking":1'));
            mock.results.put('validate', result('validate', '"status":"Passed"'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Checks failed', reload(rel.Id).Status__c, 'A blocking finding stops it');
            Boolean needsReason = false;
            try {
                RlyReleasesController.bypassScan(rel.Id, 'ok');
            } catch (AuraHandledException e) {
                needsReason = true;
            }
            System.assert(needsReason, 'A real reason is required');
            RlyReleasesController.bypassScan(rel.Id, 'False positive: the SOQL is bound and limited.');
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Bypassed', saved.Scan_Status__c, 'Bypassed');
            System.assertEquals('Ready for approval', saved.Status__c, 'Validation passed, so it can be approved');
        }
    }

    @IsTest
    static void failedValidationCantBeBypassed() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.results.put('scan', result('scan', '"status":"Passed","total":0,"blocking":0'));
            mock.results.put('validate', result('validate', '"status":"Failed","message":"1 test failure(s)"'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Checks failed', reload(rel.Id).Status__c, 'Failed validation stops it');
            Boolean refused = false;
            try {
                RlyReleaseFlow.bypassScan(rel.Id, 'Trying to skip the validation');
            } catch (RlyReleaseFlow.FlowException e) {
                refused = true;
            }
            System.assert(refused, 'Only a failed scan can be bypassed');
        }
    }

    @IsTest
    static void pipelineFailureWithoutPullRequestFails() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Workflow running', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.prState = 'none';
            mock.runStatus = 'completed';
            mock.runConclusion = 'failure';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Failed', reload(rel.Id).Status__c, 'The raise failed');
        }
    }

    @IsTest
    static void finishedRunWithoutResultsIsAnError() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.runStatus = 'completed';
            mock.runConclusion = 'failure';
            // A result from an earlier run is ignored.
            mock.results.put('scan', '{"status":"Passed","finishedAt":"2020-01-01T00:00:00.000Z"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Error', saved.Scan_Status__c, 'Old result ignored');
            System.assertEquals('Checks failed', saved.Status__c, 'Not stuck');
        }
    }

    @IsTest
    static void closedPullRequestClosesTheRelease() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.prState = 'closed';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Closed', reload(rel.Id).Status__c, 'Closed in GitHub');
        }
    }

    // ---------- approve, reject, check again ----------

    @IsTest
    static void approveStartsMergeAndDeploy() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            FlowMock mock = new FlowMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.approve(rel.Id, 'Looks good');
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'Deploying');
            System.assertEquals('Approved', saved.Approval_Status__c, 'Approved');
            System.assertEquals('merge', saved.Pending_Run__c, 'Merge run');
            System.assert(mock.dispatched.contains('"mode":"merge"') && mock.dispatched.contains('"target_environment":"sit"'), mock.dispatched);
            System.assert(d.isApprover, 'Approver');
        }
    }

    @IsTest
    static void rejectNeedsAComment() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Ready for approval', 'hub');
            Boolean refused = false;
            try {
                RlyReleasesController.reject(rel.Id, '');
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'A comment is required');
            RlyReleasesController.reject(rel.Id, 'Split the layout change out');
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Rejected', saved.Status__c, 'Rejected');
            System.assertEquals('Rejected', saved.Approval_Status__c, 'Approval rejected');
        }
    }

    @IsTest
    static void rejectClosesThePullRequest() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            FlowMock mock = new FlowMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.reject(rel.Id, 'Validation failed: fix the test and raise again');
            Test.stopTest();
            String calls = String.join(mock.calls, '\n');
            System.assert(calls.contains('PATCH callout:RLY_GitHub/repos/acme/release/pulls/42'), 'Pull request closed: ' + calls);
            System.assert(calls.contains('/issues/42/comments'), 'Reason commented');
            System.assertEquals(null, reload(rel.Id).Error_Message__c, 'No error');
        }
    }

    @IsTest
    static void checkAgainRerunsTheChecks() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Failed', Validation_Status__c = 'Passed');
            FlowMock mock = new FlowMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.checkAgain(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Validating', saved.Status__c, 'Checking again');
            System.assertEquals('Pending', saved.Scan_Status__c, 'Scan pending');
            System.assert(mock.dispatched.contains('"mode":"check"'), mock.dispatched);
        }
    }

    @IsTest
    static void refusesActionsAtTheWrongTime() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            Integer refused = 0;
            try { RlyReleasesController.approve(rel.Id, null); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.checkAgain(rel.Id); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.bypassScan(rel.Id, 'A long enough reason'); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.getRelease(null, false); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Nothing happens out of order');
        }
    }

    // ---------- deploy ----------

    @IsTest
    static void deployedAfterMerge() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Deploying', 'merge');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.runMode = 'merge';
            mock.results.put('merge', result('merge', '"status":"Merged","sha":"0123456789abcdef0123456789abcdef01234567"'));
            mock.results.put('deploy', result('deploy', '"status":"Deployed","testsRun":3'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Deployed', saved.Status__c, 'Deployed: ' + saved.Error_Message__c);
            System.assertEquals('0123456789abcdef0123456789abcdef01234567', saved.Merge_Commit__c, 'Merge commit');
        }
    }

    @IsTest
    static void deployFailureIsShown() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Deploying', 'merge');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.runMode = 'merge';
            mock.results.put('merge', result('merge', '"status":"Merged","sha":"0123456789abcdef0123456789abcdef01234567"'));
            mock.results.put('deploy', result('deploy', '"status":"Failed","message":"1 component error(s)"'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Deploy failed', saved.Status__c, 'Deploy failed');
            System.assertEquals('1 component error(s)', saved.Error_Message__c, 'Reason shown');
        }
    }

    @IsTest
    static void mergeFailureIsShown() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Deploying', 'merge');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.runMode = 'merge';
            mock.results.put('merge', result('merge', '"status":"Failed","message":"Conflicts"'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Deploy failed', reload(rel.Id).Status__c, 'Merge failed');
        }
    }

    @IsTest
    static void runFailedBeforeDeployResult() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Deploying', 'merge');
            RlyOrgSession.testToken = '00Dxx!token';
            FlowMock mock = new FlowMock();
            mock.relName = rel.Name;
            mock.runMode = 'merge';
            mock.runStatus = 'completed';
            mock.runConclusion = 'failure';
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Deploy failed', reload(rel.Id).Status__c, 'Run failed');
        }
    }

    @IsTest
    static void unreachableGitKeepsTheStatus() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Validating', 'hub');
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Provider__c = 'GitLab', Repository__c = 'acme/release');
            Test.startTest();
            RlyReleaseFlow.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = reload(rel.Id);
            System.assertEquals('Validating', saved.Status__c, 'Unchanged');
            System.assert(saved.Error_Message__c.contains('GitHub'), 'Says what is supported: ' + saved.Error_Message__c);
        }
    }

    // ---------- lists ----------

    @IsTest
    static void listsReleases() {
        System.runAs(admin()) {
            RLY_Release__c rel = release('Ready for approval', 'hub');
            System.assertEquals(1, RlyReleasesController.listReleases('mine').size(), 'Mine');
            System.assertEquals(1, RlyReleasesController.listReleases('all').size(), 'All');
            System.assertEquals(1, RlyReleasesController.listReleases('approvals').size(), 'Waiting for approval');
            System.assert(RlyReleasesController.isApprover(), 'Approver');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id, false);
            System.assertEquals(2, d.items.size(), 'Items');
            System.assertEquals('DEV1', d.sourceName, 'Source');
            System.assert(!d.running, 'Not running');
        }
    }
}
