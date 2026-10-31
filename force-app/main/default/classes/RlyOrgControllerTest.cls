/**
 * @description Tests for the hub's registered orgs: saving, validation and the sign-in check (identity, API version,
 * source tracking, refresh detection) through RlyOrgController, RlyOrgValidator and RlyOrgCheck.
 * Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it.
 */
@IsTest
private class RlyOrgControllerTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Map<String, Object> input(String name, String loginType) {
        return new Map<String, Object>{
            'Name' => name, 'Role__c' => 'Developer', 'My_Domain__c' => 'https://demo-dev-ed.develop.my.salesforce.com/',
            'Login_Type__c' => loginType, 'Username__c' => 'relay@demo.dev', 'Consumer_Key__c' => RlyTestData.CONSUMER_KEY,
            'Certificate__c' => 'release_relay', 'Git_Environment__c' => 'dev1', 'Branch__c' => 'dev1'
        };
    }

    private static Id register(String name, String loginType) {
        return RlyOrgController.saveOrg(JSON.serialize(input(name, loginType)));
    }

    @IsTest
    static void developerEditionWithoutTracking() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Id orgId = register('DEV1', 'Production');
            RLY_Org__c saved = [SELECT Status__c, My_Domain__c, Source_Tracking__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assertEquals('Not checked', saved.Status__c, 'New orgs wait for their first check');
            System.assertEquals('https://demo-dev-ed.develop.my.salesforce.com', saved.My_Domain__c, 'Trailing slash removed');

            RlyOrgCheckMock mock = new RlyOrgCheckMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals(0, mock.unsignedCalls, 'Every call carries the hub token');
            System.assertEquals('Connected', checked.Status__c, 'Signed in: ' + checked.Status_Message__c);
            System.assertEquals(mock.orgId, checked.Org_Id__c, 'Org Id read');
            System.assertEquals('64.0', checked.Api_Version__c, 'Newest API version');
            System.assertEquals('Not available', checked.Source_Tracking__c, 'No source tracking in Developer Edition');
            System.assertEquals(RlyOrgCheck.TRACKING_HINT_NONE, checked.Status_Message__c, 'Says the Metadata API is used');

            RlyOrgController.PipelineOrgs hub = RlyOrgController.getOrgs();
            System.assertEquals(true, hub.isAdmin, 'Admin');
            System.assertEquals(1, hub.orgs.size(), 'Listed');
            System.assert(String.isNotBlank(hub.hubDomain), 'Hub domain shown for the Remote Site Setting');
        }
    }

    @IsTest
    static void sandboxWithTrackingThenRefreshed() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Id orgId = register('SIT', 'Sandbox');
            Id refreshedId = register('SIT2', 'Sandbox');
            // SIT2 was checked before its last refresh: the Org Id on file is the old one.
            update new RLY_Org__c(Id = refreshedId, Org_Id__c = RlyTestData.fakeId('00D', 9), Status__c = 'Connected');
            RlyOrgCheckMock mock = new RlyOrgCheckMock();
            mock.sandbox = true;
            mock.tracking = true;
            mock.orgType = 'Enterprise Edition';
            Test.setMock(HttpCalloutMock.class, mock);
            RLY_Org__c sit = [SELECT Id, Name, My_Domain__c, Login_Type__c, Username__c, Consumer_Key__c, Client_Id__c,
                Certificate__c, Org_Id__c FROM RLY_Org__c WHERE Id = :orgId];
            Test.startTest();
            // run() makes callouts only; checkOrg() then calls out and saves once, so no callout follows a save.
            RLY_Org__c firstCheck = RlyOrgCheck.run(sit);
            RLY_Org__c secondCheck = RlyOrgController.checkOrg(refreshedId);
            Test.stopTest();
            System.assertEquals(0, mock.unsignedCalls, 'Every call carries the hub token');
            System.assertEquals('Connected', firstCheck.Status__c, 'Signed in: ' + firstCheck.Status_Message__c);
            System.assertEquals('Available', firstCheck.Source_Tracking__c, 'Source tracking found');
            System.assertEquals(null, firstCheck.Status_Message__c, 'Nothing to recommend');
            System.assertEquals(true, firstCheck.Is_Sandbox__c, 'Sandbox');
            System.assertEquals('Connected', secondCheck.Status__c, 'Still connected after a refresh');
            System.assertEquals(mock.orgId, secondCheck.Org_Id__c, 'New Org Id saved');
            System.assert(secondCheck.Status_Message__c.contains('refreshed'), secondCheck.Status_Message__c);
        }
    }

    @IsTest
    static void sandboxWithoutTrackingGetsRecommendation() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Id orgId = register('UAT', 'Production');
            RlyOrgCheckMock mock = new RlyOrgCheckMock();
            mock.sandbox = true;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals(0, mock.unsignedCalls, 'Every call carries the hub token');
            System.assert(checked.Status_Message__c.contains(RlyOrgCheck.TRACKING_HINT_SANDBOX), 'Recommends source tracking');
            System.assert(checked.Status_Message__c.contains('set Login type to Sandbox'), 'Flags the wrong login type');
        }
    }

    @IsTest
    static void apiErrorsMarkTheOrgFailed() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Id orgId = register('DEV3', 'Production');
            RlyOrgCheckMock mock = new RlyOrgCheckMock();
            mock.queryStatus = 401;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(orgId);
            Test.stopTest();
            System.assertEquals(0, mock.unsignedCalls, 'Every call carries the hub token');
            System.assertEquals('Failed', checked.Status__c, 'API error recorded');
            System.assert(checked.Status_Message__c.contains('401'), checked.Status_Message__c);
        }
    }

    @IsTest
    static void refusesBadInputAndDuplicates() {
        System.runAs(RlyTestData.admin()) {
            List<String> problems = RlyOrgValidator.validate(new RLY_Org__c(
                Name = 'Bad/Name', Role__c = 'Other', My_Domain__c = 'http://example.com', Login_Type__c = 'Test',
                Username__c = 'nobody', Consumer_Key__c = 'has space', Certificate__c = '1bad', Git_Environment__c = 'bad$env',
                Branch__c = 'bad branch'), null);
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

            Id orgId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1' LIMIT 1].Id;
            update new RLY_Org__c(Id = orgId, Org_Id__c = RlyTestData.fakeId('00D', 1), Status__c = 'Connected');
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

    @IsTest
    static void slackAvailableOnlyWhenConnected() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(false, RlyOrgController.getOrgs().slackAvailable, 'Slack off');
            RlyReleaseTestData.slackOn(null);
            Test.startTest();
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyHttpMock()));
            Boolean connected = RlyOrgController.getOrgs().slackAvailable;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('POST', 'callout:RLY_Slack/auth.test').reply(200, '{"ok":false,"error":"invalid_auth"}'));
            Boolean refused = RlyOrgController.getOrgs().slackAvailable;
            Test.stopTest();
            System.assertEquals(true, connected, 'Slack on and its app answers');
            System.assertEquals(false, refused, 'Slack on but its token is refused');
        }
    }
}
