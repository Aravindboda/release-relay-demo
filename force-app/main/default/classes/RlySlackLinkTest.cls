/**
 * @description Tests for linking from Slack: the on-the-spot SSO match when an unlinked approver presses Approve
 * (RlySlackPresser, RlySlackPress, RlySlackAction), the private "Link my account" and "You can't approve releases"
 * replies, and the Link your Slack account page (RlySlackLink: signed token, expiry, taken, Self link). Each test runs
 * through System.runAs as the active System Administrator with Release Relay Approver, or as a new approver.
 */
@IsTest
private class RlySlackLinkTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    // A new active approver (System Administrator profile + RLY_Approver) with a Federation ID that is an email.
    private static User approver(String last) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        String tag = last.toLowerCase() + '.' + Datetime.now().getTime() + '.' + Math.abs(Crypto.getRandomInteger());
        User u = new User(Alias = last.left(8), Email = tag + '@rly-mail.example.com', EmailEncodingKey = 'UTF-8', LastName = last,
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId, TimeZoneSidKey = 'America/Chicago',
            Username = 'rly.' + tag + '@example.com', FederationIdentifier = tag + '@rly-sso.example.com');
        Id setId = [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Approver' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = setId);
        }
        return [SELECT Id, Name, FederationIdentifier FROM User WHERE Id = :u.Id];
    }

    private static String slackUser(String id, String email) {
        return '{"ok":true,"user":{"id":"' + id + '","name":"x","team_id":"T1","profile":{"email":"' + email + '","real_name":"Slack ' + id + '"}}}';
    }

    private static RestResponse press(Id releaseId, String member) {
        String payload = JSON.serialize(new Map<String, Object>{ 'type' => 'block_actions', 'trigger_id' => 'trig1',
            'user' => new Map<String, Object>{ 'id' => member }, 'channel' => new Map<String, Object>{ 'id' => 'C123' },
            'team' => new Map<String, Object>{ 'id' => 'T1' },
            'actions' => new List<Object>{ new Map<String, Object>{ 'action_id' => RlySlackCard.APPROVE_ACTION, 'value' => String.valueOf(releaseId) } } });
        String stamp = String.valueOf(System.now().getTime() / 1000);
        String body = 'payload=' + EncodingUtil.urlEncode(payload, 'UTF-8');
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestURI = '/services/apexrest/rly/slack/actions';
        req.requestBody = Blob.valueOf(body);
        req.headers.put('X-Slack-Request-Timestamp', stamp);
        req.headers.put('X-Slack-Signature', RlySlackSignature.sign(RlyReleaseTestData.SIGNING_SECRET, stamp, body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RlySlackActions.receive();
        return RestContext.response;
    }

    private static RLY_Release__c readyInSlack() {
        RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Slack_Channel_Id__c = 'C123', Slack_Ts__c = '1700.0001');
        RlyReleaseTestData.slackOn('Deployed;Rejected');
        RlyReleaseTestData.targetSlack(rel, 'Slack');
        return rel;
    }

    @IsTest
    static void unlinkedApproverIsMatchedBySsoOnApprove() {
        User ann = approver('Annpress');
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyFlowScenario().build()
                .match('GET', 'users.info').reply(200, slackUser('U0ANNP', ann.FederationIdentifier)));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            press(rel.Id, 'U0ANNP');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'Counted: ' + saved.Error_Message__c + ' ' + mock.callLog());
            System.assertEquals(ann.Id, saved.Approved_By__c, 'As Ann');
            User a = [SELECT RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c FROM User WHERE Id = :ann.Id];
            System.assertEquals('U0ANNP', a.RLY_Slack_Member_Id__c, 'Linked on the spot');
            System.assertEquals('SSO', a.RLY_Slack_Linked_By__c, 'By SSO');
        }
    }

    @IsTest
    static void nonApproverIsRefused() {
        User plain = RlyTestData.plainUser();
        System.runAs(new User(Id = RlyTestData.admin().Id)) {
            update new User(Id = plain.Id, RLY_Slack_Member_Id__c = 'U0PLAIN');
        }
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            press(rel.Id, 'U0PLAIN');
            Test.stopTest();
            System.assert(mock.bodyFor('chat.postEphemeral').contains('You can\'t approve releases. Ask a ' + System.Label.RLY_App_Name + ' admin.'),
                mock.bodyFor('chat.postEphemeral'));
            System.assertEquals('Ready for approval', RlyReleaseTestData.reload(rel.Id).Status__c, 'Not approved');
        }
    }

    @IsTest
    static void selfLinkPage() {
        User ann = approver('Annlink');
        User ex = approver('Exlink');
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Deployed');
        }
        System.runAs(new User(Id = RlyTestData.admin().Id)) {
            update new User(Id = ex.Id, RLY_Slack_Member_Id__c = 'U0TAKEN');
        }
        String secret = RlyReleaseTestData.SIGNING_SECRET;
        String good = RlySlackLink.token('U0ANNL', 'T1', secret);
        String taken = RlySlackLink.token('U0TAKEN', 'T1', secret);
        String oldBody = 'U0ANNL.T1.' + (System.now().addMinutes(-1).getTime() / 1000) + '.abc';
        String expired = oldBody + '.' + RlySlackLink.mac(oldBody, secret);
        System.assert(RlySlackLink.url(good, null).contains('/lightning/n/RLY_Slack_Link?c__t=U0ANNL.'), 'Link page URL');
        System.runAs(ann) {
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'users.info').reply(200, slackUser('U0ANNL', ann.FederationIdentifier)));
            Test.startTest();
            RlySlackLink.LinkView v = RlySlackLink.readLink(good);
            System.assertEquals(RlySlackLink.READY, v.state, v.message);
            System.assertEquals('U0ANNL', v.memberId, 'From the token');
            System.assert(v.emailMatches, 'Slack email is the Federation ID');
            System.assertEquals('Approver', v.meAccess, 'Approver');
            System.assertEquals(RlySlackLink.INVALID, RlySlackLink.readLink(good.replace('U0ANNL', 'U0EVIL')).state, 'Tampered');
            System.assertEquals(RlySlackLink.INVALID, RlySlackLink.readLink('nonsense').state, 'Not a token');
            System.assertEquals(RlySlackLink.EXPIRED, RlySlackLink.readLink(expired).state, 'Too old');
            System.assertEquals(RlySlackLink.TAKEN, RlySlackLink.readLink(taken).state, 'Someone else has it');
            Integer refused = 0;
            try { RlySlackLink.confirmLink(taken); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(1, refused, 'Nothing changed');
            v = RlySlackLink.confirmLink(good);
            Test.stopTest();
            System.assertEquals(RlySlackLink.LINKED, v.state, 'Linked');
        }
        User a = [SELECT RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c, RLY_Slack_Linked_By_User__c FROM User WHERE Id = :ann.Id];
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('U0ANNL', a.RLY_Slack_Member_Id__c, 'Saved');
            System.assertEquals('Self', a.RLY_Slack_Linked_By__c, 'By the approver');
            System.assertEquals(ann.Id, a.RLY_Slack_Linked_By_User__c, 'Who');
        }
    }

    @IsTest
    static void unlinkedPersonGetsTheLinkButtonAndNonApproverPageRefuses() {
        User plain = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyInSlack();
            RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock())
                .match('GET', 'users.info').reply(200, slackUser('U0NOBODY', 'nobody@example.com'));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            press(rel.Id, 'U0NOBODY');
            Test.stopTest();
            String whisper = mock.bodyFor('chat.postEphemeral');
            System.assert(whisper.contains(RlySlackPress.notLinkedText('Approve')) && whisper.contains('Link my account'), whisper);
        }
        System.runAs(plain) {
            String token = RlySlackLink.token('U0NOBODY', null, RlyReleaseTestData.SIGNING_SECRET);
            System.assertEquals(RlySlackLink.NOT_APPROVER, RlySlackLink.readLink(token).state, 'Not an approver');
        }
    }
}
