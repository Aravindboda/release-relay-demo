/**
 * @description Tests for rolling a deployed release back (RlyRollback, RlyRollbackRun, RlyRollbackPlan,
 * RlyRollbackPreview, RlyRollbackState, RlyRollbackView, RlyRollbackController) and where a rollback shows: the release
 * page (RlyReleasesController), the Releases tab's rolled back state and counts (RlyReleaseQuery, RlyReleaseRows), the
 * CSV and evidence PDF (RlyEvidenceController, RlyEvidenceHtml, RlyEvidenceTables) and the Slack card line. Route
 * DEV1 -> SIT -> PROD (hub). Each test runs through System.runAs as an active System Administrator with Release Relay
 * Admin (or a new user without it). Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyRollbackTest {

    private static final String TOKEN = 'tok00000000000000000000000000001';
    private static final String MANIFEST = '{"request":"x","takenAt":"2026-11-01T09:11:00.000Z","existing":["ApexClass:AccountService"],'
        + '"added":["ApexClass:AccountRetry"],"deleted":[]}';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A release deployed to SIT two hours ago, whose deploy took a snapshot.
    private static RLY_Release__c deployed() {
        RLY_Release__c rel = RlyReleaseTestData.release('Deployed', 'merge');
        update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved', Deploy_Status__c = 'Deployed',
            Approved_On__c = System.now().addHours(-2), Deploy_Result__c = '{"status":"Deployed","finishedAt":"2026-11-01T09:12:00.000Z",'
            + '"snapshot":{"branch":"release-relay-snapshots","path":"' + rel.Name + '/sit/abc","existing":1,"added":1}}');
        return rel;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RlyHttpMock mock() {
        return new RlyHttpMock()
            .match('GET', '/manifest.json').reply(200, MANIFEST)
            .match('POST', '/dispatches').reply(204, '');
    }

    private static String request(Id org, String reason, String tests) {
        return JSON.serialize(new Map<String, Object>{ 'orgId' => org, 'reason' => reason, 'tests' => tests });
    }

    // A rollback of the release in SIT that is running with TOKEN.
    private static void running(RLY_Release__c rel) {
        update new RLY_Release__c(Id = rel.Id, Rollback_Status__c = 'Running', Rollback_Org__c = orgId('SIT'),
            Rollback_By__c = UserInfo.getUserId(), Rollback_On__c = System.now().addMinutes(-5), Rollback_Reason__c = 'Payments failing',
            Rollback_Token__c = TOKEN, Rollback_Result__c = '{"request":"' + rel.Name + '","snapshot":"' + rel.Name + '/sit/abc"}');
        RlyRollbackState.forget();
    }

    @IsTest
    static void choicesFollowTheRoute() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            Id devId = orgId('DEV1');
            RLY_Release__c promotion = new RLY_Release__c(Title__c = 'SIT to PROD', Status__c = 'Deployed', Mode__c = 'Org changes',
                Request_Type__c = 'Changes', Release_Type__c = 'Promotion', Source_Org__c = devId, Target_Org__c = orgId('PROD'),
                Target_Branch__c = 'prod', Deploy_Result__c = '{"status":"Deployed","snapshot":{"error":"retrieve failed"}}',
                Carried_Releases__c = String.valueOf(rel.Id));
            insert promotion;
            update new RLY_Release__c(Id = rel.Id, Promoted_In__c = promotion.Id);
            Test.startTest();
            List<RlyRollbackPlan.OrgChoice> choices = RlyRollbackController.rollbackChoices(rel.Id);
            Test.stopTest();
            System.assertEquals(2, choices.size(), 'SIT, then PROD through the promotion');
            System.assertEquals('SIT', choices[0].orgName, 'Route order');
            System.assert(choices[0].hasSnapshot, 'SIT has a snapshot');
            System.assertEquals(false, choices[0].production, 'SIT is a sandbox');
            System.assertEquals(false, choices[1].hasSnapshot, 'PROD has none');
            System.assertEquals('Snapshot failed', choices[1].why, 'Why');
            System.assert(choices[1].production && choices[1].byPromotion, 'PROD is production, by the promotion');
        }
    }

    @IsTest
    static void previewReadsTheManifest() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            RLY_Release__c later = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('b'));
            update new RLY_Release__c(Id = later.Id, Approved_On__c = System.now(), Deploy_Result__c = '{"finishedAt":"2026-11-01T11:40:00.000Z"}');
            insert new RLY_Release_Item__c(Release__c = later.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService');
            Test.setMock(HttpCalloutMock.class, mock());
            Test.startTest();
            RlyRollbackPreview.Preview p = RlyRollbackController.previewRollback(rel.Id, orgId('SIT'));
            Test.stopTest();
            System.assertEquals(new List<String>{ 'ApexClass:AccountService' }, p.restore, 'Restores what the org had');
            System.assertEquals(new List<String>{ 'ApexClass:AccountRetry' }, p.remove, 'Removes what the deploy added');
            System.assert(p.apex, 'Apex is in it');
            System.assertNotEquals(null, p.takenOn, 'Taken on');
            System.assertEquals(1, p.later.size(), 'A later release changed AccountService: ' + p.later);
            System.assert(p.later[0].startsWith(later.Name + ' also deployed AccountService to SIT'), p.later[0]);
        }
    }

    @IsTest
    static void startDispatchesTheRollback() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            update new RLY_Org__c(Id = orgId('SIT'), Environment__c = 'Production');
            RlyHttpMock m = mock();
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), ' Payments failing ', 'release'));
            Test.stopTest();
            RLY_Release__c saved = [SELECT Status__c, Rollback_Status__c, Rollback_Org__c, Rollback_Reason__c, Rollback_Token__c, Rollback_By__c,
                                           Rollback_Result__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals('Deployed', saved.Status__c, 'The release keeps its status');
            System.assertEquals('Running', saved.Rollback_Status__c, 'Running');
            System.assertEquals('Payments failing', saved.Rollback_Reason__c, 'Reason, trimmed');
            System.assertEquals(UserInfo.getUserId(), saved.Rollback_By__c, 'Who');
            Map<String, Object> inputs = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(m.bodyFor('/dispatches'))).get('inputs');
            System.assertEquals('rollback', inputs.get('mode'), 'Mode');
            System.assertEquals(rel.Name, inputs.get('request_id'), 'Request');
            System.assertEquals('sit', inputs.get('target_environment'), 'The org\'s Git environment');
            Map<String, Object> options = RlyReleaseTestData.dispatchedOptions(m);
            System.assertEquals(rel.Name + '/sit/abc', options.get('snapshotPath'), 'Snapshot');
            System.assertEquals(saved.Rollback_Token__c, options.get('attempt'), 'Attempt token');
            System.assertEquals(1, ((List<Object>) options.get('tests')).size(), 'The release\'s tests in production');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals('Rolling back in SIT', d.rollbackState.label, 'Pill');
            System.assert(d.running && d.rollbackState.busy, 'The page keeps checking and the button is disabled');
        }
    }

    @IsTest
    static void allLocalTestsSendsNoTests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            update new RLY_Org__c(Id = orgId('SIT'), Environment__c = 'Production');
            RlyHttpMock m = mock();
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Broken', RlyRollback.TESTS_ALL));
            Test.stopTest();
            System.assertEquals(null, RlyReleaseTestData.dispatchedOptions(m).get('tests'), 'All local tests: none named');
        }
    }

    @IsTest
    static void startIsRefused() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            Id prodId = orgId('PROD');
            Test.setMock(HttpCalloutMock.class, mock());
            Test.startTest();
            List<String> problems = new List<String>();
            for (String body : new List<String>{ request(orgId('SIT'), '  ', null), request(prodId, 'Why', null), '' }) {
                try {
                    RlyRollbackController.startRollback(rel.Id, body);
                } catch (AuraHandledException e) {
                    problems.add(e.getMessage());
                }
            }
            running(rel);
            try {
                RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Again', null));
            } catch (AuraHandledException e) {
                problems.add(e.getMessage());
            }
            try {
                RlyRollbackController.previewRollback(rel.Id, prodId);
            } catch (AuraHandledException e) {
                problems.add(e.getMessage());
            }
            Test.stopTest();
            System.assertEquals(5, problems.size(), 'No reason, an org it never reached, nothing, running, no preview: ' + problems);
            System.assert(problems[0].contains('say why'), problems[0]);
            System.assert(problems[1].contains('wasn\'t deployed'), problems[1]);
            System.assert(problems[3].contains('is running'), problems[3]);
        }
    }

    @IsTest
    static void onlyAdminsAndTheDeploymentTeam() {
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = deployed();
        }
        System.runAs(RlyTestData.plainUser()) {
            Boolean refused = false;
            try {
                RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Why', null));
            } catch (AuraHandledException e) {
                refused = e.getMessage().contains('deployment team');
            }
            System.assert(refused, 'Refused without the permission');
            System.assertEquals(false, RlyRollbackView.of(RlyReleaseStore.release(rel.Id)).canRollBack, 'No button');
        }
    }

    @IsTest
    static void rolledBackWhenTheResultIsIn() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            running(rel);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/rollback.json').reply(200, RlyReleaseTestData.result('rollback',
                '"status":"Rolled back","restored":1,"removed":1,"deployId":"' + RlyTestData.fakeId('0Af', 9) + '","message":"Rolled sit back","attempt":"' + TOKEN + '"')));
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals('Rolled_Back', d.rollbackState.status, 'Rolled back');
            System.assertEquals('Rolled back in SIT', d.rollbackState.label, 'Pill');
            System.assertEquals(false, d.running, 'Nothing runs');
            RLY_Release_Event__c e = [SELECT Event_Type__c, Detail__c, Reference__c, Actor__c FROM RLY_Release_Event__c
                                      WHERE Release__c = :rel.Id AND Event_Type__c = 'Rolled_Back' LIMIT 1];
            System.assert(e.Detail__c.contains('restored 1, removed 1'), e.Detail__c);
            System.assertEquals(RlyTestData.fakeId('0Af', 9), e.Reference__c, 'Deploy id');
            System.assert(RlyRollbackState.slackLine(new RLY_Release__c(Id = rel.Id)).contains('Rolled back in SIT'), 'Slack line');
            String pdf = RlyEvidenceTables.rollbackTable(RlyRollbackState.rowOf(rel.Id));
            System.assert(pdf.contains('<h2>Rollback</h2>') && pdf.contains('Payments failing'), 'Evidence section');
        }
    }

    @IsTest
    static void earlierResultIsIgnored() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            running(rel);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/rollback.json').reply(200,
                RlyReleaseTestData.result('rollback', '"status":"Rolled back","attempt":"older"')));
            Test.startTest();
            RlyRollbackRun.advance(rel.Id);
            Test.stopTest();
            System.assert(RlyRollbackState.isRunning(rel.Id), 'Still running: that result is from another run');
        }
    }

    @IsTest
    static void failedRunBeforeAResult() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            running(rel);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/runs?').reply(200, '{"workflow_runs":[{"id":7,'
                + '"html_url":"https://github.com/acme/release/actions/runs/7","display_title":"' + RlyRollbackRun.runTitle(rel.Name)
                + '","status":"completed","conclusion":"failure"}]}'));
            Test.startTest();
            RlyRollbackRun.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c row = [SELECT Rollback_Status__c, Rollback_Result__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals('Failed', row.Rollback_Status__c, 'Failed');
            System.assert(row.Rollback_Result__c.contains('actions/runs/7'), 'Run link kept');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c = :rel.Id AND Event_Type__c = 'Rollback_Failed'], 'History');
        }
    }

    @IsTest
    static void releasesTabListsRolledBack() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            update new RLY_Release__c(Id = rel.Id, Rollback_Status__c = 'Rolled_Back', Rollback_Org__c = orgId('SIT'),
                Rollback_By__c = UserInfo.getUserId(), Rollback_On__c = System.now(), Rollback_Reason__c = 'Broken',
                Rollback_Result__c = '{"restored":1,"removed":0}');
            Test.startTest();
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleasesFor('{"state":"rolledback"}');
            List<RlyReleasesController.Row> deployedRows = RlyReleasesController.listReleasesFor('{"state":"deployed"}');
            List<RlyReleasesController.Row> mine = RlyReleasesController.listReleasesFor(JSON.serialize(new Map<String, Object>{
                'state' => 'rolledback', 'raisedById' => UserInfo.getUserId() }));
            Map<String, Integer> counts = RlyReleasesController.countReleases('');
            String csv = RlyEvidenceController.exportCsv('{"state":"rolledback"}');
            Test.stopTest();
            System.assertEquals(1, rows.size(), 'Listed under Rolled back');
            System.assertEquals('Rolled_Back', rows[0].rollbackStatus, 'Row state');
            System.assertEquals('SIT', rows[0].rolledBackIn, 'Row org');
            System.assertEquals(0, deployedRows.size(), 'Not under Deployed');
            System.assertEquals(1, mine.size(), 'Raised by me');
            System.assertEquals(1, counts.get('rolledback'), 'Counted under Rolled back');
            System.assertEquals(0, counts.get('deployed'), 'Not under Deployed');
            System.assertEquals(1, counts.get('all'), 'All');
            List<String> lines = csv.split('\r\n');
            System.assert(lines[0].endsWith('"Rolled back in","Rolled back on"'), lines[0]);
            System.assert(lines[1].contains('"Rolled back"') && lines[1].contains('"SIT"'), lines[1]);
        }
    }

    @IsTest
    static void gateFailuresInTheEvidence() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = new RLY_Release__c(Scan_Result__c = '{"gates":{"file":".relay/gates.json","passed":false,'
                + '"failures":["2 findings at priority 2 or higher"]}}', Validation_Result__c = '{"gates":{"passed":false,'
                + '"failures":["PayClient 61% < 75%"]}}');
            Test.startTest();
            List<String> failures = RlyEvidenceTables.gateFailures(rel);
            Test.stopTest();
            System.assertEquals(new List<String>{ '2 findings at priority 2 or higher', 'PayClient 61% < 75%' }, failures, 'Scan, then validation');
            System.assertEquals('', RlyEvidenceTables.rollbackTable(new RLY_Release__c()), 'No rollback, no section');
        }
    }

    @IsTest
    static void stateHelpers() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c row = new RLY_Release__c(Rollback_Status__c = 'Failed');
            row.Rollback_Org__r = new RLY_Org__c(Name = 'SIT');
            Test.startTest();
            String label = RlyRollbackState.label(row);
            String print = RlyRollbackState.fingerprint(row);
            Test.stopTest();
            System.assertEquals('Rollback failed in SIT', label, 'Failed pill');
            System.assert(print.startsWith('Failed@'), 'Fingerprint: ' + print);
            System.assertEquals('', RlyRollbackState.fingerprint(new RLY_Release__c()), 'Read without the fields: nothing');
            System.assertEquals('', RlyRollbackState.counts(new RLY_Release__c()), 'No result yet');
            System.assertEquals(null, RlyRollbackPlan.toTime('not a time'), 'Bad time');
            System.assertEquals(0, RlyRollbackState.rowsOf(new Set<Id>()).size(), 'Nothing asked');
        }
    }

    @IsTest
    static void sandboxRollbackWithApexSendsTheReleaseTests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            RlyHttpMock m = mock();
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            // A sandbox has no tests choice: "all" sent by an older page is ignored there.
            RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Broken', RlyRollback.TESTS_ALL));
            Test.stopTest();
            System.assertEquals(new List<Object>{ 'AccountServiceTest' }, RlyReleaseTestData.dispatchedOptions(m).get('tests'),
                'Apex in a sandbox snapshot runs the release\'s tests, never every org test');
            RLY_Release__c saved = [SELECT Rollback_Result__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assert(saved.Rollback_Result__c.contains('"testsChoice":"release"'), saved.Rollback_Result__c);
        }
    }

    @IsTest
    static void rollbackWithoutApexSendsNoTests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            RlyHttpMock m = new RlyHttpMock()
                .match('GET', '/manifest.json').reply(200, '{"request":"x","existing":["Layout:Account-Account Layout"],"added":[],"deleted":[]}')
                .match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Broken', RlyRollback.TESTS_RELEASE));
            Test.stopTest();
            System.assertEquals(null, RlyReleaseTestData.dispatchedOptions(m).get('tests'), 'No Apex: no tests');
        }
    }

    @IsTest
    static void unreadableManifestStillSendsTheReleaseTests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = deployed();
            RlyHttpMock m = new RlyHttpMock().match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyRollbackController.startRollback(rel.Id, request(orgId('SIT'), 'Broken', null));
            Test.stopTest();
            System.assertEquals(new List<Object>{ 'AccountServiceTest' }, RlyReleaseTestData.dispatchedOptions(m).get('tests'),
                'The manifest couldn\'t be read: the release\'s tests are sent rather than none');
        }
    }
}
