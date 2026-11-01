/**
 * @description Tests for Approve and Reject from Slack (RlySlackActions, RlySlackAction, RlySlackSignature): the
 * signature and age check, the linked approver, the org approved in Slack, the reject form, and refusals. Each test
 * runs as an active System Administrator holding Release Relay Approver, linked to Slack member U0TEST01.
 */
@IsTest
private class RlySlackActionsTest {

    private static final String MEMBER = 'U0TEST01';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
        User me = RlyTestData.admin();
        System.runAs(me) {
            update new User(Id = me.Id, RLY_Slack_Member_Id__c = MEMBER);
        }
    }

    private static RLY_Release__c readyInSlack() {
        RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Slack_Channel_Id__c = 'C123', Slack_Ts__c = '1700.0001');
        RlyReleaseTestData.slackOn('Deployed;Rejected');
        RlyReleaseTestData.targetSlack(rel, 'Slack');
        return rel;
    }

    private static String button(String actionId, Id releaseId, String member) {
        return JSON.serialize(new Map<String, Object>{ 'type' => 'block_actions', 'trigger_id' => 'trig1',
            'user' => new Map<String, Object>{ 'id' => member }, 'channel' => new Map<String, Object>{ 'id' => 'C123' },
            'actions' => new List<Object>{ new Map<String, Object>{ 'action_id' => actionId, 'value' => String.valueOf(releaseId) } } });
    }

    private static String form(Id releaseId, String reason) {
        Map<String, Object> values = new Map<String, Object>{ RlySlackAction.REASON_BLOCK => new Map<String, Object>{
            RlySlackAction.REASON_INPUT => new Map<String, Object>{ 'value' => reason } } };
        return JSON.serialize(new Map<String, Object>{ 'type' => 'view_submission', 'user' => new Map<String, Object>{ 'id' => MEMBER },
            'view' => new Map<String, Object>{ 'callback_id' => RlySlackAction.REJECT_FORM, 'private_metadata' => String.valueOf(releaseId),
                'state' => new Map<String, Object>{ 'values' => values } } });
    }

    // Sends a signed request (as a raw body, or as Apex REST parameters for 'params') and returns the response.
    private static RestResponse send(String payloadJson, Integer ageSeconds, String shape) {
        String stamp = String.valueOf(System.now().getTime() / 1000 - ageSeconds);
        String body = 'payload=' + EncodingUtil.urlEncode(payloadJson, 'UTF-8');
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/rly/slack/actions';
        if (shape == 'params') {
            req.params.put('payload', payloadJson);
        } else {
            req.requestBody = Blob.valueOf(body);
        }
        req.headers.put('X-Slack-Request-Timestamp', stamp);
        req.headers.put('X-Slack-Signature', RlySlackSignature.sign(RlyReleaseTestData.SIGNING_SECRET, stamp, body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RlySlackActions.receive();
        return RestContext.response;
    }

    @IsTest
    static void approveFromSlack() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyFlowScenario().build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RestResponse res = send(button(RlySlackCard.APPROVE_ACTION, rel.Id, MEMBER), 0, 'body');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals(200, res.statusCode, 'Answered');
            System.assertEquals('Deploying', saved.Status__c, 'Merging: ' + saved.Error_Message__c);
            System.assertEquals('Slack', saved.Approved_Via__c, 'Approved in Slack');
            System.assertEquals(RlyTestData.admin().Id, saved.Approved_By__c, 'For the linked user');
            System.assert(mock.bodyFor('chat.update') != null, 'Card edited: ' + mock.callLog());
        }
    }

    @IsTest
    static void approveAsFormParameters() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyFlowScenario().build()));
            Test.startTest();
            send(button(RlySlackCard.APPROVE_ACTION, rel.Id, MEMBER), 10, 'params');
            Test.stopTest();
            System.assertEquals('Deploying', RlyReleaseTestData.reload(rel.Id).Status__c, 'Signature checked on the rebuilt body');
        }
    }

    @IsTest
    static void refusesBadOrOldRequests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyFlowScenario().build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RestResponse old = send(button(RlySlackCard.APPROVE_ACTION, rel.Id, MEMBER), 600, 'body');
            RestRequest forged = RestContext.request;
            forged.headers.put('X-Slack-Signature', 'v0=forged');
            forged.headers.put('X-Slack-Request-Timestamp', String.valueOf(System.now().getTime() / 1000));
            RlySlackActions.receive();
            RestResponse bad = RestContext.response;
            Test.stopTest();
            System.assertEquals(401, old.statusCode, 'Older than five minutes');
            System.assertEquals(401, bad.statusCode, 'Bad signature');
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Nothing happened');
            System.assert(mock.calls.isEmpty(), 'No calls: ' + mock.calls);
        }
    }

    @IsTest
    static void unlinkedUserIsToldPrivately() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            send(button(RlySlackCard.APPROVE_ACTION, rel.Id, 'U0OTHER9'), 0, 'body');
            Test.stopTest();
            String whisper = mock.bodyFor('chat.postEphemeral');
            System.assert(whisper != null && whisper.contains('You can\'t approve ' + rel.Name), 'Ephemeral: ' + mock.callLog());
            System.assert(whisper.contains('link your Slack account in ' + System.Label.RLY_App_Name + ' → Pipeline'), whisper);
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Not approved');
        }
    }

    @IsTest
    static void orgNotApprovedInSlackIsRefused() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyReleaseTestData.targetSlack(rel, 'Salesforce');
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            send(button(RlySlackCard.APPROVE_ACTION, rel.Id, MEMBER), 0, 'body');
            Test.stopTest();
            System.assert(mock.bodyFor('chat.postEphemeral') != null, 'Told privately');
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Not approved');
        }
    }

    @IsTest
    static void rejectOpensTheForm() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            send(button(RlySlackCard.REJECT_ACTION, rel.Id, MEMBER), 0, 'body');
            Test.stopTest();
            String view = mock.bodyFor('views.open');
            System.assert(view != null && view.contains('"trigger_id":"trig1"') && view.contains(String.valueOf(rel.Id)), 'Form: ' + mock.callLog());
            System.assert(view.contains('Why are you rejecting?'), view);
        }
    }

    @IsTest
    static void rejectFormRejects() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyFlowScenario().build());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RestResponse res = send(form(rel.Id, 'Split the layout change out'), 0, 'body');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('', res.responseBody.toString(), 'Form closes');
            System.assertEquals('Rejected', saved.Status__c, 'Rejected');
            System.assertEquals('Slack', saved.Approved_Via__c, 'In Slack');
            System.assert(mock.bodyFor('/issues/42/comments').contains('Rejected in Slack by'), 'Reason on the pull request');
        }
    }

    @IsTest
    static void rejectFormNeedsAReason() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyHttpMock()));
            Test.startTest();
            RestResponse res = send(form(rel.Id, ''), 0, 'body');
            Test.stopTest();
            System.assert(res.responseBody.toString().contains('"response_action":"errors"'), res.responseBody.toString());
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Not rejected');
        }
    }

    @IsTest
    static void slackOffRefusesEverything() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            Test.startTest();
            RestResponse res = send(button(RlySlackCard.APPROVE_ACTION, rel.Id, MEMBER), 0, 'body');
            Test.stopTest();
            System.assertEquals(401, res.statusCode, 'No Slack record');
            System.assertEquals('You can\'t approve this release. Ask an admin to link your Slack account in '
                + System.Label.RLY_App_Name + ' → Pipeline.', RlySlackAction.refusal(null), 'Refusal');
        }
    }
}
