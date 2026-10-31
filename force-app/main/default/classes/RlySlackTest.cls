/**
 * @description Tests for Slack notifications (RlySlack, RlySlackMessage, RlySlackController,
 * RlySlackRules). Each test runs through System.runAs as an active System Administrator with Release Relay Admin
 * (or a new user without it). Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlySlackTest {

    private static final String WEBHOOK = 'https://hooks.slack.com/services/T000/B000/abcdWXYZ';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Notification__c slack(Boolean enabled, String events) {
        RLY_Notification__c s = new RLY_Notification__c(Name = 'Slack', Channel__c = 'Slack', Enabled__c = enabled,
            Webhook_URL__c = WEBHOOK, Events__c = events);
        insert s;
        return s;
    }

    private static RLY_Notification__c saved() {
        return [SELECT Enabled__c, Events__c, Last_Sent__c, Last_Result__c FROM RLY_Notification__c LIMIT 1];
    }

    private static String settingsJson(Boolean enabled, String url, List<String> events) {
        return JSON.serialize(new Map<String, Object>{ 'enabled' => enabled, 'webhookUrl' => url, 'events' => events });
    }

    @IsTest
    static void sendsWhenTheStatusChanges() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            slack(true, 'Ready for approval;Deployed');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            RlyHttpMock mock = scenario.build().match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Moved along');
            String body = mock.bodyFor('hooks.slack.com');
            System.assertNotEquals(null, body, 'Slack was told: ' + mock.callLog());
            System.assert(body.contains(rel.Name + ' · Ready for approval'), 'Header: ' + body);
            System.assert(body.contains('Region field') && body.contains('Open in Release Relay'), 'Title and button: ' + body);
            System.assert(body.contains('/lightning/n/RLY_My_Releases?c__release=' + rel.Id), 'Links to the release');
            System.assert(saved().Last_Result__c.startsWith('Sent: '), saved().Last_Result__c);
        }
    }

    @IsTest
    static void quietWhenOffOrNotSelected() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RLY_Notification__c s = slack(false, 'Ready for approval');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            RlyHttpMock mock = new RlyHttpMock().match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlack.notify(read, 'Ready for approval');
            update new RLY_Notification__c(Id = s.Id, Enabled__c = true, Events__c = 'Deployed');
            RlySlack.notify(read, 'Ready for approval');
            RlySlack.notifyTransition(read, 'Ready for approval');
            Test.stopTest();
            System.assert(mock.calls.isEmpty(), 'Nothing sent while off, for an unselected event, or without a change: ' + mock.calls);
            System.assertEquals(null, RlySlack.eventFor('Validating', 'Deploying'), 'Deploying isn\'t an event');
            System.assertEquals('Rejected', RlySlack.eventFor('Checks failed', 'Rejected'), 'Rejected is');
        }
    }

    @IsTest
    static void failedPostDoesntThrow() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
            update new RLY_Release__c(Id = rel.Id, Scan_Status__c = 'Failed', Scan_Blocking__c = 1, Validation_Status__c = 'Passed');
            slack(true, 'Checks failed');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            RlyHttpMock mock = new RlyHttpMock().match('POST', 'hooks.slack.com').reply(500, 'internal_error');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlack.notify(read, 'Checks failed');
            RlySlack.saveResults();
            Test.stopTest();
            System.assert(mock.bodyFor('hooks.slack.com').contains('Code scan: 1 blocking finding(s)'), 'The reason is in the message');
            System.assert(saved().Last_Result__c.contains('HTTP 500'), 'Recorded, not thrown: ' + saved().Last_Result__c);
            System.assertNotEquals(null, saved().Last_Sent__c, 'When');
        }
    }

    @IsTest
    static void raisedWhenThePipelineStarts() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            slack(true, 'Raised');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build().match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Workflow running', RlyReleaseTestData.reload(rel.Id).Status__c, 'Retrieved, pipeline started');
            String body = mock.bodyFor('hooks.slack.com');
            System.assertNotEquals(null, body, 'Slack was told: ' + mock.callLog());
            System.assert(body.contains(rel.Name + ' · Raised') && body.contains('Region field'), body);
            System.assertEquals('Sent: ' + rel.Name + ' · Raised', saved().Last_Result__c, 'Result saved after the callouts');
        }
    }

    @IsTest
    static void failedRetrieveIsntRaised() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            slack(true, 'Raised;Ready for approval;Checks failed;Deployed;Deploy failed;Rejected');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Failed';
            RlyHttpMock mock = scenario.build().match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Retrieve failed');
            System.assertEquals(null, mock.bodyFor('hooks.slack.com'), 'Failed isn\'t an event, and nothing was raised');
            System.assertEquals('Raised', RlySlack.eventFor('Retrieving', 'Workflow running'), 'The raise event');
            System.assertEquals(null, RlySlack.eventFor('Retrieving', 'Failed'), 'Not for a failed retrieve');
        }
    }

    @IsTest
    static void settingsAreCheckedAndTheUrlNeverReturned() {
        System.runAs(RlyTestData.admin()) {
            Integer refused = 0;
            List<String> bad = new List<String>{
                settingsJson(true, 'http://hooks.slack.com/services/T000/B000/x', null),
                settingsJson(true, 'https://hooks.slack.com/services/', null),
                settingsJson(true, 'https://hooks.slack.com/servicesX/T000', null),
                settingsJson(true, 'https://hooks.slack.com/services/T000 B000', null),
                settingsJson(true, null, null),
                settingsJson(false, WEBHOOK, new List<String>{ 'Approved' }),
                'not json'
            };
            for (String b : bad) {
                try {
                    RlySlackController.saveSlack(b);
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            System.assertEquals(bad.size(), refused, 'Only Slack webhook URLs, a URL to turn it on, known events, readable input');
            RlySlackController.SlackSettings shown = RlySlackController.saveSlack(settingsJson(true, ' ' + WEBHOOK + ' ',
                new List<String>{ 'Ready for approval', 'Deployed' }));
            System.assertEquals('Saved (ends ••••WXYZ)', shown.webhookHint, 'Masked hint');
            System.assert(!JSON.serialize(shown).contains('hooks.slack.com/services/T000'), 'The URL never goes to the page');
            System.assertEquals(2, shown.events.size(), 'Events saved');
            RlySlackController.saveSlack(settingsJson(true, '', new List<String>{ 'Deployed' }));
            System.assertEquals(WEBHOOK, RlySlack.settings().Webhook_URL__c, 'A blank URL keeps the saved one');
            System.assertEquals('Deployed', saved().Events__c, 'The edit is saved');

            RlyHttpMock mock = new RlyHttpMock().match('POST', 'hooks.slack.com').reply(200, 'ok');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlySlackController.SlackSettings tested = RlySlackController.sendSlackTest();
            Test.stopTest();
            System.assert(mock.bodyFor('hooks.slack.com').contains('Release Relay test message from https://'), mock.bodyFor('hooks.slack.com'));
            System.assert(tested.lastResult.startsWith('Sent: test message'), tested.lastResult);
        }
    }

    @IsTest
    static void onlyAdminsChangeIt() {
        System.runAs(RlyTestData.admin()) {
            slack(true, 'Deployed');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlySlackController.SlackSettings shown = RlySlackController.getSlack();
            System.assert(!shown.isAdmin && shown.webhookHint == null, 'Nothing for other users');
            Integer refused = 0;
            try { RlySlackController.saveSlack(settingsJson(false, null, null)); } catch (AuraHandledException e) { refused++; }
            try { RlySlackController.sendSlackTest(); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(2, refused, 'Admins only');
        }
    }
}
