/**
 * @description Tests for the Credentials dashboard (build 49): RlyCredentialCheck and its checks (RlyCredentialHubChecks,
 * RlyCredentialOrgChecks, RlyCredentialUsers, RlyCredentialParse), the Slack alert (RlyCredentialAlert), the rows
 * (RlyCredentialRows, RlyCredentialViews, RlyCredentialStore), the pages (RlyCredentialController) and the nightly hook
 * (RlyCredentialNightly). Each test runs as an active System Administrator with Release Relay Admin. Records are
 * inserted before Test.startTest; callouts come after it, and the saves after the callouts.
 */
@IsTest
private class RlyCredentialTest {

    private static final Date TODAY_FOR_TEST = Date.newInstance(2026, 11, 7);

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    /** @description Answers by URL fragment, with headers (GitHub's token expiry). */
    private class Mock implements HttpCalloutMock {
        private List<List<String>> rules = new List<List<String>>();
        public List<String> calls = new List<String>();
        public Map<String, String> bodies = new Map<String, String>();

        /**
         * @description Adds an answer for URLs containing a fragment.
         * @param urlPart the fragment
         * @param status the HTTP status
         * @param body the body
         * @return this mock
         */
        public Mock answer(String urlPart, Integer status, String body) {
            rules.add(new List<String>{ urlPart, String.valueOf(status), body, null });
            return this;
        }

        /**
         * @description Gives the last answer GitHub's token expiry header.
         * @param expiry the header's value
         * @return this mock
         */
        public Mock withExpiry(String expiry) {
            rules[rules.size() - 1][3] = expiry;
            return this;
        }

        /**
         * @description Answers a callout from the table (404 when nothing matches).
         * @param req the request
         * @return the answer
         */
        public HttpResponse respond(HttpRequest req) {
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            calls.add(url);
            bodies.put(url, req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"message":"Not Found"}');
            for (List<String> r : rules) {
                if (url.contains(r[0])) {
                    res.setStatusCode(Integer.valueOf(r[1]));
                    res.setBody(r[2]);
                    if (r[3] != null) {
                        res.setHeader(RlyCredentialParse.GITHUB_EXPIRY_HEADER, r[3]);
                    }
                    break;
                }
            }
            return res;
        }
    }

    private static String certs(String devName, String expires) {
        return '{"records":[{"DeveloperName":"' + devName + '","MasterLabel":"' + devName + '","ExpirationDate":"' + expires + 'T00:00:00.000+0000"}]}';
    }

    // DEV1 (developer org, inactive user), SIT (stage), PROD (the hub, its user unknown here), a GitHub connection, Slack on.
    private static Mock scenario() {
        RlyReleaseTestData.route();
        RlyReleaseTestData.slackOn('Ready for approval');
        update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD'].Id, Slack_Channel__c = '#relay-admins', Status__c = 'Connected',
            Last_Checked__c = System.now().addDays(-1));
        RlyCredentialRows.todayForTest = TODAY_FOR_TEST;
        RlyOrgSession.testToken = RlyTestData.TOKEN;
        return new Mock()
            .answer('callout:RLY_GitHub/repos/acme/release', 200, '{"id":1}').withExpiry('2026-11-12 10:00:00 UTC')
            .answer('callout:RLY_Slack/auth.test', 200, '{"ok":true,"team":"Acme"}')
            .answer('callout:RLY_Slack/chat.postMessage', 200, '{"ok":true,"channel":"C1","ts":"1.1"}')
            .answer('dev1.my.salesforce.com/services/data/v63.0/tooling/query', 200, certs('dev_cert', '2026-11-01'))
            .answer('dev1.my.salesforce.com/services/data/v63.0/query', 200, '{"records":[{"IsActive":false}]}')
            .answer('sit.my.salesforce.com/services/data/v63.0/tooling/query', 200, certs('sit_cert', '2027-06-01'))
            .answer('sit.my.salesforce.com/services/data/v63.0/query', 200, '{"records":[{"IsActive":true}]}');
    }

    private static Map<String, RLY_Credential_Status__c> saved() {
        Map<String, RLY_Credential_Status__c> out = new Map<String, RLY_Credential_Status__c>();
        for (RLY_Credential_Status__c r : [SELECT Key__c, Kind__c, Name, Status__c, Expires_On__c, Message__c, Last_OK__c, Org__r.Name
                                           FROM RLY_Credential_Status__c LIMIT 500]) {
            out.put(r.Kind__c + '|' + (r.Org__r == null ? '' : r.Org__r.Name) + '|' + r.Name, r);
        }
        return out;
    }

    private static RLY_Credential_Status__c find(Map<String, RLY_Credential_Status__c> rows, String kind, String nameStart) {
        for (RLY_Credential_Status__c r : rows.values()) {
            if (r.Kind__c == kind && r.Name.startsWith(nameStart)) {
                return r;
            }
        }
        return null;
    }

    @IsTest
    static void aPassChecksEverythingAndAlertsOnce() {
        System.runAs(RlyTestData.admin()) {
            Mock mock = scenario();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyCredentialCheck.Pass p = RlyCredentialCheck.gather();
            RlyCredentialCheck.save(p);
            Test.stopTest();
            Map<String, RLY_Credential_Status__c> rows = saved();
            RLY_Credential_Status__c git = find(rows, RlyCredentialRows.KIND_GIT, 'GitHub');
            System.assertEquals(RlyCredentialRows.CRITICAL, git.Status__c, 'GitHub token 5 days left: ' + git);
            System.assertEquals(Date.newInstance(2026, 11, 12), git.Expires_On__c, 'Expiry from the header');
            System.assertEquals(RlyCredentialRows.OK, find(rows, RlyCredentialRows.KIND_SLACK, 'Slack').Status__c, 'Slack answers');
            System.assertEquals(RlyCredentialRows.UNKNOWN, find(rows, RlyCredentialRows.KIND_CERT, 'Hub certificates').Status__c,
                'No RLY_Org_Self in the test org');
            System.assertEquals(RlyCredentialRows.EXPIRED, find(rows, RlyCredentialRows.KIND_CERT, 'dev_cert').Status__c, 'DEV1 certificate expired');
            System.assertEquals(RlyCredentialRows.OK, find(rows, RlyCredentialRows.KIND_CERT, 'sit_cert').Status__c, 'SIT certificate fine');
            System.assertEquals(RlyCredentialRows.FAILED, find(rows, RlyCredentialRows.KIND_USER, 'DEV1').Status__c, 'DEV1 user inactive');
            System.assertEquals(RlyCredentialRows.OK, find(rows, RlyCredentialRows.KIND_USER, 'SIT').Status__c, 'SIT user active');
            System.assertEquals(RlyCredentialRows.FAILED, find(rows, RlyCredentialRows.KIND_USER, 'PROD').Status__c, 'The hub has no such user');
            System.assertEquals(RlyCredentialRows.OK, find(rows, RlyCredentialRows.KIND_SIGNIN, 'SIT').Status__c, 'Signed in to SIT');
            System.assertEquals(RlyCredentialRows.OK, find(rows, RlyCredentialRows.KIND_SIGNIN, 'PROD').Status__c, 'Hub from its saved check');
            System.assertNotEquals(null, find(rows, RlyCredentialRows.KIND_SIGNIN, 'SIT').Last_OK__c, 'Last OK stamped');
            System.assertEquals(2, p.orgsChecked, 'DEV1 and SIT signed in');
            System.assertEquals(0, p.orgsLeft, 'Nothing left');
            String alert = mock.bodies.get('callout:RLY_Slack/chat.postMessage');
            System.assert(alert != null && alert.contains('credentials need attention') && alert.contains('#relay-admins'), 'One alert: ' + alert);
            System.assert(p.alertResult.startsWith('Sent'), 'Recorded: ' + p.alertResult);
            System.assert(RlyCredentialCheck.summary(p).contains('checked'), RlyCredentialCheck.summary(p));
        }
    }

    @IsTest
    static void aSmallBudgetLeavesOrgsForTheNextPass() {
        System.runAs(RlyTestData.admin()) {
            Mock mock = scenario();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            p.budget = 4;
            RlyCredentialHubChecks.git(p);
            RlyCredentialOrgChecks.run(p);
            Test.stopTest();
            System.assertEquals(1, p.orgsChecked, 'Room for one org after the Git call');
            System.assertEquals(1, p.orgsLeft, 'The other waits');
            System.assert(p.callouts() <= 4, 'Within the budget: ' + p.callouts());
            System.assert(RlyCredentialCheck.summary(p).contains('left for the next pass'), RlyCredentialCheck.summary(p));
        }
    }

    @IsTest
    static void signInFailuresAndRefusedQueriesAreShown() {
        System.runAs(RlyTestData.admin()) {
            scenario();
            RlyOrgSession.testToken = null;
            RlyOrgSession.testSignInError = 'invalid_grant: user hasn\'t approved this consumer';
            Mock mock = new Mock().answer('callout:RLY_GitHub/repos/', 401, '{"message":"Bad credentials"}')
                .answer('callout:RLY_Slack/auth.test', 200, '{"ok":false,"error":"invalid_auth"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyCredentialCheck.Pass p = RlyCredentialCheck.gather();
            Test.stopTest();
            System.assertEquals(RlyCredentialRows.FAILED, find(p.found, RlyCredentialRows.KIND_GIT, 'GitHub').Status__c, 'Token refused');
            System.assertEquals(RlyCredentialRows.FAILED, find(p.found, RlyCredentialRows.KIND_SLACK, 'Slack').Status__c, 'Slack refused');
            System.assertEquals(RlyCredentialRows.FAILED, find(p.found, RlyCredentialRows.KIND_SIGNIN, 'SIT').Status__c, 'No sign-in');
            System.assertEquals(RlyCredentialRows.UNKNOWN, find(p.found, RlyCredentialRows.KIND_USER, 'SIT').Status__c, 'User unknown');
            System.assert(p.turnedBad.size() >= 3, 'New failures alert: ' + p.turnedBad.size());
        }
    }

    @IsTest
    static void theHubReadsItsOwnCertificatesAndGitLabTokens() {
        System.runAs(RlyTestData.admin()) {
            RlyCredentialRows.todayForTest = TODAY_FOR_TEST;
            insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
                Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default', Active__c = true);
            insert new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'group/project', Named_Credential__c = 'RLY_GitLab',
                Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default', Active__c = false);
            RlyCredentialHubChecks.selfCredentialForTest = true;
            Mock mock = new Mock()
                .answer('callout:RLY_Org_Self/services/data/v63.0/tooling/query', 200, certs('release_relay', '2026-12-01'))
                .answer('callout:RLY_GitLab/personal_access_tokens/self', 200, '{"expires_at":"2026-11-10","active":true}')
                .answer('callout:RLY_GitHub/repos/acme/release', 200, '{}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            RlyCredentialHubChecks.certificates(p);
            RlyCredentialHubChecks.git(p);
            Test.stopTest();
            RLY_Credential_Status__c cert = p.found.get(RlyCredentialHubChecks.HUB_CERT_PREFIX + 'release_relay');
            System.assertEquals(RlyCredentialRows.EXPIRING, cert.Status__c, '24 days left: ' + cert);
            System.assertEquals(Date.newInstance(2026, 12, 1), p.hubCerts.get('release_relay'), 'Kept for the org sign-ins');
            System.assert(p.goneKeys.contains(RlyCredentialHubChecks.HUB_CERT_KEY), 'The placeholder row goes');
            RLY_Credential_Status__c lab = find(p.found, RlyCredentialRows.KIND_GIT, 'GitLab');
            System.assertEquals(RlyCredentialRows.CRITICAL, lab.Status__c, 'An inactive GitLab connection is checked too: ' + lab);
            System.assertEquals(RlyCredentialRows.OK, find(p.found, RlyCredentialRows.KIND_GIT, 'GitHub').Status__c, 'No expiry header');
        }
    }

    @IsTest
    static void aRefusedSelfQueryIsShown() {
        System.runAs(RlyTestData.admin()) {
            RlyCredentialHubChecks.selfCredentialForTest = true;
            Test.setMock(HttpCalloutMock.class, new Mock().answer('callout:RLY_Org_Self/', 403, '[{"errorCode":"INSUFFICIENT_ACCESS"}]'));
            Test.startTest();
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            RlyCredentialHubChecks.certificates(p);
            p.budget = 0;
            RlyCredentialHubChecks.slack(p);
            Test.stopTest();
            RLY_Credential_Status__c holder = p.found.get(RlyCredentialHubChecks.HUB_CERT_KEY);
            System.assertEquals(RlyCredentialRows.FAILED, holder.Status__c, 'Refused: ' + holder);
            System.assert(holder.Message__c.contains('403'), holder.Message__c);
        }
    }

    @IsTest
    static void gitLabTokensAndOtherProviders() {
        System.runAs(RlyTestData.admin()) {
            RlyCredentialRows.todayForTest = TODAY_FOR_TEST;
            RLY_Credential_Status__c r = RlyCredentialRows.row('git:x', RlyCredentialRows.KIND_GIT, 'GitLab · group/project');
            HttpResponse answerOk = new HttpResponse();
            answerOk.setStatusCode(200);
            answerOk.setBody('{"expires_at":"2026-11-30","active":true,"revoked":false}');
            System.assertEquals(RlyCredentialRows.EXPIRING, RlyCredentialParse.gitLab(r, answerOk).Status__c, '23 days left');
            answerOk.setBody('{"expires_at":null,"active":false}');
            System.assertEquals(RlyCredentialRows.FAILED, RlyCredentialParse.gitLab(r, answerOk).Status__c, 'Not active');
            HttpResponse refused = new HttpResponse();
            refused.setStatusCode(401);
            System.assertEquals(RlyCredentialRows.FAILED, RlyCredentialParse.gitLab(r, refused).Status__c, 'Refused');
            refused.setStatusCode(500);
            System.assert(RlyCredentialParse.gitLab(r, refused).Message__c.contains('500'), 'Other errors');
            System.assert(RlyCredentialParse.gitHub(r, refused).Message__c.contains('500'), 'GitHub errors');
            HttpResponse noExpiry = new HttpResponse();
            noExpiry.setStatusCode(200);
            noExpiry.setBody('{}');
            System.assertEquals(RlyCredentialRows.OK, RlyCredentialParse.gitHub(r, noExpiry).Status__c, 'No header: no expiry');
            System.assertEquals(null, RlyCredentialParse.dateOf('soon'), 'Not a date');
            System.assertEquals(null, RlyCredentialParse.dateOf('2026-13-45 00'), 'Bad date');
            List<RLY_Credential_Status__c> hub = RlyCredentialParse.certRows(certs('release_relay', '2026-11-10'), 'cert:hub:', null);
            System.assertEquals('release_relay (hub)', hub[0].Name, 'Hub certificate named');
            System.assertEquals(RlyCredentialRows.CRITICAL, hub[0].Status__c, '3 days left');
            System.assertEquals(RlyCredentialRows.FAILED, RlyCredentialRows.worse(RlyCredentialRows.OK, RlyCredentialRows.FAILED), 'Worse');
        }
    }

    @IsTest
    static void theHubSignInTakesItsCertificateExpiry() {
        System.runAs(RlyTestData.admin()) {
            RlyCredentialRows.todayForTest = TODAY_FOR_TEST;
            RLY_Org__c hub = RlyTestData.org('PROD', 'Hub', 'prod');
            hub.Status__c = 'Failed';
            insert hub;
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            p.hubCerts.put('release_relay', Date.newInstance(2026, 11, 9));
            RlyCredentialUsers.hubOrg(p, [SELECT Id, Name, Role__c, Username__c, Certificate__c, Status__c, Last_Checked__c FROM RLY_Org__c WHERE Id = :hub.Id]);
            RLY_Credential_Status__c s = p.found.get(RlyCredentialOrgChecks.signInKey(hub.Id));
            System.assertEquals(RlyCredentialRows.FAILED, s.Status__c, 'Its last check failed');
            hub.Status__c = 'Connected';
            RlyCredentialUsers.hubOrg(p, hub);
            s = p.found.get(RlyCredentialOrgChecks.signInKey(hub.Id));
            System.assertEquals(RlyCredentialRows.CRITICAL, s.Status__c, 'Signs in with a certificate 2 days from expiry');
            System.assert(s.Message__c.contains('release_relay'), s.Message__c);
            hub.Status__c = 'Not checked';
            RlyCredentialUsers.hubOrg(p, hub);
            System.assertEquals(RlyCredentialRows.UNKNOWN, p.found.get(RlyCredentialOrgChecks.signInKey(hub.Id)).Status__c, 'Not checked yet');
            RLY_Credential_Status__c u = RlyCredentialRows.orgRow('user:x', RlyCredentialRows.KIND_USER, hub);
            System.assertEquals(RlyCredentialRows.OK, RlyCredentialUsers.userStatus(u, RlyCredentialUsers.ACTIVE, hub).Status__c, 'Active');
            System.assertEquals(RlyCredentialRows.FAILED, RlyCredentialUsers.userStatus(u, RlyCredentialUsers.INACTIVE, hub).Status__c, 'Inactive');
        }
    }

    @IsTest
    static void thePagesReadTheRows() {
        System.runAs(RlyTestData.admin()) {
            RlyCredentialRows.todayForTest = TODAY_FOR_TEST;
            RLY_Org__c sit = RlyTestData.stage('SIT', 'sit', 1);
            insert sit;
            RlyCredentialStore.save(new List<RLY_Credential_Status__c>{
                RlyCredentialRows.fromExpiry(RlyCredentialRows.row('git:a', RlyCredentialRows.KIND_GIT, 'GitHub · acme/release'), Date.newInstance(2026, 11, 20), null),
                RlyCredentialRows.mark(RlyCredentialRows.row('slack', RlyCredentialRows.KIND_SLACK, 'Slack app'), RlyCredentialRows.OK, 'ok'),
                RlyCredentialRows.mark(RlyCredentialRows.orgRow('cert:' + sit.Id + ':c', RlyCredentialRows.KIND_CERT, sit), RlyCredentialRows.FAILED, 'x'),
                RlyCredentialRows.mark(RlyCredentialRows.orgRow('user:' + sit.Id, RlyCredentialRows.KIND_USER, sit), RlyCredentialRows.UNKNOWN, 'x'),
                RlyCredentialRows.mark(RlyCredentialRows.row('signin:a', RlyCredentialRows.KIND_SIGNIN, 'Old'), RlyCredentialRows.OK, 'x')
            }, null);
            RlyCredentialController.Board b = RlyCredentialController.board();
            System.assertEquals(5, b.rows.size(), 'Every row');
            System.assertEquals(RlyCredentialRows.FAILED, b.rows[0].status, 'Worst first');
            System.assertEquals(1, b.counts.get(RlyCredentialRows.EXPIRING), 'Counted');
            System.assert(b.canCheck, 'Admins check now');
            for (RlyCredentialViews.Row r : b.rows) {
                System.assert(String.isNotBlank(r.renew), 'How to renew ' + r.kind);
            }
            System.assertEquals(13, b.rows[1].daysLeft, 'Days left: ' + b.rows[1].name);
            RlyCredentialController.Tile t = RlyCredentialController.tile();
            System.assertEquals(2, t.problems.size(), 'Expiring and Failed');
            System.assertEquals(5, t.total, 'Total');
            System.assert(t.isAdmin, 'Admin link');
            System.assert(RlyCredentialViews.howToRenew(RlyCredentialRows.KIND_GIT, 'GitLab · g/p').contains('GitLab'), 'GitLab renew');
            System.assert(RlyCredentialViews.howToRenew(RlyCredentialRows.KIND_SIGNIN, 'x').contains('Pipeline'), 'Sign-in renew');
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            p.saved = RlyCredentialStore.byKey();
            p.replaceScope('cert:' + sit.Id + ':');
            p.gone('signin:a');
            System.assertEquals(2, p.goneKeys.size(), 'Gone rows');
            RlyCredentialCheck.save(p);
            System.assertEquals(3, [SELECT COUNT() FROM RLY_Credential_Status__c], 'Removed');
        }
    }

    @IsTest
    static void checkNowAndTheNightlyCall() {
        System.runAs(RlyTestData.admin()) {
            Mock mock = scenario();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyCredentialController.Board b = RlyCredentialController.checkNow();
            Test.stopTest();
            System.assert(b.message.startsWith('Checked:'), b.message);
            System.assert(b.rows.size() > 5, 'Rows saved: ' + b.rows.size());
            System.assertEquals(null, RlyCredentialNightly.checkFirst('{"runId":"a0B000000000001"}'), 'Later calls of the night don\'t check');
            Map<String, Object> answer = new Map<String, Object>();
            RlyCredentialNightly.saveAfter(null, answer);
            System.assert(!answer.containsKey('credentials'), 'Nothing to save');
            RlyCredentialCheck.Pass p = new RlyCredentialCheck.Pass();
            p.add(RlyCredentialRows.mark(RlyCredentialRows.row('slack', RlyCredentialRows.KIND_SLACK, 'Slack app'), RlyCredentialRows.OK, 'ok'));
            RlyCredentialNightly.saveAfter(p, answer);
            System.assert(String.valueOf(answer.get('credentials')).contains('1 checked'), 'Said in the answer: ' + answer);
        }
    }

    @IsTest
    static void onlyAdminsCheckNow() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            String refused;
            try {
                RlyCredentialController.checkNow();
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.contains('admin'), 'Refused: ' + refused);
            System.assert(!RlyCredentialController.board().canCheck, 'No Check now');
            System.assertEquals(null, RlyCredentialAlert.post(new List<RLY_Credential_Status__c>()), 'Nothing to post');
            System.assert(RlyCredentialAlert.text(new List<RLY_Credential_Status__c>{
                new RLY_Credential_Status__c(Name = 'GitHub', Kind__c = 'Git token', Status__c = 'Expired', Expires_On__c = Date.newInstance(2026, 11, 1))
            }).contains('Expired: Git token'), 'Alert text');
        }
    }
}
