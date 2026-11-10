/**
 * @description Tests for build 54: open releases at Switch now (RlyMigrationCancel, RlyMigrationSwitch.switchHub with the
 * admin's choice, RlyMigrationOrgController.switchNowCancelling, the gate's warn condition, the report's section, the
 * Slack card's Cancelled line). The current connection (GitHub) and the new one (GitLab) are created in the test setup;
 * every Git call is answered by RlyHttpMock. Every test runs as an admin through System.runAs; DML happens before the
 * callouts of each test.
 */
@IsTest
private class RlyMigrationCancelTest {

    private static final String TOKEN = 'tok-54';

    @TestSetup
    static void setup() {
        RlyMigrationTestData.connections();
    }

    private static Id gitHubId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1].Id;
    }

    private static Id gitLabId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitLab' LIMIT 1].Id;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    // An open release from DEV1 into SIT on the GitHub connection (not inserted).
    private static RLY_Release__c release(String status, Integer prNumber) {
        RLY_Release__c rel = RlyMigrationTestData.release(status);
        rel.Git_Connection__c = gitHubId();
        rel.PR_Number__c = prNumber;
        rel.PR_URL__c = prNumber == null ? null : 'https://github.com/acme/release/pull/' + prNumber;
        return rel;
    }

    private static Map<String, Object> ref(String name, String sha) {
        return new Map<String, Object>{ 'ref' => 'refs/heads/' + name, 'kind' => 'branch', 'name' => name, 'source' => sha,
            'target' => sha, 'match' => true };
    }

    // The importer's verify, every ref matching.
    private static String verified() {
        return JSON.serialize(new Map<String, Object>{ 'request' => 'MIG-1762531200054', 'step' => 'migrate', 'status' => 'Succeeded',
            'attempt' => TOKEN, 'ready' => true, 'phase' => 'done', 'method' => 'verify', 'dryRun' => true,
            'branches' => new Map<String, Object>{ 'found' => 3, 'pushed' => 0, 'failed' => 0 },
            'tags' => new Map<String, Object>{ 'found' => 0, 'pushed' => 0, 'failed' => 0 }, 'commits' => 42, 'mainCommits' => 40,
            'defaultBranch' => 'main', 'sizeKb' => 2048, 'targetEmpty' => false, 'targetRefCount' => 3,
            'access' => new Map<String, Object>{ 'read' => true, 'push' => null }, 'problems' => new List<Object>(),
            'namedBranches' => new List<Object>{ new Map<String, Object>{ 'name' => 'sit', 'inSource' => true, 'inTarget' => true } },
            'refs' => new List<Object>{ ref('main', 'a1'), ref('sit', 'b2'), ref('prod', 'c3') } });
    }

    // A migration GitHub → GitLab ready to switch but for the open releases.
    private static RLY_Migration__c readyMigration() {
        RlyMigrationState state = new RlyMigrationState();
        for (RLY_Org__c o : RlySyncStore.orgs()) {
            RlyMigrationState.OrgCheck c = new RlyMigrationState.OrgCheck();
            c.status = RlyMigrationSync.IN_SYNC;
            c.syncId = 'SYN-1762531200054';
            c.mode = 'drift';
            state.orgChecks.put(String.valueOf(o.Id), c);
        }
        RLY_Migration__c m = new RLY_Migration__c(Migration_Id__c = 'MIG-1762531200054', Current_Connection__c = gitHubId(),
            New_Connection__c = gitLabId(), Status__c = RlyMigrationStore.OPEN, Step__c = 7, Method__c = RlyMigrationMethods.IMPORTER,
            Dry_Run__c = verified(), Result__c = verified(), Run_Kind__c = RlyMigrationRun.DRY, Run_Status__c = RlyMigrationRun.READY,
            State__c = state.toJson());
        insert m;
        return m;
    }

    private static String refusal(Exception e) {
        return e.getMessage();
    }

    @IsTest
    static void gateNamesTheOpenReleasesAndWaitsForTheChoice() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = readyMigration();
            RLY_Release__c waiting = release('Ready for approval', 41);
            RLY_Release__c running = release('Validating', 57);
            insert new List<RLY_Release__c>{ waiting, running };
            Test.startTest();
            RlyMigrationView.View before = RlyMigrationController.getMigration();
            String unchosen;
            try {
                RlyMigrationOrgController.switchNow(m.Id);
            } catch (AuraHandledException e) {
                unchosen = refusal(e);
            }
            String unseen;
            try {
                RlyMigrationOrgController.switchNowCancelling(m.Id, new List<Id>{ waiting.Id });
            } catch (AuraHandledException e) {
                unseen = refusal(e);
            }
            Test.stopTest();
            System.assertEquals(false, before.gate.ready, 'Open releases: not ready as it was');
            System.assertEquals(true, before.gate.readyIfCancelled, 'Ready once the open releases are cancelled');
            System.assertEquals(2, before.holds.open.size(), 'Both releases listed');
            Boolean warned = false;
            for (RlyMigrationView.Condition c : before.gate.conditions) {
                warned = warned || (c.warn && c.detail.contains('cancelled when you switch'));
            }
            System.assert(warned, 'The open releases condition warns: ' + before.gate.conditions);
            Map<Id, Boolean> runs = new Map<Id, Boolean>();
            for (RlyMigrationView.OpenRelease o : before.holds.open) {
                runs.put(o.id, o.running);
            }
            System.assertEquals(true, runs.get(running.Id), 'The validating release has a run going');
            System.assertEquals(false, runs.get(waiting.Id), 'The waiting release has none');
            System.assert(unchosen != null && unchosen.contains('Cancel the 2 open releases'), 'Without the choice it is refused: ' + unchosen);
            System.assert(unseen != null && unseen.contains('opened after you chose'), 'A release not confirmed stops it: ' + unseen);
            System.assertEquals(RlyMigrationStore.OPEN, [SELECT Status__c FROM RLY_Migration__c WHERE Id = :m.Id].Status__c, 'Not switched');
        }
    }

    @IsTest
    static void switchCancelsTheOpenReleasesAndClosesTheirPullRequests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = readyMigration();
            RLY_Release__c waiting = release('Ready for approval', 41);
            RLY_Release__c running = release('Validating', 57);
            insert new List<RLY_Release__c>{ waiting, running };
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/repos/acme/release/issues/41/comments').reply(201, '{"id":1}')
                .match('PATCH', '/repos/acme/release/pulls/41').reply(200, '{"state":"closed"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyMigrationView.View switched = RlyMigrationOrgController.switchNowCancelling(m.Id, new List<Id>{ waiting.Id, running.Id });
            Test.stopTest();
            System.assertEquals(RlyMigrationStore.SWITCHED, switched.status, 'Switched');
            System.assertEquals(gitLabId(), RlyGitConnections.activeId(), 'GitLab is active');
            Map<Id, RLY_Release__c> saved = new Map<Id, RLY_Release__c>([SELECT Id, Status__c, Error_Message__c FROM RLY_Release__c
                WHERE Id IN :new List<Id>{ waiting.Id, running.Id }]);
            System.assertEquals('Cancelled', saved.get(waiting.Id).Status__c, 'The waiting release is cancelled');
            System.assertEquals('Cancelled', saved.get(running.Id).Status__c, 'The running release is cancelled too');
            System.assert(saved.get(waiting.Id).Error_Message__c.startsWith('Cancelled by the move to GitLab (MIG-1762531200054).'),
                'The reason is on the release: ' + saved.get(waiting.Id).Error_Message__c);
            System.assert(saved.get(running.Id).Error_Message__c.contains('pipeline run was still going in GitHub')
                && saved.get(running.Id).Error_Message__c.contains('couldn\'t be closed'), 'The run and the refused close are said: '
                + saved.get(running.Id).Error_Message__c);
            System.assert(mock.bodyFor('/issues/41/comments').contains('Cancelled in Release Relay: the hub moved to GitLab.'),
                'The pull request gets the comment: ' + mock.callLog());
            List<RLY_Release_Event__c> events = [SELECT Detail__c FROM RLY_Release_Event__c
                WHERE Event_Type__c = 'Cancelled' AND Release__c = :waiting.Id];
            System.assertEquals(1, events.size(), 'One Cancelled event in History');
            System.assert(events[0].Detail__c.startsWith('Cancelled by the move from GitHub to GitLab by '), 'The event says why: ' + events[0].Detail__c);
            System.assertEquals(2, switched.cancelled.size(), 'The migration keeps both');
            Map<Id, Boolean> closed = new Map<Id, Boolean>();
            for (RlyMigrationView.CancelledRelease r : switched.cancelled) {
                closed.put(r.id, r.closed);
            }
            System.assertEquals(true, closed.get(waiting.Id), 'Its pull request is closed');
            System.assertEquals(false, closed.get(running.Id), 'This one was refused');
            System.assert(switched.log.events[1].what.startsWith('Cancelled 2 open releases on GitHub:'),
                'Who did what lists the cancelled releases: ' + switched.log.events[1].what);
            String report = RlyMigrationReport.html(RlyMigrationStore.byId(m.Id), switched);
            System.assert(report.contains('Releases cancelled by the switch') && report.contains('not closed'), 'The report lists them');
        }
    }

    @IsTest
    static void releasesBeyondTheCalloutsAreCancelledWithTheirPullRequestLeftOpen() {
        System.runAs(RlyTestData.admin()) {
            RLY_Migration__c m = readyMigration();
            RLY_Release__c open = release('PR open', 41);
            insert open;
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            RlyMigrationCancel.calloutsKept = 1000;
            Test.startTest();
            RlyMigrationView.View switched = RlyMigrationOrgController.switchNowCancelling(m.Id, new List<Id>{ open.Id });
            Test.stopTest();
            RLY_Release__c saved = [SELECT Status__c, Error_Message__c FROM RLY_Release__c WHERE Id = :open.Id];
            System.assertEquals('Cancelled', saved.Status__c, 'Cancelled without callouts');
            System.assert(saved.Error_Message__c.contains('left open in GitHub'), 'Said on the release: ' + saved.Error_Message__c);
            System.assertEquals(0, mock.calls.size(), 'No callout made: ' + mock.callLog());
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Release_Event__c WHERE Event_Type__c = 'Cancelled' AND Release__c = :open.Id],
                'History has the event');
            System.assert(switched.cancelled[0].note.contains('too many releases'), 'The row says why: ' + switched.cancelled[0].note);
        }
    }

    @IsTest
    static void slackCardAndSummarySayCancelled() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            String line = RlySlackCard.statusLine(new RLY_Release__c(Status__c = 'Cancelled',
                Error_Message__c = 'Cancelled by the move to GitLab (MIG-1).'), null);
            RlyMigrationCancel.Plan p = new RlyMigrationCancel.Plan();
            p.oldLabel = 'GitHub';
            for (Integer i = 0; i < 45; i++) {
                RlyMigrationView.CancelledRelease r = new RlyMigrationView.CancelledRelease();
                r.name = 'REL-' + String.valueOf(10000 + i);
                r.url = Math.mod(i, 2) == 0 ? 'https://github.com/acme/release/pull/' + i : null;
                r.closed = r.url != null;
                p.rows.add(r);
            }
            String text = RlyMigrationCancelText.summary(p);
            String none;
            try {
                RlyMigrationCancel.requireConfirmed(new List<RlyMigrationView.OpenRelease>{ new RlyMigrationView.OpenRelease() }, null);
            } catch (RlyReleaseException e) {
                none = refusal(e);
            }
            Test.stopTest();
            System.assert(line.startsWith(':no_entry: Cancelled: Cancelled by the move to GitLab'), 'The card says Cancelled: ' + line);
            System.assert(text.startsWith('Cancelled 45 open releases on GitHub:') && text.contains(' and 5 more'), 'Long lists are cut: ' + text);
            System.assert(text.contains('Pull requests closed: 23 of 23'), 'The pull requests are counted: ' + text);
            System.assert(none != null && none.contains('opened after you chose'), 'Nothing confirmed: refused: ' + none);
        }
    }
}
