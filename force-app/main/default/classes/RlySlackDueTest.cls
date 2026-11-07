/**
 * @description Tests for Slack reminders, the daily digest, mentions and hotfix alerts (RlySlackDue, RlySlackDueRest,
 * RlySlackDueStore, RlySlackNudge, RlySlackAlert, RlySlackReminderController). Slack answers through RlyHttpMock; the
 * call's moment is set with RlySlackDue.testNow so hours and quiet times don't depend on when the test runs. Each test
 * runs through System.runAs as the active System Administrator with Release Relay Admin, linked to Slack as U1.
 */
@IsTest
private class RlySlackDueTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        User me = RlyTestData.admin();
        System.runAs(me) {
            update new User(Id = me.Id, RLY_Slack_Member_Id__c = 'U1');
        }
    }

    // Tomorrow at this hour in the hub's time zone (so everything inserted now waited at least 10 hours).
    private static Datetime tomorrowAt(Integer hour) {
        TimeZone tz = RlySlackDueReads.hubTimeZone();
        Datetime localNow = System.now().addSeconds(tz.getOffset(System.now()) / 1000);
        Datetime at = Datetime.newInstanceGmt(localNow.dateGmt().addDays(1), Time.newInstance(hour, 0, 0, 0));
        return at.addSeconds(-tz.getOffset(at) / 1000);
    }

    // SIT with reminders, the digest and mentions on, and a channel.
    private static RLY_Org__c sitWith(Boolean reminders, Boolean digest) {
        RLY_Org__c sit = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1];
        update new RLY_Org__c(Id = sit.Id, Slack_Channel__c = '#releases-sit', Slack_Reminders__c = reminders, Slack_Reminder_Hours__c = 2,
            Slack_Digest__c = digest, Slack_Digest_Hour__c = 8, Slack_Mentions__c = true);
        return sit;
    }

    private static Map<String, Object> call(Integer pass) {
        return RlySlackDue.handle(JSON.serialize(new Map<String, Object>{ 'pass' => pass, 'runUrl' => 'https://github.com/x/y/actions/runs/1' }));
    }

    @IsTest
    static void aReleaseWaitingForApprovalIsNudgedInItsThread() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', null);
            update new RLY_Release__c(Id = rel.Id, Slack_Channel_Id__c = 'C123', Slack_Ts__c = '1700.0001');
            RlyReleaseTestData.slackOn('');
            sitWith(true, false);
            RlySlackDue.testNow = tomorrowAt(14);
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Map<String, Object> first = call(1);
            Map<String, Object> again = call(2);
            Test.stopTest();
            System.assertEquals(1, first.get('sent'), 'One nudge: ' + first);
            System.assertEquals(true, first.get('done'), 'All handled');
            String body = mock.bodyFor('chat.postMessage');
            System.assert(body.contains('"thread_ts":"1700.0001"') && body.contains('for approval into SIT'), 'In the thread: ' + body);
            System.assert(body.contains('<@U1>'), 'The approvers are tagged: ' + body);
            System.assertNotEquals(null, [SELECT Slack_Reminded__c FROM RLY_Release__c WHERE Id = :rel.Id].Slack_Reminded__c, 'Remembered');
            System.assertEquals(0, again.get('sent'), 'Not again within the period: ' + again);
        }
    }

    @IsTest
    static void quietHoursAndOrgsWithRemindersOffSendNothing() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.release('Ready for approval', null);
            RlyReleaseTestData.slackOn('');
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyHttpMock()));
            Test.startTest();
            Map<String, Object> noOrg = call(1);
            sitWith(true, false);
            RlySlackDue.testNow = tomorrowAt(22);
            Map<String, Object> night = call(1);
            Test.stopTest();
            System.assertEquals(true, noOrg.get('skipped'), 'No org has them on: nothing read');
            System.assertEquals(0, night.get('sent'), 'Quiet at night');
            System.assert(String.valueOf(night.get('reason')).startsWith('Quiet hours'), 'Says why: ' + night);
        }
    }

    @IsTest
    static void deployedReleasesWithStepsToDoNudgeTheDeployTeam() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deployed', null);
            RLY_Org__c sit = sitWith(true, false);
            RLY_Manual_Step__c step = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Load regions', Category__c = 'Data',
                Timing__c = 'After_Deploy', Sequence__c = 1);
            insert step;
            insert new RLY_Manual_Step_Run__c(Step__c = step.Id, Release__c = rel.Id, Org__c = sit.Id, Status__c = 'To_Do');
            RlyReleaseTestData.slackOn('');
            RlySlackDue.testNow = tomorrowAt(10);
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Map<String, Object> out = call(1);
            Test.stopTest();
            String body = mock.bodyFor('chat.postMessage');
            System.assertEquals(1, out.get('sent'), 'One nudge: ' + out);
            System.assert(body.contains('#releases-sit') && body.contains('1 manual step to do'), 'In the channel (no card): ' + body);
        }
    }

    @IsTest
    static void theDigestGoesOutOnceADay() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', null);
            sitWith(false, true);
            RlyReleaseTestData.slackOn('');
            RlySlackDue.testNow = tomorrowAt(9);
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Map<String, Object> first = call(1);
            Map<String, Object> second = call(2);
            Test.stopTest();
            String body = mock.bodyFor('chat.postMessage');
            System.assertEquals(1, first.get('sent'), 'The digest: ' + first);
            System.assert(body.contains('daily digest') && body.contains('Waiting for approval: ' + rel.Name), 'Its lines: ' + body);
            System.assertEquals(0, second.get('sent'), 'Once a day');
            System.assertNotEquals(null, [SELECT Slack_Digest_Sent__c FROM RLY_Org__c WHERE Name = 'SIT'].Slack_Digest_Sent__c, 'Day saved');
        }
    }

    @IsTest
    static void skipsWhenSlackIsBusyOrOff() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.release('Ready for approval', null);
            sitWith(true, true);
            RLY_Notification__c slack = RlyReleaseTestData.slackOn('');
            RlySlackDue.testNow = tomorrowAt(15);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('POST', 'callout:RLY_Slack/').reply(429, '{"ok":false,"error":"ratelimited"}'));
            Test.startTest();
            Map<String, Object> busy = call(1);
            update new RLY_Notification__c(Id = slack.Id, Enabled__c = false);
            Map<String, Object> off = call(1);
            Test.stopTest();
            System.assertEquals(0, busy.get('sent'), 'Nothing sent while busy');
            System.assert(String.valueOf(busy.get('reason')).contains(RlySlackDue.BUSY), 'Waits for the next hour: ' + busy);
            System.assertEquals(true, off.get('skipped'), 'Slack off: skipped');
        }
    }

    @IsTest
    static void restAnswersJson() {
        System.runAs(RlyTestData.admin()) {
            RestContext.request = new RestRequest();
            RestContext.request.requestBody = Blob.valueOf('{"pass":1}');
            RestContext.response = new RestResponse();
            Test.startTest();
            RlySlackDueRest.send();
            Test.stopTest();
            Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
            System.assertEquals(200, RestContext.response.statusCode, 'Always 200');
            System.assertEquals(true, out.get('done'), 'Answered: ' + out);
        }
    }

    @IsTest
    static void aHotfixAlertsItsTargetEvenWithRemindersOff() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.hotfixRelease('Retrieving');
            RlyReleaseTestData.slackOn('');
            Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            update new RLY_Org__c(Id = targetId, Slack_Channel__c = '#releases-sit');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyReleaseTestData.withSlack(RlyFlowScenario.forRelease(rel).build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            String body = mock.bodyFor('chat.postMessage');
            System.assertNotEquals(null, body, 'Alert sent: ' + mock.callLog());
            System.assert(body.contains('Hotfix in progress') && body.contains('Duplicate emails in production'), 'With the reason: ' + body);
            System.assert(body.contains('<@U1>'), 'Names who raised it: ' + body);
        }
    }

    @IsTest
    static void mentionsFollowTheOrgsSwitch() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', null);
            RLY_Release__c full = [SELECT Id, Target_Org__c, CreatedById FROM RLY_Release__c WHERE Id = :rel.Id];
            Test.startTest();
            String off = RlySlackAlert.mentionsFor(full, 'Checks failed');
            sitWith(false, false);
            String failed = RlySlackAlert.mentionsFor(full, 'Checks failed');
            String ready = RlySlackAlert.mentionsFor(full, 'Ready for approval');
            String other = RlySlackAlert.mentionsFor(full, 'Deployed');
            Test.stopTest();
            System.assertEquals('', off, 'Mentions off: nobody tagged');
            System.assertEquals(' <@U1>', failed, 'The developer when checks fail');
            System.assertEquals(' <@U1>', ready, 'The approvers when ready');
            System.assertEquals('', other, 'Other events tag nobody');
        }
    }

    @IsTest
    static void adminsSaveTheSettings() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
            Test.startTest();
            RlySlackReminderController.Settings before = RlySlackReminderController.orgSettings(sitId);
            RlySlackReminderController.Settings saved = RlySlackReminderController.saveOrgSettings(sitId, JSON.serialize(
                new Map<String, Object>{ 'reminders' => true, 'hours' => 6, 'digest' => true, 'digestHour' => 9, 'mentions' => true,
                    'hotfixAlerts' => false }));
            String badHours;
            try {
                RlySlackReminderController.saveOrgSettings(sitId, '{"hours":0}');
            } catch (AuraHandledException e) {
                badHours = e.getMessage();
            }
            String badHour;
            try {
                RlySlackReminderController.saveOrgSettings(sitId, '{"digestHour":30}');
            } catch (AuraHandledException e) {
                badHour = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(false, before.reminders, 'Off by default');
            System.assertEquals(true, before.hotfixAlerts, 'Hotfix alerts on by default');
            System.assertEquals(RlySlackNudge.DEFAULT_HOURS, before.hours, 'Default hours');
            System.assertEquals(6, saved.hours, 'Saved hours');
            System.assertEquals(9, saved.digestHour, 'Saved hour');
            System.assertEquals(false, saved.hotfixAlerts, 'Hotfix alerts can be turned off');
            System.assert(saved.canEdit, 'Admins edit');
            System.assertEquals('Reminders wait 1 to 72 hours.', badHours, 'Hours checked');
            System.assertEquals('The digest hour is 0 to 23.', badHour, 'Hour checked');
        }
    }

    @IsTest
    static void wordsAndLimits() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c none = new RLY_Org__c(Name = 'X');
            RLY_Org__c big = new RLY_Org__c(Name = 'Y', Slack_Reminder_Hours__c = 500, Slack_Digest_Hour__c = -3);
            Test.startTest();
            String noDigest = RlySlackNudge.digest(none, new Map<String, List<RLY_Release__c>>(), Date.today());
            Date soon = Date.today().addDays(3);
            RLY_Org__c frozen = new RLY_Org__c(Name = 'PROD', Window_Time_Zone__c = 'America/Chicago',
                Window_Freezes__c = '[{"from":"' + String.valueOf(soon) + '","to":"' + String.valueOf(soon.addDays(2)) + '","reason":"Go-live week"}]');
            String freezeDigest = RlySlackNudge.digest(frozen, new Map<String, List<RLY_Release__c>>(), Date.today());
            String many = RlySlackNudge.mentions(new List<String>{ 'U1', 'U2', 'U3', 'U4', 'U5', 'U6', '' });
            Test.stopTest();
            System.assertEquals(RlySlackNudge.DEFAULT_HOURS, RlySlackNudge.hoursOf(none), 'Default hours');
            System.assertEquals(72, RlySlackNudge.hoursOf(big), 'At most 72');
            System.assertEquals(0, RlySlackNudge.digestHourOf(big), 'At least 0');
            System.assertEquals(null, noDigest, 'Nothing to say, no digest');
            System.assert(freezeDigest != null && freezeDigest.contains(':snowflake: PROD freeze starts') && freezeDigest.contains('Go-live week'),
                'A freeze within a week is in the digest: ' + freezeDigest);
            System.assertEquals(RlySlackDueStore.MAX_MENTIONS, many.countMatches('<@'), 'At most a few mentions');
        }
    }
}
