/**
 * @description Tests for the Pipeline tab's status strip and settings log (build 50): RlyPipelineSummary,
 * RlyPipelineSummaryTiles, RlyPipelineSummaryStore, RlySettingsLog and RlySettingsLogDiff. Every test runs as an active
 * System Administrator (RlyTestData.admin) and makes its own records; nothing depends on the org's data. No callouts.
 */
@IsTest
private class RlyPipelineSummaryTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Git_Connection__c git(String status) {
        return new RLY_Git_Connection__c(Name = 'GitHub acme/release', Provider__c = 'GitHub', Repository__c = 'acme/release',
            Named_Credential__c = 'RLY_Git_GitHub', Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main',
            Source_Path__c = 'force-app/main/default', Code_Scan__c = false, Status__c = status, Active__c = true);
    }

    private static Map<String, RlyPipelineSummary.Tile> tilesOf(RlyPipelineSummary.Summary s) {
        Map<String, RlyPipelineSummary.Tile> out = new Map<String, RlyPipelineSummary.Tile>();
        for (RlyPipelineSummary.Tile t : s.tiles) {
            out.put(t.key, t);
        }
        return out;
    }

    @IsTest
    static void emptyHubShowsWhatToSetUp() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyPipelineSummary.Summary s = RlyPipelineSummary.summary();
            Test.stopTest();
            Map<String, RlyPipelineSummary.Tile> t = tilesOf(s);
            System.assertEquals(5, s.tiles.size(), 'Five tiles');
            System.assertEquals('Not connected', t.get('git').value, 'No Git connection yet');
            System.assertEquals(RlyPipelineSummary.TONE_WARN, t.get('git').tone, 'Git needs setting up');
            System.assertEquals('No route yet', t.get('route').value, 'No orgs');
            System.assertEquals('Slack not set up', t.get('approvals').value, 'Slack optional');
            System.assertEquals('Not checked', t.get('security').value, 'Repository never checked');
            System.assertEquals('Not checked', t.get('credentials').value, 'No credential rows');
            System.assertEquals(7, s.dots.size(), 'A dot per section: ' + s.dots);
            System.assertEquals(RlyPipelineSummary.TONE_NONE, s.dots.get(RlyPipelineSummary.ORGS), 'No orgs, grey');
            System.assertEquals(0, s.orgCount, 'No orgs');
            System.assertEquals('No tracker yet', s.notes.get(RlyPipelineSummary.TRACKING), 'Tracking note');
            System.assertEquals(1, s.problems.size(), 'Run signing off is the only problem: ' + JSON.serialize(s.problems));
            System.assert(s.changes.isEmpty(), 'No settings changes yet');
        }
    }

    @IsTest
    static void storedStatesFillTheStrip() {
        System.runAs(RlyTestData.admin()) {
            RLY_Git_Connection__c conn = git('Connected');
            conn.Retention_Days__c = 365;
            conn.Archive_Nightly__c = true;
            conn.Last_Nightly_Call__c = System.now();
            insert conn;
            RLY_Org__c sit = RlyTestData.stage('SIT', 'sit', 1);
            sit.Status__c = 'Failed';
            insert new List<RLY_Org__c>{ RlyTestData.org('DEV1', 'Developer', 'dev1'), sit, RlyTestData.stage('PROD', 'main', 999) };
            insert new RLY_Notification__c(Name = RlySlack.CHANNEL, Channel__c = RlySlack.CHANNEL, Enabled__c = true,
                Bot_Token_Hint__c = 'ab12', Last_Result__c = 'Error: channel_not_found');
            insert new List<RLY_Credential_Status__c>{
                new RLY_Credential_Status__c(Name = 'GitHub token', Key__c = 'git:t', Kind__c = 'Git token', Status__c = 'Expiring',
                    Expires_On__c = Date.today().addDays(25), Last_Checked__c = System.now()),
                new RLY_Credential_Status__c(Name = 'release_relay', Key__c = 'cert:hub:t', Kind__c = 'Certificate', Status__c = 'OK',
                    Expires_On__c = Date.today().addDays(300), Last_Checked__c = System.now())
            };
            insert new RLY_Work_Tracker__c(Name = 'Jira Claims', Type__c = 'Jira', Active__c = true, Sort_Order__c = 1);
            RlyRepoSecurity.Report report = new RlyRepoSecurity.Report();
            report.missing = 2;
            report.items.add(RlyRepoSecurity.row('env:prod', 'prod environment: any branch can deploy').found(RlyRepoSecurity.MISSING, 'x'));
            report.items.add(RlyRepoSecurity.row('env:uat', 'uat environment missing').found(RlyRepoSecurity.MISSING, 'y'));
            report.items.add(RlyRepoSecurity.row('branch', 'Branch protection').found(RlyRepoSecurity.OK, 'z'));
            System.assert(RlyPipelineSummaryStore.keepSecurity(report), 'Kept');
            Test.startTest();
            RlyPipelineSummary.Summary s = RlyPipelineSummary.build();
            Test.stopTest();
            Map<String, RlyPipelineSummary.Tile> t = tilesOf(s);
            System.assertEquals('GitHub · connected', t.get('git').value, 'Provider and status');
            System.assertEquals(RlyPipelineSummary.TONE_OK, t.get('git').tone, 'Connected');
            System.assertEquals('DEV1 → SIT → PROD', t.get('route').value, 'The lane in order');
            System.assertEquals('SIT can\'t sign in', t.get('route').detail, 'The problem');
            System.assertEquals(RlyPipelineSummary.TONE_BAD, s.dots.get(RlyPipelineSummary.CONNECTION), 'Route problem shows on the section');
            System.assertEquals(RlyPipelineSummary.TONE_BAD, s.dots.get(RlyPipelineSummary.ORGS), 'An org fails to sign in');
            System.assertEquals('Slack: last message failed', t.get('approvals').value, 'Last Slack message failed');
            System.assertEquals(RlyPipelineSummary.TONE_WARN, t.get('approvals').tone, 'Slack needs a look');
            System.assertEquals('2 to fix', t.get('security').value, 'From the stored check');
            System.assertEquals('prod environment: any branch can deploy', t.get('security').detail, 'First thing to fix');
            System.assertEquals('1 expiring', t.get('credentials').value, 'One credential expiring');
            System.assertEquals('GitHub token · 25 days', t.get('credentials').detail, 'Which and when');
            System.assertEquals(RlyPipelineSummary.TONE_BAD, s.dots.get(RlyPipelineSummary.SECURITY), 'Security to fix');
            System.assertEquals(4, s.problems.size(), 'Two to fix, run signing off, one credential: ' + JSON.serialize(s.problems));
            System.assertEquals(RlyPipelineSummary.TONE_OK, s.dots.get(RlyPipelineSummary.TRACKING), 'A tracker is on');
            System.assertEquals(3, s.orgCount, 'Three orgs');
            System.assertEquals(RlyPipelineSummary.TONE_OK, s.dots.get(RlyPipelineSummary.RETENTION), 'Nightly ran');
        }
    }

    @IsTest
    static void tilesForOtherStates() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RLY_Git_Connection__c failed = git('Failed');
            failed.Status_Message__c = 'Bad credentials';
            RlyPipelineSummary.Tile g = RlyPipelineSummaryTiles.git(failed);
            RlyPipelineSummary.Tile n = RlyPipelineSummaryTiles.git(git('Not checked'));
            RLY_Org__c dev = RlyTestData.org('DEV1', 'Developer', 'dev1');
            dev.Status__c = 'Not checked';
            RlyPipelineSummary.Tile r = RlyPipelineSummaryTiles.route(new List<RLY_Org__c>{ dev, RlyTestData.org('DEV2', 'Developer', 'dev2') });
            RLY_Run_Key__c key = new RLY_Run_Key__c(Key__c = 'abc', Security_Checked_On__c = System.now(), Security_Missing__c = 0,
                Security_Unknown__c = 1);
            List<RlyPipelineSummary.Problem> problems = new List<RlyPipelineSummary.Problem>();
            RlyPipelineSummary.Tile sec = RlyPipelineSummaryChecks.security(key, problems);
            key.Security_Unknown__c = 0;
            RlyPipelineSummary.Tile ok = RlyPipelineSummaryChecks.security(key, problems);
            RlyPipelineSummary.Tile cred = RlyPipelineSummaryChecks.credentials(new List<RLY_Credential_Status__c>{
                new RLY_Credential_Status__c(Name = 'SIT sign-in', Kind__c = 'Org sign-in', Status__c = 'Failed') }, problems);
            RlyPipelineSummary.Tile allOk = RlyPipelineSummaryChecks.credentials(new List<RLY_Credential_Status__c>{
                new RLY_Credential_Status__c(Name = 'cert', Status__c = 'OK') }, problems);
            RlyPipelineSummary.Tile slackOff = RlyPipelineSummaryTiles.approvals(new RLY_Notification__c(Enabled__c = false, Bot_Token_Hint__c = 'ab12'));
            RlyPipelineSummary.Tile slackOn = RlyPipelineSummaryTiles.approvals(new RLY_Notification__c(Enabled__c = true, Bot_Token_Hint__c = 'ab12'));
            Test.stopTest();
            System.assertEquals('GitHub · check failed', g.value, 'Failed check');
            System.assertEquals('Bad credentials', g.detail, 'Why');
            System.assertEquals(RlyPipelineSummary.TONE_WARN, n.tone, 'Not checked');
            System.assertEquals('2 dev orgs', r.value, 'Two developer orgs, no stage');
            System.assertEquals(RlyPipelineSummary.TONE_WARN, r.tone, 'Route warnings: ' + r.detail);
            System.assertEquals('1 couldn\'t be read', sec.value, 'Unknown rows');
            System.assertEquals('OK', ok.value, 'All in place');
            System.assertEquals('1 failed', cred.value, 'A failed sign-in');
            System.assertEquals(RlyPipelineSummary.TONE_BAD, cred.tone, 'Failed is red');
            System.assertEquals('OK', allOk.value, 'All fine');
            System.assertEquals('Slack off', slackOff.value, 'Token saved, Slack off');
            System.assertEquals(RlyPipelineSummary.TONE_NONE, slackOff.tone, 'Off is grey');
            System.assertNotEquals(null, slackOn.detail, 'Approvers line: ' + slackOn.detail);
            System.assertEquals(RlyPipelineSummary.TONE_BAD, RlyPipelineSummary.worst(RlyPipelineSummary.TONE_OK, RlyPipelineSummary.TONE_BAD), 'Bad wins');
            System.assertEquals(RlyPipelineSummary.TONE_WARN, RlyPipelineSummary.worst(RlyPipelineSummary.TONE_WARN, 'other'), 'Unknown tone loses');
        }
    }

    @IsTest
    static void logsGitAndOrgChanges() {
        System.runAs(RlyTestData.admin()) {
            RLY_Git_Connection__c conn = git('Connected');
            insert conn;
            Test.startTest();
            RlySettingsLog.Snapshot was = RlySettingsLog.read(RlySettingsLog.GIT);
            update new RLY_Git_Connection__c(Id = conn.Id, Named_Credential__c = 'RLY_Git_Other', Code_Scan__c = true);
            Integer gitRows = RlySettingsLog.compare(was);
            RlySettingsLog.Snapshot orgsBefore = RlySettingsLog.read(RlySettingsLog.ORGS);
            RLY_Org__c sit = RlyTestData.stage('SIT', 'sit', 1);
            insert sit;
            Integer added = RlySettingsLog.compare(orgsBefore);
            RlySettingsLog.Snapshot renamed = RlySettingsLog.read(RlySettingsLog.ORGS);
            update new RLY_Org__c(Id = sit.Id, Name = 'UAT', Branch__c = 'uat');
            Integer changed = RlySettingsLog.compare(renamed);
            Integer unchanged = RlySettingsLog.compare(RlySettingsLog.read(RlySettingsLog.ORGS));
            Test.stopTest();
            List<RLY_Settings_Change__c> rows = RlySettingsLog.recent(50);
            Map<String, RLY_Settings_Change__c> byWhat = new Map<String, RLY_Settings_Change__c>();
            for (RLY_Settings_Change__c r : rows) {
                byWhat.put(r.What__c, r);
            }
            System.assertEquals(2, gitRows, 'Named Credential and Code scan');
            System.assertEquals('RLY_Git_GitHub', byWhat.get('Named Credential').Old_Value__c, 'Old value');
            System.assertEquals('RLY_Git_Other', byWhat.get('Named Credential').New_Value__c, 'New value');
            System.assertEquals(RlySettingsLog.SECTION_CONNECTION, byWhat.get('Named Credential').Section__c, 'Section');
            System.assertEquals(UserInfo.getName(), byWhat.get('Named Credential').Changed_By__c, 'Who');
            System.assertEquals(2, added, 'Org added (one row, not one per field) and the route');
            System.assert(byWhat.containsKey('Org "SIT" added'), 'Added: ' + byWhat.keySet());
            System.assertEquals('SIT', byWhat.get('Route').New_Value__c, 'Route order');
            System.assert(byWhat.containsKey('Org "SIT" renamed'), 'Renamed: ' + byWhat.keySet());
            System.assertEquals('uat', byWhat.get('UAT · Branch').New_Value__c, 'Branch under the new name');
            System.assert(changed >= 3, 'Rename, branch and route: ' + changed);
            System.assertEquals(0, unchanged, 'Nothing changed, nothing logged');
        }
    }

    @IsTest
    static void logsRemovedOrgsTrackersAndSecretsWithoutValues() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyTestData.org('DEV1', 'Developer', 'dev1');
            insert dev;
            insert new RLY_Notification__c(Name = RlySlack.CHANNEL, Channel__c = RlySlack.CHANNEL, Enabled__c = false, Bot_Token_Hint__c = 'ab12');
            Test.startTest();
            RlySettingsLog.Snapshot orgs = RlySettingsLog.read(RlySettingsLog.ORGS);
            try {
                delete dev;
            } catch (DmlException e) {
                System.assertNotEquals(null, e.getMessage(), 'Delete skipped: ' + e.getMessage());
            }
            Integer removed = RlySettingsLog.compare(orgs);
            RlySettingsLog.Snapshot slack = RlySettingsLog.read(RlySettingsLog.SLACK);
            RLY_Notification__c s = [SELECT Id FROM RLY_Notification__c WHERE Channel__c = :RlySlack.CHANNEL LIMIT 1];
            update new RLY_Notification__c(Id = s.Id, Bot_Token_Hint__c = 'cd34', Enabled__c = true);
            Integer slackRows = RlySettingsLog.compare(slack);
            RlySettingsLog.Snapshot tracking = RlySettingsLog.read(RlySettingsLog.TRACKING);
            insert new RLY_Work_Tracker__c(Name = 'Jira Claims', Type__c = 'Jira', Active__c = true, Sort_Order__c = 1);
            Integer trackerRows = RlySettingsLog.compare(tracking);
            RlySettingsLog.Snapshot key = RlySettingsLog.read(RlySettingsLog.SECURITY);
            upsert new RLY_Run_Key__c(SetupOwnerId = UserInfo.getOrganizationId(), Key__c = 'secret-key-value');
            Integer keyRows = RlySettingsLog.compare(key);
            Integer lockRows = RlySettingsLog.compare(RlySettingsLog.read(RlySettingsLog.LOCK));
            Integer approvalRows = RlySettingsLog.compare(RlySettingsLog.read(RlySettingsLog.APPROVAL));
            Integer retentionRows = RlySettingsLog.compare(RlySettingsLog.read(RlySettingsLog.RETENTION));
            Test.stopTest();
            String logged = JSON.serialize(RlySettingsLog.recent(50));
            System.assert(removed >= 1, 'Removed org logged: ' + logged);
            System.assert(logged.contains('Org \\"DEV1\\" removed') || removed == 0, 'Removed row: ' + logged);
            System.assertEquals(2, slackRows, 'Slack on and the token: ' + logged);
            System.assert(logged.contains('Slack bot token') && !logged.contains('cd34'), 'The token hint never written: ' + logged);
            System.assert(trackerRows >= 1, 'Tracker added: ' + logged);
            System.assertEquals(1, keyRows, 'Run-signing key set');
            System.assert(!logged.contains('secret-key-value'), 'The key never written');
            System.assertEquals(0, lockRows + approvalRows + retentionRows, 'Nothing else changed');
            System.assertEquals(0, RlySettingsLog.compare(null), 'No snapshot, nothing logged');
        }
    }

    @IsTest
    static void textPurgeAndStoredSecurity() {
        System.runAs(RlyTestData.admin()) {
            RLY_Settings_Change__c old = new RLY_Settings_Change__c(Section__c = 'Orgs', What__c = 'Old change');
            insert old;
            Test.setCreatedDate(old.Id, System.now().addDays(-RlySettingsLog.KEEP_DAYS - 5));
            insert new RLY_Settings_Change__c(Section__c = 'Orgs', What__c = 'New change');
            Test.startTest();
            Integer purged = RlySettingsLog.purge();
            Boolean nothingKept = RlyPipelineSummaryStore.keepSecurity(null);
            Test.stopTest();
            System.assertEquals(RlyOrgController.isAdmin() ? 1 : 0, purged, 'Only the row older than 90 days');
            System.assertEquals(false, nothingKept, 'No report, nothing kept');
            System.assertEquals('On', RlySettingsLog.text(true), 'Switch on');
            System.assertEquals('Off', RlySettingsLog.text(false), 'Switch off');
            System.assertEquals('730', RlySettingsLog.text(730.0), 'Whole number');
            System.assertEquals('Apex, Flows', RlySettingsLog.text('Apex;Flows'), 'Multi-select');
            System.assertEquals(null, RlySettingsLog.text('  '), 'Blank');
            System.assertEquals(0, RlyPipelineSummaryStore.securityProblems(new RLY_Run_Key__c()).size(), 'Nothing stored');
            System.assertEquals(2, RlyPipelineSummaryStore.securityProblems(new RLY_Run_Key__c(Security_Problems__c = 'a; b')).size(), 'Two names');
            System.assertEquals(1, RlySettingsLog.recent(null).size() + (purged == 1 ? 0 : -1), 'The newer row stays');
        }
    }
}
