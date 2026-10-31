/**
 * Tests for the hub's registered orgs: saving, validation, the sign-in check (identity, API version,
 * source tracking, refresh detection) and the plain-language sign-in errors.
 * Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyOrgControllerTest {

    /** Answers the calls the check makes, as the registered org would. */
    private class OrgMock implements HttpCalloutMock {
        public String orgId = '00Dxx0000000001EAA';
        public Boolean sandbox = false;
        public String orgType = 'Developer Edition';
        public Boolean tracking = false;
        public Integer queryStatus = 200;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            System.assert(req.getHeader('Authorization').startsWith('Bearer '), 'Every call carries the hub token');
            if (url.endsWith('/services/data/')) {
                res.setStatusCode(200);
                res.setBody('[{"version":"62.0"},{"version":"63.0"},{"version":"64.0"}]');
            } else if (url.contains('FROM SourceMember')) {
                res.setStatusCode(tracking ? 200 : 400);
                res.setBody(tracking ? '{"size":0,"records":[]}'
                    : '[{"message":"sObject type \'SourceMember\' is not supported.","errorCode":"INVALID_TYPE"}]');
            } else if (url.contains('FROM Organization')) {
                res.setStatusCode(queryStatus);
                res.setBody(queryStatus == 200
                    ? '{"records":[{"Id":"' + orgId + '","Name":"Demo","OrganizationType":"' + orgType + '","IsSandbox":' + sandbox + '}]}'
                    : '[{"message":"Session expired","errorCode":"INVALID_SESSION_ID"}]');
            } else {
                res.setStatusCode(404);
                res.setBody('[]');
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        User admin = admin();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Admin']) {
            if ([SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :admin.Id AND PermissionSetId = :ps.Id].isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id);
            }
        }
    }

    private static User admin() {
        return [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true
                ORDER BY CreatedDate ASC LIMIT 1];
    }

    private static Map<String, Object> input(String name, String loginType) {
        return new Map<String, Object>{
            'Name' => name, 'Role__c' => 'Developer', 'My_Domain__c' => 'https://demo-dev-ed.develop.my.salesforce.com/',
            'Login_Type__c' => loginType, 'Username__c' => 'relay@demo.dev', 'Client_Id__c' => '3MVG9demo',
            'Certificate__c' => 'release_relay', 'Git_Environment__c' => 'dev1', 'Branch__c' => 'dev1'
        };
    }

    private static Id register(String name, String loginType) {
        return RlyOrgController.saveOrg(JSON.serialize(input(name, loginType)));
    }

    @IsTest
    static void developerEditionWithoutTracking() {
        System.runAs(admin()) {
            RlyOrgSession.testToken = '00Dxx!token';
            Id orgId = register('DEV1', 'Production');
            RLY_Org__c saved = [SELECT Status__c, My_Domain__c, Source_Tracking__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assertEquals('Not checked', saved.Status__c, 'New orgs wait for their first check');
            System.assertEquals('https://demo-dev-ed.develop.my.salesforce.com', saved.My_Domain__c, 'Trailing slash removed');

            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals('Connected', checked.Status__c, 'Signed in: ' + checked.Status_Message__c);
            System.assertEquals('00Dxx0000000001EAA', checked.Org_Id__c, 'Org Id read');
            System.assertEquals('64.0', checked.Api_Version__c, 'Newest API version');
            System.assertEquals('Not available', checked.Source_Tracking__c, 'No source tracking in Developer Edition');
            System.assertEquals(RlyOrgController.TRACKING_HINT_NONE, checked.Status_Message__c, 'Says the Metadata API is used');

            RlyOrgController.HubInfo hub = RlyOrgController.getOrgs();
            System.assertEquals(true, hub.isAdmin, 'Admin');
            System.assertEquals(1, hub.orgs.size(), 'Listed');
            System.assert(String.isNotBlank(hub.hubDomain), 'Hub domain shown for the Remote Site Setting');
        }
    }

    @IsTest
    static void sandboxWithTrackingThenRefreshed() {
        System.runAs(admin()) {
            RlyOrgSession.testToken = '00Dxx!token';
            Id orgId = register('SIT', 'Sandbox');
            Id refreshedId = register('SIT2', 'Sandbox');
            // SIT2 was checked before its last refresh: the Org Id on file is the old one.
            update new RLY_Org__c(Id = refreshedId, Org_Id__c = '00Dxx0000000009EAA', Status__c = 'Connected');
            OrgMock mock = new OrgMock();
            mock.sandbox = true;
            mock.tracking = true;
            mock.orgType = 'Enterprise Edition';
            Test.setMock(HttpCalloutMock.class, mock);
            RLY_Org__c sit = [SELECT Id, Name, My_Domain__c, Login_Type__c, Username__c, Client_Id__c,
                Certificate__c, Org_Id__c FROM RLY_Org__c WHERE Id = :orgId];
            Test.startTest();
            // check() makes callouts only; checkOrg() then calls out and saves once, so no callout follows a save.
            RLY_Org__c firstCheck = RlyOrgController.check(sit);
            RLY_Org__c secondCheck = RlyOrgController.checkOrg(refreshedId);
            Test.stopTest();
            System.assertEquals('Connected', firstCheck.Status__c, 'Signed in: ' + firstCheck.Status_Message__c);
            System.assertEquals('Available', firstCheck.Source_Tracking__c, 'Source tracking found');
            System.assertEquals(null, firstCheck.Status_Message__c, 'Nothing to recommend');
            System.assertEquals(true, firstCheck.Is_Sandbox__c, 'Sandbox');
            System.assertEquals('Connected', secondCheck.Status__c, 'Still connected after a refresh');
            System.assertEquals('00Dxx0000000001EAA', secondCheck.Org_Id__c, 'New Org Id saved');
            System.assert(secondCheck.Status_Message__c.contains('refreshed'), secondCheck.Status_Message__c);
        }
    }

    @IsTest
    static void sandboxWithoutTrackingGetsRecommendation() {
        System.runAs(admin()) {
            RlyOrgSession.testToken = '00Dxx!token';
            Id orgId = register('UAT', 'Production');
            OrgMock mock = new OrgMock();
            mock.sandbox = true;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assert(checked.Status_Message__c.contains(RlyOrgController.TRACKING_HINT_SANDBOX), 'Recommends source tracking');
            System.assert(checked.Status_Message__c.contains('set Login type to Sandbox'), 'Flags the wrong login type');
        }
    }

    @IsTest
    static void signInFailuresExplainTheFix() {
        System.runAs(admin()) {
            RlyOrgSession.testSignInError = 'invalid_grant: user hasn\'t approved this consumer';
            Id orgId = register('DEV2', 'Production');
            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals('Failed', checked.Status__c, 'Sign-in failed');
            System.assert(checked.Status_Message__c.contains('Pre-authorize'), checked.Status_Message__c);

            RLY_Org__c o = new RLY_Org__c(Name = 'DEV2', My_Domain__c = 'https://demo.my.salesforce.com', Certificate__c = 'release_relay');
            Map<String, String> cases = new Map<String, String>{
                'Unauthorized endpoint, please check Setup->Security->Remote site settings' => 'Remote Site Setting',
                'Certificate does not exist' => 'Hub certificate',
                'invalid_client_id: client identifier invalid' => 'Client Id',
                'invalid_grant: audience is invalid' => 'Login type',
                'invalid_grant: user is inactive' => 'Integration username',
                'invalid_grant: something else' => 'JWT bearer flow',
                'Read timed out' => 'couldn\'t sign in'
            };
            for (String raw : cases.keySet()) {
                String fix = RlyOrgSession.explain(raw, o);
                System.assert(fix.contains(cases.get(raw)), raw + ' -> ' + fix);
            }
            System.assertEquals('https://test.salesforce.com', RlyOrgSession.audience(new RLY_Org__c(Login_Type__c = 'Sandbox')), 'Sandbox audience');
            System.assertEquals('https://login.salesforce.com', RlyOrgSession.audience(new RLY_Org__c(Login_Type__c = 'Production')), 'Production audience');
        }
    }

    @IsTest
    static void apiErrorsMarkTheOrgFailed() {
        System.runAs(admin()) {
            RlyOrgSession.testToken = '00Dxx!token';
            Id orgId = register('DEV3', 'Production');
            OrgMock mock = new OrgMock();
            mock.queryStatus = 401;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals('Failed', checked.Status__c, 'API error recorded');
            System.assert(checked.Status_Message__c.contains('401'), checked.Status_Message__c);
        }
    }

    /** Fails every call, as when the org can't be reached. */
    private class DownMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Unauthorized endpoint, please check Setup->Security->Remote site settings');
        }
    }

    @IsTest
    static void sessionEdgeCases() {
        System.runAs(admin()) {
            RLY_Org__c org = new RLY_Org__c(Name = 'DEV9', My_Domain__c = 'https://demo.my.salesforce.com/',
                Username__c = 'relay@demo.dev', Certificate__c = 'release_relay', Login_Type__c = 'Production');
            System.assertEquals('https://demo.my.salesforce.com', RlyOrgSession.baseUrl(org), 'Trailing slash removed');

            Boolean noToken = false;
            try {
                RlyOrgSession.accessToken(org);
            } catch (RlyOrgSession.SignInException e) {
                noToken = e.getMessage().contains('No access token');
            }
            System.assert(noToken, 'A blank token is refused with a reason');

            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new DownMock());
            Test.startTest();
            Boolean unreachable = false;
            try {
                RlyOrgSession.send(org, 'POST', '/services/data/v63.0/sobjects/Account', '{}', null);
            } catch (RlyOrgSession.SignInException e) {
                unreachable = e.getMessage().contains('Remote Site Setting');
            }
            Test.stopTest();
            System.assert(unreachable, 'An unreachable org points to the Remote Site Setting');
            System.assert(RlyOrgSession.queryPath('SELECT Id FROM Account', true).startsWith('/services/data/v63.0/tooling/query/'), 'Tooling path');
        }
    }

    @IsTest
    static void refusesBadInputAndDuplicates() {
        System.runAs(admin()) {
            List<String> problems = RlyOrgController.validate(new RLY_Org__c(
                Name = 'Bad/Name', Role__c = 'Other', My_Domain__c = 'http://example.com', Login_Type__c = 'Test',
                Username__c = 'nobody', Client_Id__c = 'has space', Certificate__c = '1bad', Git_Environment__c = 'bad$env', Branch__c = 'bad branch'));
            System.assertEquals(9, problems.size(), 'Every field checked: ' + problems);

            register('DEV1', 'Production');
            Boolean duplicate = false;
            try {
                register('DEV1', 'Production');
            } catch (AuraHandledException e) {
                duplicate = true;
            }
            System.assert(duplicate, 'Org names are unique');

            Boolean unreadable = false;
            try {
                RlyOrgController.saveOrg('not json');
            } catch (AuraHandledException e) {
                unreadable = true;
            }
            System.assert(unreadable, 'Bad JSON refused');

            Id orgId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1'].Id;
            update new RLY_Org__c(Id = orgId, Org_Id__c = '00Dxx0000000001EAA', Status__c = 'Connected');
            Map<String, Object> changed = input('DEV1', 'Production');
            changed.put('Id', orgId);
            changed.put('Username__c', 'other@demo.dev');
            RlyOrgController.saveOrg(JSON.serialize(changed));
            RLY_Org__c saved = [SELECT Username__c, Org_Id__c, Status__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assertEquals('other@demo.dev', saved.Username__c, 'Updated in place');
            System.assertEquals(null, saved.Org_Id__c, 'A new user forgets the old Org Id, so it isn\'t taken for a refresh');
            System.assertEquals('Not checked', saved.Status__c, 'Needs a new check');
        }
    }
}
