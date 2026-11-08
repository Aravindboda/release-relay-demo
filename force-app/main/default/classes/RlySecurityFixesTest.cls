/**
 * @description Tests for the build 48 hub fixes: tickets changed only by the raiser or an admin, the ServiceNow change
 * that must name the release, who may run the checks again, https-only links from results, and Slack (constant-time
 * signature check, the payload read only from the signed body, the workspace check, the workspace recorded on Test,
 * and "Link my account" only for a matched person). Callouts are mocked (RlyHttpMock); nothing depends on org data.
 * Every test runs as an active System Administrator holding Release Relay Admin (or a plain user) through System.runAs.
 */
@IsTest
private class RlySecurityFixesTest {

    private static final String SECRET = RlyReleaseTestData.SIGNING_SECRET;

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Release__c withTickets(String status) {
        RLY_Release__c rel = RlyReleaseTestData.release(status, 'hub');
        RlyWorkItems.attach(rel, new List<String>{ 'CLAIMS-412' });
        return rel;
    }

    private static RestRequest signed(String payloadJson, String stamp) {
        String body = 'payload=' + EncodingUtil.urlEncode(payloadJson, 'UTF-8');
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        req.headers.put('X-Slack-Request-Timestamp', stamp);
        req.headers.put('X-Slack-Signature', RlySlackSignature.sign(SECRET, stamp, body));
        return req;
    }

    private static String now() {
        return String.valueOf(System.now().getTime() / 1000);
    }

    @IsTest
    static void ticketsChangeOnlyForTheRaiserOrAnAdmin() {
        User plain = RlyTestData.plainUser();
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = withTickets('Ready for approval');
        }
        System.runAs(plain) {
            Test.startTest();
            RlyWorkTypes.ReleaseTickets seen = RlyWorkItemsController.releaseTickets(rel.Id);
            String error;
            try {
                RlyWorkItemsController.addReleaseTickets(rel.Id, new List<String>{ 'CLAIMS-999' });
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assert(!seen.canEdit, 'Read-only for someone else');
            System.assert(error != null && error.contains('Only the person who raised'), 'Refused: ' + error);
        }
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyWorkItemsController.releaseTickets(rel.Id).canEdit, 'The raiser (an admin here) can edit');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Work_Item__c WHERE Release__c = :rel.Id], 'Nothing added by the refused call');
        }
    }

    @IsTest
    static void theChangeMustNameTheRelease() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            insert new RLY_Work_Tracker__c(Name = 'Changes', Type__c = 'ServiceNow', Named_Credential__c = 'RLY_Work_ServiceNow',
                Ticket_Pattern__c = 'CHG\\d{7}', Active__c = true, Sort_Order__c = 1, Change_Mentions_Release__c = true);
            insert new RLY_Work_Tracking__c(SetupOwnerId = UserInfo.getOrganizationId(), Require_Change__c = true, Change_Pattern__c = 'CHG\\d{7}');
            RlyWorkStore.forgetTrackers();
            Id prodId = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id;
            RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region', Status__c = 'Ready for approval', Mode__c = 'Org changes',
                Request_Type__c = 'Changes', Release_Type__c = 'Release', Target_Org__c = prodId, Target_Branch__c = 'prod');
            insert rel;
            rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
            RlyWorkItems.attach(rel, new List<String>{ 'CHG0012345' });
            String start = Datetime.now().addHours(-1).formatGmt('yyyy-MM-dd HH:mm:ss');
            String ends = Datetime.now().addHours(2).formatGmt('yyyy-MM-dd HH:mm:ss');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/api/now/table/change_request').reply(200,
                '{"result":[{"number":"CHG0012345","approval":"approved","start_date":"' + start + '","end_date":"' + ends
                + '","short_description":"Quarterly patch","description":"Also ' + rel.Name + '1 maybe"}]}'));
            RLY_Release__c full = RlyReleaseStore.release(rel.Id);
            RLY_Work_Tracker__c off = new RLY_Work_Tracker__c(Type__c = 'ServiceNow', Named_Credential__c = 'RLY_Work_ServiceNow', Change_Mentions_Release__c = false);
            Test.startTest();
            Boolean held = RlyWorkGate.holds(full);
            RlyWorkTypes.Change notRequired = RlyWorkChangeMention.checked(RlyWorkTracker.change(off, 'CHG0012345'), off, rel.Name);
            Test.stopTest();
            System.assert(held, 'An approved change that doesn\'t name the release keeps the deploy waiting');
            System.assert(full.Error_Message__c.contains('doesn\'t mention ' + rel.Name), 'Says why: ' + full.Error_Message__c);
            System.assert(notRequired.allowed, 'A tracker with the check off lets it go: ' + notRequired.message);
            System.assert(RlyWorkChangeMention.mentions(new Map<String, Object>{ 'short_description' => 'Deploy rel-00052 tonight' }, 'REL-00052'), 'Any case');
            System.assert(RlyWorkChangeMention.mentions(new Map<String, Object>{ 'description' => 'For REL-00052.' }, 'REL-00052'), 'In the description');
            System.assert(!RlyWorkChangeMention.mentions(new Map<String, Object>{ 'description' => 'REL-000521' }, 'REL-00052'), 'The whole number');
            System.assert(!RlyWorkChangeMention.mentions(new Map<String, Object>{ 'description' => 'XREL-00052' }, 'REL-00052'), 'Not inside a word');
        }
    }

    @IsTest
    static void trackersKeepTheChangeMentionChoice() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyWorkTypes.Settings firstSave = RlyWorkTrackersController.saveTracker(JSON.serialize(new Map<String, Object>{ 'name' => 'Changes',
                'kind' => 'ServiceNow', 'ticketPattern' => 'CHG\\d{7}', 'active' => true }));
            Id trackerId = firstSave.trackers[0].id;
            RlyWorkTypes.Settings turnedOff = RlyWorkTrackersController.saveTracker(JSON.serialize(new Map<String, Object>{ 'id' => trackerId,
                'name' => 'Changes', 'kind' => 'ServiceNow', 'ticketPattern' => 'CHG\\d{7}', 'active' => true, 'changeMentionsRelease' => false }));
            Test.stopTest();
            System.assert(firstSave.trackers[0].changeMentionsRelease, 'On by default');
            System.assert(!turnedOff.trackers[0].changeMentionsRelease, 'Turned off');
            System.assertEquals(false, [SELECT Change_Mentions_Release__c FROM RLY_Work_Tracker__c WHERE Id = :trackerId].Change_Mentions_Release__c, 'Saved');
        }
    }

    @IsTest
    static void onlyTheRaiserApproversDeployTeamOrAdminsRunChecksAgain() {
        User plain = RlyTestData.plainUser();
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = RlyReleaseTestData.release('Checks failed', 'check');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
        }
        System.runAs(plain) {
            Test.startTest();
            String error;
            try {
                RlyApprovalService.rerunChecks(rel.Id);
            } catch (RlyReleaseException e) {
                error = e.getMessage();
            }
            Boolean plainMay = RlyReleaseAccess.mayRerunChecks(RlyReleaseStore.release(rel.Id));
            Test.stopTest();
            System.assert(error != null && error.contains('can run its checks again'), 'Refused: ' + error);
            System.assert(!plainMay, 'Not the raiser, no permission');
        }
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyReleaseAccess.mayRerunChecks(RlyReleaseStore.release(rel.Id)), 'The raiser may');
            System.assertEquals('Checks failed', [SELECT Status__c FROM RLY_Release__c WHERE Id = :rel.Id].Status__c, 'Nothing started');
        }
    }

    @IsTest
    static void onlyHttpsLinksFromResultsAreShown() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            String compareId = 'CMP-1762400000000';
            String payload = JSON.serialize(new Map<String, Object>{ 'request' => compareId, 'step' => 'compare', 'status' => 'Failed',
                'attempt' => 'tok', 'message' => 'Part 1 is broken.', 'runUrl' => 'javascript:alert(1)' });
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'results/' + compareId + '/compare.json')
                .reply(200, JSON.serialize(new Map<String, Object>{ 'payload' => payload })));
            Test.startTest();
            RlyComparePipelineResult.Result r = RlyCompareController.checkPipelineCompare(compareId, 'tok');
            Test.stopTest();
            System.assert(r.done && r.failed, 'The wrapped result is read: ' + r.message);
            System.assertEquals(null, r.runUrl, 'A javascript: link isn\'t shown');
            System.assertEquals('https://github.com/a/b/actions/runs/1', RlyRunMonitorInput.url('https://github.com/a/b/actions/runs/1'), 'https kept');
            System.assertEquals(null, RlyRunMonitorInput.url('http://github.com/a'), 'http dropped');
            System.assertEquals(null, RlyRunMonitorInput.url('https://a b'), 'Spaces dropped');
        }
    }

    @IsTest
    static void slackPayloadComesOnlyFromTheSignedBody() {
        System.runAs(RlyTestData.admin()) {
            String real = '{"type":"block_actions","team":{"id":"T1"}}';
            RestRequest req = signed(real, now());
            req.params.put('payload', '{"type":"view_submission","forged":true}');
            RestRequest wrongSig = signed(real, now());
            wrongSig.headers.put('X-Slack-Signature', 'v0=' + '0'.repeat(64));
            RestRequest old = signed(real, String.valueOf(System.now().getTime() / 1000 - 600));
            RestRequest form = new RestRequest();
            String stamp = now();
            form.params.put('payload', real);
            form.headers.put('X-Slack-Request-Timestamp', stamp);
            form.headers.put('X-Slack-Signature', RlySlackSignature.sign(SECRET, stamp, 'payload=' + EncodingUtil.urlEncode(real, 'UTF-8')));
            Test.startTest();
            String body = RlySlackSignature.verifiedBody(req, SECRET);
            String formBody = RlySlackSignature.verifiedBody(form, SECRET);
            Test.stopTest();
            System.assertEquals(real, RlySlackSignature.payloadOf(body), 'The signed body\'s payload, not the extra parameter');
            System.assertEquals(null, RlySlackSignature.verifiedBody(wrongSig, SECRET), 'A wrong signature');
            System.assertEquals(null, RlySlackSignature.verifiedBody(old, SECRET), 'Too old');
            System.assertEquals(null, RlySlackSignature.verifiedBody(req, null), 'No secret');
            System.assertEquals(real, RlySlackSignature.payloadOf(formBody), 'A form post Apex REST gave as parameters, rebuilt and verified');
            System.assertEquals(null, RlySlackSignature.payloadOf(null), 'Nothing verified');
        }
    }

    @IsTest
    static void slackPressesFromAnotherWorkspaceAreRefused() {
        System.runAs(RlyTestData.admin()) {
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Deployed');
            update new RLY_Notification__c(Id = s.Id, Slack_Team_Id__c = 'T0ACME1');
            RlySlack.forgetSettings();
            String fromElsewhere = '{"type":"block_actions","team":{"id":"T0OTHER"},"actions":[]}';
            String fromUs = '{"type":"block_actions","team":{"id":"T0ACME1"},"actions":[]}';
            Test.startTest();
            RlySlackAction.Reply other = RlySlackAction.handle(signed(fromElsewhere, now()));
            RlySlackAction.Reply ours = RlySlackAction.handle(signed(fromUs, now()));
            Test.stopTest();
            System.assertEquals(401, other.status, 'Another workspace is refused');
            System.assertEquals(200, ours.status, 'Ours is handled');
            RLY_Notification__c saved = RlySlack.settings();
            System.assert(!RlySlackTeam.isOurs(saved, new Map<String, Object>()), 'No team: refused once recorded');
            System.assert(RlySlackTeam.isOurs(new RLY_Notification__c(), new Map<String, Object>()), 'Not recorded yet: allowed');
        }
    }

    @IsTest
    static void testingTheSlackConnectionRecordsTheWorkspace() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('POST', 'callout:RLY_Slack/auth.test').reply(200, '{"ok":true,"team":"Acme","team_id":"T0ACME1","user":"relay"}'));
            Test.startTest();
            RlySlackController.SlackSettings out = RlySlackController.testSlack();
            Test.stopTest();
            System.assert(out.connected, 'Connected: ' + out.status);
            System.assertEquals('T0ACME1', RlySlackTeam.lastSeen(), 'Read from auth.test');
            System.assertEquals('T0ACME1', RlySlack.settings().Slack_Team_Id__c, 'Recorded');
            System.assert(RlySlackTeam.isTeamId('T0ACME1') && !RlySlackTeam.isTeamId('acme') && !RlySlackTeam.isTeamId(null), 'Team ID shape');
        }
    }

    @IsTest
    static void aLinkTokenOnlyForSomeoneWhoMatchesAUser() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RlyReleaseTestData.slackOn('Deployed');
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Map<String, Object> p = new Map<String, Object>{ 'user' => new Map<String, Object>{ 'id' => 'U0SOMEONE' },
                'channel' => new Map<String, Object>{ 'id' => 'C123' }, 'team' => new Map<String, Object>{ 'id' => 'T1' },
                'actions' => new List<Object>{ new Map<String, Object>{ 'action_id' => RlySlackCard.APPROVE_ACTION, 'value' => String.valueOf(rel.Id) } } };
            RlySlackPresser matched = new RlySlackPresser();
            matched.matched = true;
            Test.startTest();
            RlySlackPress press = new RlySlackPress(p);
            press.refuse(matched);
            String withLink = mock.bodyFor('chat.postEphemeral');
            press.refuse(new RlySlackPresser());
            String withoutLink = mock.bodyFor('chat.postEphemeral');
            Test.stopTest();
            System.assert(withLink.contains('Link my account'), 'Matched by email or SSO: the link: ' + withLink);
            System.assert(withoutLink.contains('Ask an admin to link you') && !withoutLink.contains('Link my account'), 'No match: ' + withoutLink);
        }
    }
}
