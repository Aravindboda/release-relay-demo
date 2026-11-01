/**
 * @description Tests for first-run setup (RlySetupStatus, RlyOrgController.getHubDefaults) and the Slack bot token
 * saved from the Pipeline tab (RlySlackController.saveBotToken, RlyBotToken). ConnectApi credentials can't be written in
 * a test, so the token store is replaced with a fake; the real store is only run against an External Credential that
 * doesn't exist. Every test runs through System.runAs as an active System Administrator with Release Relay Admin (or a
 * new user without it).
 */
@IsTest
private class RlySetupStatusTest {

    private static final String BOT_TOKEN = 'xoxb-1234567890-abcdefghij-WXYZ';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // Keeps only what the controller hands to the store, so the test can check it.
    private class FakeStore extends RlyBotToken {
        public Integer calls = 0;
        public String lastFour;

        public override void store(String token) {
            calls++;
            lastFour = token.right(4);
        }
    }

    @IsTest
    static void statusFollowsSetup() {
        System.runAs(RlyTestData.admin()) {
            RlySetupStatus.SetupStatus fresh = RlySetupStatus.getSetupStatus();
            System.assert(fresh.needsSetup && !fresh.hubRegistered && !fresh.gitSaved, 'Nothing set up yet');
            System.assertEquals(0, fresh.orgCount, 'No orgs');
            RlyReleaseTestData.route();
            RlySetupStatus.SetupStatus routed = RlySetupStatus.getSetupStatus();
            System.assert(routed.hubRegistered && routed.gitSaved && routed.gitConnected, 'Hub and Git saved and connected');
            System.assertEquals(false, routed.needsSetup, 'Setup done');
            System.assertEquals(false, routed.pipelineFilesFound, 'Files not reported by a check yet');
            System.assertEquals(2, routed.orgCount, 'Two orgs besides the hub');
            System.assertEquals(false, routed.slackConnected, 'No Slack');
            RLY_Git_Connection__c g = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            update new RLY_Git_Connection__c(Id = g.Id, Status_Message__c = 'Repository reachable.\nPipeline files found on main.');
            RLY_Notification__c s = RlyReleaseTestData.slackOn('Deployed');
            update new RLY_Notification__c(Id = s.Id, Last_Result__c = 'Sent: test message to #channel-name');
            RlySetupStatus.SetupStatus done = RlySetupStatus.getSetupStatus();
            System.assert(done.pipelineFilesFound && done.slackConnected, 'Files found and Slack sent');
        }
    }

    @IsTest
    static void hubDefaultsComeFromThisOrg() {
        System.runAs(RlyTestData.admin()) {
            RlyOrgController.OrgDefaults d = RlyOrgController.getHubDefaults();
            System.assertEquals(UserInfo.getOrganizationId(), d.orgId, 'This org');
            System.assert(d.myDomain.startsWith('https://') && !d.myDomain.endsWith('/'), d.myDomain);
            System.assertEquals(null, d.name, 'No name suggested');
        }
    }

    @IsTest
    static void botTokenSavedWithHintOnly() {
        System.runAs(RlyTestData.admin()) {
            FakeStore fake = new FakeStore();
            RlySlackController.tokenStore = fake;
            RlySlackController.SlackSettings out = RlySlackController.saveBotToken('  ' + BOT_TOKEN + ' ');
            System.assertEquals(1, fake.calls, 'Stored once');
            System.assertEquals('WXYZ', fake.lastFour, 'Trimmed token stored');
            System.assertEquals('Saved (ends ••••WXYZ)', out.botTokenHint, 'Masked hint');
            System.assert(!JSON.serialize(out).contains(BOT_TOKEN), 'Token never returned');
            RLY_Notification__c row = [SELECT Bot_Token_Hint__c, Enabled__c FROM RLY_Notification__c LIMIT 1];
            System.assertEquals('WXYZ', row.Bot_Token_Hint__c, 'Only the last four kept');
            System.assertEquals(false, row.Enabled__c, 'Slack not switched on by saving a token');
            RlySlackController.saveBotToken(BOT_TOKEN.replace('WXYZ', 'ABCD'));
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Notification__c], 'Same record updated');
            System.assertEquals('ABCD', [SELECT Bot_Token_Hint__c FROM RLY_Notification__c LIMIT 1].Bot_Token_Hint__c, 'New hint');
        }
    }

    @IsTest
    static void badTokensRefused() {
        System.runAs(RlyTestData.admin()) {
            FakeStore fake = new FakeStore();
            RlySlackController.tokenStore = fake;
            Integer refused = 0;
            for (String bad : new List<String>{ null, '  ', 'xoxp-1234567890-abcdefghij', 'xoxb-short', 'xoxb-12345 67890abc' }) {
                try {
                    RlySlackController.saveBotToken(bad);
                } catch (AuraHandledException e) {
                    refused++;
                    System.assert(bad == null || String.isBlank(bad) || !e.getMessage().contains(bad), 'Token not echoed');
                }
            }
            System.assertEquals(5, refused, 'Every bad token refused');
            System.assertEquals(0, fake.calls, 'Nothing stored');
        }
    }

    @IsTest
    static void onlyAdminsSaveTheToken() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            String message;
            try {
                RlySlackController.saveBotToken(BOT_TOKEN);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assert(message != null && message.contains('Admin permission set'), 'Admins only: ' + message);
        }
    }

    @IsTest
    static void tokenHelpers() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('Saved in Setup', RlyBotToken.hint(null, RlyBotToken.CONNECTED), 'Connected without a hint');
            System.assertEquals(null, RlyBotToken.hint(null, 'Not set up'), 'Nothing saved');
            String failed = RlyBotToken.failure('Bad value ' + BOT_TOKEN, BOT_TOKEN);
            System.assert(!failed.contains(BOT_TOKEN) && failed.contains('••••'), 'Token blanked out: ' + failed);
            System.assert(RlyBotToken.failure(null, null).contains('no reason given'), 'No reason');
            Boolean leaked = false;
            try {
                new RlyBotToken('RLY_Missing_Credential').store(BOT_TOKEN);
            } catch (Exception e) {
                leaked = e.getMessage() != null && e.getMessage().contains(BOT_TOKEN);
            }
            System.assertEquals(false, leaked, 'A failed save never shows the token');
        }
    }
}
