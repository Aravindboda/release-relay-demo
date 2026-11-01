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

    /** @description Answers 401 to every token but the good one, and records what each call carried. */
    private class TokenMock implements HttpCalloutMock {
        /** @description The Authorization header of each call, in order. */
        public List<String> auths = new List<String>();
        /** @description The body of each call, in order. */
        public List<String> bodies = new List<String>();
        private String goodToken;

        /**
         * @description A mock that accepts one token.
         * @param goodToken the token answered with 200, or null to refuse every token
         */
        public TokenMock(String goodToken) {
            this.goodToken = goodToken;
        }

        /**
         * @description 200 for the good token, 401 INVALID_SESSION_ID for any other.
         * @param req the request
         * @return the answer
         */
        public HttpResponse respond(HttpRequest req) {
            auths.add(req.getHeader('Authorization'));
            bodies.add(req.getBody());
            Boolean good = goodToken != null && req.getHeader('Authorization') == 'Bearer ' + goodToken;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(good ? 200 : 401);
            res.setBody(good ? '{"ok":true}' : '[{"errorCode":"INVALID_SESSION_ID","message":"Session expired or invalid"}]');
            return res;
        }
    }

    private static RLY_Org__c savedOrg() {
        RLY_Org__c org = RlyTestData.org('DEV7', 'Developer', 'dev7');
        insert org;
        return org;
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

    @IsTest
    static void keptTokenSavesTheSignIn() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c org = savedOrg();
            RlyTokenCache.active = new RlyTokenCache.MemoryStore();
            RlyTokenCache.keep(org, 'kept!token');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            TokenMock mock = new TokenMock('kept!token');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            HttpResponse res = RlyOrgSession.send(org, new RlyOrgSession.Call('GET', '/services/data/'));
            Test.stopTest();
            System.assertEquals(200, res.getStatusCode(), 'The kept token works');
            System.assertEquals('Bearer kept!token', mock.auths[0], 'The kept token is used');
            System.assertEquals(0, RlyOrgSession.signIns, 'No sign-in (no token callout) with a kept token');
        }
    }

    @IsTest
    static void refusedKeptTokenIsRenewedOnce() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c org = savedOrg();
            RlyTokenCache.active = new RlyTokenCache.MemoryStore();
            RlyTokenCache.keep(org, 'stale!token');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            TokenMock mock = new TokenMock(RlyTestData.TOKEN);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            HttpResponse res = RlyOrgSession.send(org, new RlyOrgSession.Call('POST', '/services/Soap/m/63.0')
                .withBody('<sessionId>stale!token</sessionId>'));
            Test.stopTest();
            System.assertEquals(200, res.getStatusCode(), 'Sent again with a new token');
            System.assertEquals(2, mock.auths.size(), 'One retry: ' + mock.auths);
            System.assertEquals('Bearer ' + RlyTestData.TOKEN, mock.auths[1], 'The retry signs in afresh');
            System.assert(mock.bodies[1].contains(RlyTestData.TOKEN) && !mock.bodies[1].contains('stale'), 'The body carries the new token too');
            System.assertEquals(1, RlyOrgSession.signIns, 'Signed in once');
            System.assertEquals(RlyTestData.TOKEN, RlyTokenCache.fetch(org), 'The new token is kept in place of the refused one');
        }
    }

    @IsTest
    static void refusedAgainIsNotRetriedTwice() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c org = savedOrg();
            RlyTokenCache.active = new RlyTokenCache.MemoryStore();
            RlyTokenCache.keep(org, 'stale!token');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            TokenMock mock = new TokenMock(null);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            HttpResponse first = RlyOrgSession.send(org, new RlyOrgSession.Call('GET', '/services/data/'));
            HttpResponse second = RlyOrgSession.send(org, new RlyOrgSession.Call('GET', '/services/data/'));
            Test.stopTest();
            System.assertEquals(401, first.getStatusCode(), 'The refusal is handed back after one retry');
            System.assertEquals(401, second.getStatusCode(), 'A fresh token refused is not renewed');
            System.assertEquals(3, mock.auths.size(), 'Retried once in all: ' + mock.auths);
            System.assertEquals(1, RlyOrgSession.signIns, 'Signed in once');
        }
    }

    @IsTest
    static void withoutThePartitionTokensLastTheTransaction() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c org = savedOrg();
            RlyTokenCache.active = new RlyTokenCache.OrgStore('local.RlyNoSuchPartition');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.startTest();
            String once = RlyOrgSession.accessToken(org);
            String again = RlyOrgSession.accessToken(org);
            Test.stopTest();
            System.assertEquals(RlyTestData.TOKEN, once, 'Signed in');
            System.assertEquals(once, again, 'Reused within the transaction');
            System.assertEquals(1, RlyOrgSession.signIns, 'One sign-in per transaction without the cache');
            System.assertEquals(null, RlyTokenCache.fetch(org), 'Nothing kept');
            RlyTokenCache.evict(org);

            RlyTokenCache.OrgStore real = new RlyTokenCache.OrgStore(RlyTokenCache.PARTITION);
            real.keep('tokTest', 'value');
            real.fetch('tokTest');
            real.drop('tokTest');
            System.assertEquals(null, real.fetch('tokTest'), 'Dropped, or never kept without capacity');
            System.assertEquals(null, RlyTokenCache.keyOf(new RLY_Org__c(Name = 'X')), 'An unsaved org has no key');
            System.assert(RlyTokenCache.keyOf(org).length() <= 50 && RlyTokenCache.keyOf(org).isAlphanumeric(), 'Cache keys are short and alphanumeric');
        }
    }
}
