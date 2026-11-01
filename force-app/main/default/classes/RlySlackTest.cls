/**
 * @description Tests for Slack notifications (RlySlack, RlySlackDelivery, RlySlackCard, RlySlackApi, RlySlackMessage,
 * RlySlackController, RlySlackRules, RlySlackDirectory). Each test runs through System.runAs as an active System
 * Administrator with Release Relay Admin (or a new user without it). Records are inserted before Test.startTest;
 * callouts come after it.
 */
@IsTest
private class RlySlackTest {

    private static final String WEBHOOK = 'https://hooks.slack.com/services/T000/B000/abcdWXYZ';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Notification__c saved() {
        return [SELECT Enabled__c, Events__c, Last_Sent__c, Last_Result__c, Signing_Secret__c FROM RLY_Notification__c LIMIT 1];
    }

    private static String settingsJson(Boolean enabled, List<String> events, String secret) {
        return JSON.serialize(new Map<String, Object>{ 'enabled' => enabled, 'events' => events, 'signingSecret' => secret });
    }

    private static Integer count(RlyHttpMock mock, String part) {
        return mock.callLog().countMatches(part);
    }

    @IsTest
    static void cardPostedWhenRaised() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyReleaseTestData.slackOn('Raised');
            RlyReleaseTestData.targetSlack(rel, 'Salesforce');
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Role__c = 'Developer' LIMIT 1].Id, Slack_Post__c = true, Slack_Channel__c = '#dev-team');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyReleaseTestData.withSlack(RlyFlowScenario.forRelease(rel).build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c afterRaise = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Workflow running', afterRaise.Status__c, 'Retrieved, pipeline started');
            System.assertEquals('C123', afterRaise.Slack_Channel_Id__c, 'Card channel saved');
            System.assertEquals('1700.0001', afterRaise.Slack_Ts__c, 'Card ts saved');
            System.assertEquals(3, count(mock, 'chat.postMessage'), 'Card, thread reply and the developer org copy: ' + mock.callLog());
            String copy = mock.bodyFor('chat.postMessage');
            System.assert(copy.contains('#dev-team') && copy.contains('Raised from'), 'Copy to the developer channel: ' + copy);
            System.assert(saved().Last_Result__c.startsWith('Sent: ' + rel.Name), saved().Last_Result__c);
        }
    }

    @IsTest
    static void laterEventsEditTheCard() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            update new RLY_Release__c(Id = rel.Id, Slack_Channel_Id__c = 'C123', Slack_Ts__c = '1700.0001');
            RlyReleaseTestData.slackOn('Ready for approval');
            RlyReleaseTestData.targetSlack(rel, 'Slack');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":2,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            RlyHttpMock mock = RlyReleaseTestData.withSlack(scenario.build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Moved along');
            String card = mock.bodyFor('chat.update');
            System.assertNotEquals(null, card, 'Card edited: ' + mock.callLog());
            System.assert(card.contains('"ts":"1700.0001"') && card.contains(RlySlackCard.APPROVE_ACTION), 'Approve in Slack: ' + card);
            System.assert(card.contains('Scan (2 findings)') && card.contains('Open in ' + System.Label.RLY_App_Name), card);
            String reply = mock.bodyFor('chat.postMessage');
            System.assert(reply.contains('"thread_ts":"1700.0001"') && reply.contains('Checks passed'), 'Thread reply: ' + reply);
        }
    }

    @IsTest
    static void webhookWhenTheAppIsntSetUp() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Ready for approval');
            update new RLY_Notification__c(Id = s.Id, Webhook_URL__c = WEBHOOK);
            RlyReleaseTestData.targetSlack(rel, 'Salesforce');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            RlyHttpMock mock = new RlyHttpMock().match('POST', 'callout:RLY_Slack/').reply(200, '{"ok":false,"error":"not_authed"}')
                .match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlack.notify(read, 'Ready for approval');
            RlySlack.saveResults();
            Test.stopTest();
            String body = mock.bodyFor('hooks.slack.com');
            System.assert(body != null && body.contains(rel.Name + ' · Ready for approval'), 'Webhook used: ' + mock.callLog());
            System.assert(saved().Last_Result__c.startsWith('Sent: '), saved().Last_Result__c);
        }
    }

    @IsTest
    static void refusedCardIsRecordedNotThrown() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, Scan_Status__c = 'Failed', Scan_Blocking__c = 1, Validation_Status__c = 'Passed');
            RlyReleaseTestData.slackOn('Checks failed');
            RlyReleaseTestData.targetSlack(rel, 'Salesforce');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('POST', 'callout:RLY_Slack/').reply(200, '{"ok":false,"error":"channel_not_found"}'));
            Test.startTest();
            RlySlack.notify(read, 'Checks failed');
            RlySlack.saveResults();
            Test.stopTest();
            System.assert(saved().Last_Result__c.contains('channel_not_found'), 'Recorded: ' + saved().Last_Result__c);
            System.assertNotEquals(null, saved().Last_Sent__c, 'When');
        }
    }

    @IsTest
    static void legacyWebhookWithoutChannels() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, Scan_Status__c = 'Failed', Scan_Blocking__c = 1, Validation_Status__c = 'Passed');
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Checks failed');
            update new RLY_Notification__c(Id = s.Id, Webhook_URL__c = WEBHOOK);
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            RlyHttpMock mock = new RlyHttpMock().match('POST', 'hooks.slack.com').reply(500, 'internal_error');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlack.notify(read, 'Checks failed');
            RlySlack.saveResults();
            Test.stopTest();
            System.assert(mock.bodyFor('hooks.slack.com').contains('Code scan: 1 blocking finding(s)'), 'The reason is in the message');
            System.assert(saved().Last_Result__c.contains('HTTP 500'), 'Recorded, not thrown: ' + saved().Last_Result__c);
            System.assertEquals(0, count(mock, 'RLY_Slack'), 'No app calls without a channel');
        }
    }

    @IsTest
    static void noSlackAtAll() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id, Approval_In__c = 'Slack');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            RlyHttpMock mock = scenario.build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals('Ready for approval', d.release.Status__c, 'The release moves along');
            System.assertEquals(null, d.release.Error_Message__c, 'No error');
            System.assertEquals('Salesforce', d.approvedIn, 'Approve in Slack falls back while Slack is off');
            System.assertEquals(null, d.slackUrl, 'No card');
            System.assert(!mock.callLog().contains('slack'), 'No Slack calls: ' + mock.callLog());
            System.assert(!RlySlack.isOn() && !RlySlack.wants('Deployed'), 'Off');
            for (RlyOrgController.ApprovalOption o : RlyOrgController.approvalOptions()) {
                System.assertNotEquals('Slack', o.value, 'No Slack option');
            }
        }
    }

    @IsTest
    static void eventsAndQuietCases() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Deployed');
            update new RLY_Notification__c(Id = s.Id, Enabled__c = false);
            RlyReleaseTestData.targetSlack(rel, 'Salesforce');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlack.notify(read, 'Ready for approval');
            update new RLY_Notification__c(Id = s.Id, Enabled__c = true);
            RlySlack.notify(read, 'Ready for approval');
            RlySlack.notifyTransition(read, 'Ready for approval');
            Test.stopTest();
            System.assert(mock.calls.isEmpty(), 'Nothing sent while off, for an unselected event, or without a change: ' + mock.calls);
            System.assertEquals(RlySlack.APPROVED, RlySlack.eventFor('Ready for approval', 'Deploying'), 'Approved');
            System.assertEquals('Rejected', RlySlack.eventFor('Checks failed', 'Rejected'), 'Rejected');
            System.assertEquals('Raised', RlySlack.eventFor('Retrieving', 'Workflow running'), 'Raised');
            System.assertEquals(null, RlySlack.eventFor('Retrieving', 'Failed'), 'Not for a failed retrieve');
            System.assert(RlySlack.wants(RlySlack.APPROVED), 'Approvals edit the card whenever Slack is on');
        }
    }

    @IsTest
    static void cardLines() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            update new RLY_Release__c(Id = rel.Id, Approved_Via__c = 'Slack', Approval_Status__c = 'Approved', Deploy_Status__c = 'Deploying',
                Scan_Status__c = 'Bypassed', Validation_Status__c = 'Passed', PR_Number__c = 7, Approval_Comment__c = 'Split it',
                Error_Message__c = 'Test failure');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            String target = read.Target_Org__r.Name;
            System.assert(RlySlackCard.statusLine(read, 'Ana').contains('Deploying to ' + target), RlySlackCard.statusLine(read, 'Ana'));
            System.assert(RlySlackReply.forEvent(read, RlySlack.APPROVED, 'Ana').contains('Approved by Ana (Slack)'), 'Approved reply');
            System.assert(RlySlackCard.stepsLine(read).contains('PR #7') && RlySlackCard.stepsLine(read).contains(':warning: Scan'), RlySlackCard.stepsLine(read));
            read.Status__c = 'Deployed';
            read.Deploy_Status__c = 'Deployed';
            System.assert(RlySlackCard.statusLine(read, 'Ana').contains('approved by Ana in Slack'), RlySlackCard.statusLine(read, 'Ana'));
            System.assertEquals(':rocket: Deployed to ' + target, RlySlackReply.forEvent(read, 'Deployed', 'Ana'), 'Deployed reply');
            read.Status__c = 'Rejected';
            System.assert(RlySlackReply.forEvent(read, 'Rejected', 'Ana').contains('Rejected by Ana: “Split it”'), 'Rejected');
            read.Status__c = 'Deploy failed';
            System.assert(RlySlackReply.forEvent(read, 'Deploy failed', null).contains('failed: Test failure'), 'Deploy failed');
            System.assert(RlySlackCard.statusLine(read, null).startsWith(':x:'), 'Failed emoji');
            read.Status__c = 'Validating';
            read.Pending_Run__c = 'resolve';
            System.assert(RlySlackCard.statusLine(read, null).contains('Resolving conflicts'), 'Phase');
            System.assert(RlySlackReply.forEvent(read, 'Checks failed', null).startsWith(':red_circle: Checks failed'), 'Checks failed');
            System.assert(RlySlackReply.forEvent(read, 'Raised', null).contains('Raised from DEV1'), 'Raised');
        }
    }

    @IsTest
    static void connectionCardSaves() {
        System.runAs(RlyTestData.admin()) {
            Integer refused = 0;
            List<String> bad = new List<String>{
                settingsJson(true, new List<String>{ 'Approved' }, null),
                settingsJson(true, null, 'too short'),
                'not json'
            };
            for (String b : bad) {
                try {
                    RlySlackController.saveSlack(b);
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            System.assertEquals(bad.size(), refused, 'Known events, a real secret, readable input');
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyHttpMock()));
            Test.startTest();
            RlySlackController.SlackSettings shown = RlySlackController.saveSlack(settingsJson(true, null, RlyReleaseTestData.SIGNING_SECRET));
            Test.stopTest();
            System.assertEquals(RlySlack.EVENTS.size(), shown.events.size(), 'Turning Slack on selects every event');
            System.assertEquals('Saved (ends ••••4f2a)', shown.signingSecretHint, 'Masked hint');
            System.assert(!JSON.serialize(shown).contains(RlyReleaseTestData.SIGNING_SECRET), 'The secret never goes to the page');
            System.assert(shown.connected && shown.workspace == 'Acme' && shown.status == 'Connected', 'auth.test: ' + shown.status);
            System.assert(shown.approversTotal >= 1, 'The admin is an approver');
            RlySlackController.saveSlack(settingsJson(true, new List<String>{ 'Deployed' }, ''));
            System.assertEquals(RlyReleaseTestData.SIGNING_SECRET, saved().Signing_Secret__c, 'A blank secret keeps the saved one');
            System.assertEquals('Deployed', saved().Events__c, 'The edit is saved');
        }
    }

    @IsTest
    static void testMessageGoesToTheChannel() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Boolean badChannel = false;
            try {
                RlySlackController.sendSlackTest('not a channel');
            } catch (AuraHandledException e) {
                badChannel = true;
            }
            System.assert(badChannel, 'Channel checked');
            Test.startTest();
            RlySlackController.SlackSettings tested = RlySlackController.sendSlackTest('#releases');
            Test.stopTest();
            System.assert(mock.bodyFor('chat.postMessage').contains(System.Label.RLY_App_Name + ' test message from https://'), mock.bodyFor('chat.postMessage'));
            System.assert(tested.lastResult.startsWith('Sent: test message to #releases'), tested.lastResult);
            System.assert(tested.enabled, 'On');
        }
    }

    @IsTest
    static void notSetUpAndLinks() {
        User me = RlyTestData.admin();
        System.runAs(me) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('POST', 'callout:RLY_Slack/').reply(200, '{"ok":false,"error":"not_authed"}'));
            Test.startTest();
            RlySlackController.SlackSettings shown = RlySlackController.testSlack();
            System.assertEquals('Not set up', shown.status, 'No token yet');
            System.assert(!shown.connected, 'Not connected');
            shown = RlySlackController.saveSlackMember(me.Id, ' u0abc123 ');
            Test.stopTest();
            System.assertEquals('U0ABC123', [SELECT RLY_Slack_Member_Id__c FROM User WHERE Id = :me.Id].RLY_Slack_Member_Id__c, 'Linked');
            System.assert(shown.approversLinked >= 1, 'Counted');
            Integer refused = 0;
            try { RlySlackController.saveSlackMember(me.Id, 'bad id'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.saveSlackMember(null, 'U0ABC123'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.sendSlackTest('#releases'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(3, refused, 'Member ID format, a user, and settings before a test message');
            System.assertEquals(null, RlySlackDirectory.approverFor(null), 'No member');
        }
    }

    @IsTest
    static void onlyAdminsChangeIt() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlySlackController.SlackSettings shown = RlySlackController.getSlack();
            System.assert(!shown.isAdmin && shown.signingSecretHint == null, 'Nothing for other users');
            Integer refused = 0;
            try { RlySlackController.saveSlack(settingsJson(false, null, null)); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.sendSlackTest('#releases'); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.testSlack(); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.saveSlackMember(plain.Id, 'U0ABC123'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Admins only');
        }
    }
}
