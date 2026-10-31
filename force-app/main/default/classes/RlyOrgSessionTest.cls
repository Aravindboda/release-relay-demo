/**
 * @description Tests for signing in to registered orgs (RlyOrgSession) and the plain-language sign-in errors
 * (RlySignInAdvice). Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it.
 */
@IsTest
private class RlyOrgSessionTest {

    /** @description Fails every call, as when the org can't be reached. */
    private class DownMock implements HttpCalloutMock {
        /**
         * @description Throws as an unreachable org does.
         * @param req the request
         * @return never
         */
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Unauthorized endpoint, please check Setup->Security->Remote site settings');
        }
    }

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    @IsTest
    static void signInFailuresExplainTheFix() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgSession.testSignInError = 'invalid_grant: user hasn\'t approved this consumer';
            RLY_Org__c dev = RlyTestData.org('DEV2', 'Developer', 'dev2');
            insert dev;
            Test.setMock(HttpCalloutMock.class, new RlyOrgCheckMock());
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(dev.Id);
            Test.stopTest();
            System.assertEquals('Failed', checked.Status__c, 'Sign-in failed');
            System.assert(checked.Status_Message__c.contains('Pre-authorize'), checked.Status_Message__c);

            RLY_Org__c o = new RLY_Org__c(Name = 'DEV2', My_Domain__c = 'https://demo.my.salesforce.com', Certificate__c = 'release_relay');
            Map<String, String> cases = new Map<String, String>{
                'Unauthorized endpoint, please check Setup->Security->Remote site settings' => 'Remote Site Setting',
                'Certificate does not exist' => 'Hub certificate',
                'invalid_client_id: client identifier invalid' => 'Consumer key',
                'invalid_grant: audience is invalid' => 'Login type',
                'invalid_grant: user is inactive' => 'Integration username',
                'invalid_grant: something else' => 'JWT bearer flow',
                'Read timed out' => 'couldn\'t sign in'
            };
            for (String raw : cases.keySet()) {
                String fix = RlySignInAdvice.explain(raw, o);
                System.assert(fix.contains(cases.get(raw)), raw + ' -> ' + fix);
            }
            System.assertEquals('https://test.salesforce.com', RlyOrgSession.audience(new RLY_Org__c(Login_Type__c = 'Sandbox')), 'Sandbox audience');
            System.assertEquals('https://login.salesforce.com', RlyOrgSession.audience(new RLY_Org__c(Login_Type__c = 'Production')), 'Production audience');
        }
    }

    @IsTest
    static void sessionEdgeCases() {
        System.runAs(RlyTestData.admin()) {
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

            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new DownMock());
            Test.startTest();
            Boolean unreachable = false;
            try {
                RlyOrgSession.send(org, new RlyOrgSession.Call('POST', '/services/data/v63.0/sobjects/Account').withBody('{}'));
            } catch (RlyOrgSession.SignInException e) {
                unreachable = e.getMessage().contains('Remote Site Setting');
            }
            Test.stopTest();
            System.assert(unreachable, 'An unreachable org points to the Remote Site Setting');
            System.assert(RlyOrgSession.toolingQueryPath('SELECT Id FROM Account').startsWith('/services/data/v63.0/tooling/query/'), 'Tooling path');
            System.assert(RlyOrgSession.queryPath('SELECT Id FROM Account').startsWith('/services/data/v63.0/query/'), 'REST path');
        }
    }
}
