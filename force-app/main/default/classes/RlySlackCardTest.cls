/**
 * @description Tests that a release's Slack card always shows its current state (RlySlackCardSync, RlySlackCardState,
 * RlySlackCard): the card is edited on every change it shows, whatever events are selected; Approve and Reject give way
 * to a line saying who decided; held, failed and deployed releases say why and how. Each test runs through
 * System.runAs as an active System Administrator with Release Relay Admin. Records are inserted before Test.startTest;
 * callouts come after it.
 */
@IsTest
private class RlySlackCardTest {

    private static final String CHANNEL = 'C123';
    private static final String CARD_TS = '1700.0001';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A release in a status, with its card already posted, read the way the hub reads it.
    private static RLY_Release__c withCard(String status, String approvalIn) {
        RLY_Release__c rel = RlyReleaseTestData.release(status, 'hub');
        update new RLY_Release__c(Id = rel.Id, Slack_Channel_Id__c = CHANNEL, Slack_Ts__c = CARD_TS);
        RlyReleaseTestData.targetSlack(rel, approvalIn);
        return RlyReleaseStore.release(rel.Id);
    }

    private static RlyHttpMock slackMock() {
        RlyHttpMock mock = RlyReleaseTestData.withSlack(new RlyHttpMock());
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void deployedEditsTheCardWhenTheEventIsntSelected() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Raised');
            RLY_Release__c rel = withCard('Deploying', 'Slack');
            RLY_Release__c prior = rel.clone(true, true, true, true);
            rel.Status__c = 'Deployed';
            rel.Deploy_Status__c = 'Deployed';
            rel.Approval_Status__c = 'Approved';
            rel.Deploy_Result__c = '{"deployId":"0Af000000000001","quick":true}';
            RlyHttpMock mock = slackMock();
            Test.startTest();
            RlySlackCardSync.notifyChange(prior, rel);
            RlySlack.saveResults();
            Test.stopTest();
            String card = mock.bodyFor('chat.update');
            System.assertNotEquals(null, card, 'Card edited: ' + mock.callLog());
            System.assert(card.contains('"ts":"' + CARD_TS + '"') && card.contains('quick deploy'), card);
            System.assert(!card.contains(RlySlackCard.APPROVE_ACTION), 'No Approve once deployed: ' + card);
            System.assert(!mock.callLog().contains('chat.postMessage'), 'No extra messages: ' + mock.callLog());
        }
    }

    @IsTest
    static void rejectedCardSaysWhoInsteadOfButtons() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Raised');
            RLY_Release__c rel = withCard('Ready for approval', 'Slack');
            RLY_Release__c prior = rel.clone(true, true, true, true);
            rel.Status__c = 'Rejected';
            rel.Approval_Status__c = 'Rejected';
            rel.Approved_Via__c = 'Slack';
            RlyHttpMock mock = slackMock();
            Test.startTest();
            RlySlackCardSync.notifyChange(prior, rel);
            RlySlack.saveResults();
            Test.stopTest();
            String card = mock.bodyFor('chat.update');
            System.assertNotEquals(null, card, 'Card edited: ' + mock.callLog());
            System.assert(card.contains('Rejected') && card.contains('The approval is closed'), card);
            System.assert(!card.contains(RlySlackCard.APPROVE_ACTION), 'Buttons gone: ' + card);
        }
    }

    @IsTest
    static void failedDeployShowsTheReason() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.slackOn('Raised');
            RLY_Release__c rel = withCard('Deploying', 'Salesforce');
            RLY_Release__c prior = rel.clone(true, true, true, true);
            rel.Status__c = 'Deploy failed';
            rel.Error_Message__c = 'PayClient: Invalid type';
            RlyHttpMock mock = slackMock();
            Test.startTest();
            RlySlackCardSync.notifyChange(prior, rel);
            RlySlack.saveResults();
            Test.stopTest();
            String card = mock.bodyFor('chat.update');
            System.assert(card != null && card.contains('failed') && card.contains('PayClient'), 'Reason shown: ' + card);
        }
    }

    @IsTest
    static void nothingCalledWithoutAChangeOrWithSlackOff() {
        System.runAs(RlyTestData.admin()) {
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Raised');
            RLY_Release__c rel = withCard('Deploying', 'Salesforce');
            RlyHttpMock mock = slackMock();
            Test.startTest();
            RlySlackCardSync.notifyChange(rel.clone(true, true, true, true), rel);
            RlySlackCardSync.notifyChange(null, rel);
            update new RLY_Notification__c(Id = s.Id, Enabled__c = false);
            RLY_Release__c prior = rel.clone(true, true, true, true);
            rel.Status__c = 'Deployed';
            RlySlackCardSync.notifyChange(prior, rel);
            Test.stopTest();
            System.assert(!mock.callLog().contains('chat.'), 'No Slack calls: ' + mock.callLog());
            System.assert(!RlySlackCardState.changed(rel, rel), 'Same release: no change');
        }
    }

    @IsTest
    static void cardLinesForEachState() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = withCard('Ready for approval', 'Slack');
            System.assert(RlySlackCardState.awaitsApprover(rel), 'Waits for a decision');
            System.assertEquals(null, RlySlackCardState.decisionLine(rel, null), 'Nothing decided yet');
            System.assert(JSON.serialize(RlySlackCard.card(rel, null)).contains(RlySlackCard.APPROVE_ACTION), 'Approve offered');

            rel.Approval_Status__c = 'Approved';
            rel.Approved_Via__c = 'Salesforce';
            System.assert(!RlySlackCardState.awaitsApprover(rel), 'Decided');
            System.assert(RlySlackCardState.decisionLine(rel, 'Ana').contains('Approved by'), RlySlackCardState.decisionLine(rel, 'Ana'));
            String held = RlySlackCardState.heldOrFailedLine(rel, 'Ana');
            System.assert(held != null && held.contains('approved'), 'Approved, waiting to deploy: ' + held);
            System.assert(!JSON.serialize(RlySlackCard.card(rel, 'Ana')).contains(RlySlackCard.APPROVE_ACTION), 'Buttons gone');

            rel.Approved_Via__c = RlyReleaseLog.VIA_RULE;
            System.assert(RlySlackCardState.approvedText(rel, null).contains('automatically'), RlySlackCardState.approvedText(rel, null));

            rel.Status__c = 'Checks failed';
            rel.Approval_Status__c = null;
            System.assert(RlySlackCardState.heldOrFailedLine(rel, null).contains('Checks failed'), 'Checks failed line');

            rel.Status__c = 'Deployed';
            System.assertEquals(null, RlySlackCardState.heldOrFailedLine(rel, null), 'Deployed has its own line');
            rel.Deploy_Result__c = '{"deployId":"0Af000000000002","quick":false,"testsRun":12}';
            System.assertEquals(' (full deploy, 12 tests run)', RlySlackCardState.deployHow(rel), 'Full deploy');
            rel.Deploy_Result__c = null;
            System.assertEquals('', RlySlackCardState.deployHow(rel), 'No deploy result');
            System.assertEquals('', RlySlackCardState.mergedBackLine(rel), 'Nothing merged back');
            rel.Back_Merge_Result__c = '[{"branch":"sit","status":"Synced"}]';
            System.assert(RlySlackCardState.mergedBackLine(rel).contains('Branches merged back'), RlySlackCardState.mergedBackLine(rel));
            System.assertEquals(1, RlySlackCardState.decisionBlocks(new RLY_Release__c(Status__c = 'Rejected'), null).size(), 'Rejected block');
        }
    }
}
