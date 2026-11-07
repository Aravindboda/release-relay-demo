/**
 * @description Tests for the Pipeline Monitor (RlyRunMonitorController, RlyRunMonitorBoard, RlyRunMonitorLanes,
 * RlyRunMonitorBranches, RlyRunMonitorQueries) and the pipeline run retention (RlyRunMonitorRetention, through the
 * nightly archive call): the tiles, one lane per org in route order with today's run or the last run, the active
 * branches running first with the release's pull request, runs still going first then pages of 50, the repository
 * filter with two Git connections, and old runs removed by the nightly call. Runs are inserted directly. Each test runs
 * through System.runAs as the active System Administrator with Release Relay Admin.
 */
@IsTest
private class RlyRunMonitorControllerTest {

    private static final String URL_BASE = 'https://github.com/acme/release/actions/runs/';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A run (not inserted): key, status and target org as "key|status|target".
    private static RLY_Pipeline_Run__c run(String spec, Datetime started) {
        List<String> p = spec.split('\\|');
        String key = p[0];
        String status = p[1];
        String target = p[2];
        Boolean going = RlyRunMonitorStore.ACTIVE.contains(status);
        return new RLY_Pipeline_Run__c(Run_Id__c = key, Status__c = status, Target_Org__c = target, Started__c = started,
            Finished__c = going ? null : started.addMinutes(2), Duration_Seconds__c = going ? null : 120,
            Workflow_Step__c = 'Check-only deploy', Mode__c = 'check', Branch__c = 'feature/rel-' + key.substringBefore('-'),
            Actor__c = 'Test user', Run_Url__c = URL_BASE + key.substringBefore('-'));
    }

    // DEV1 → SIT → PROD, a back promote org TRAIN, a release on its branch with PR #170, and runs.
    private static RLY_Release__c board() {
        RLY_Release__c rel = RlyReleaseTestData.release('PR open', null);
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 170, PR_URL__c = 'https://github.com/acme/release/pull/170');
        insert RlyTestData.org('TRAIN', 'Back_Promote', 'train');
        Datetime now = System.now();
        RLY_Pipeline_Run__c raise = run('100-1|Succeeded|sit', now.addMinutes(-30));
        raise.Workflow_Step__c = 'Raise';
        raise.Release__c = rel.Id;
        raise.Branch__c = 'feature/' + rel.Name.toLowerCase();
        RLY_Pipeline_Run__c going = run('101-1|In progress|SIT', now.addMinutes(-2));
        going.Release__c = rel.Id;
        going.Branch__c = raise.Branch__c;
        List<RLY_Pipeline_Run__c> rows = new List<RLY_Pipeline_Run__c>{ raise, going,
            run('102-1|Failed|sit', now.addMinutes(-20)), run('103-1|Succeeded|prod', now.addMinutes(-10)),
            run('104-1|Succeeded|train', now.addDays(-3)) };
        for (Integer i = 0; i < 52; i++) {
            rows.add(run(String.valueOf(1000 + i) + '-1|Succeeded|prod', now.addDays(-5).addMinutes(-i)));
        }
        rows[1].Failure_Message__c = null;
        rows[2].Failure_Message__c = 'Assertion failed';
        rows[2].Steps__c = '[{"name":"Check-only deploy","outcome":"failure","seconds":90}]';
        insert rows;
        return rel;
    }

    private static RlyRunMonitorViews.Lane laneOf(RlyRunMonitorViews.Board b, String name) {
        for (RlyRunMonitorViews.Lane l : b.lanes) {
            if (l.name == name) {
                return l;
            }
        }
        return null;
    }

    @IsTest
    static void readsTheBoard() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = board();
            Test.startTest();
            RlyRunMonitorViews.Board b = RlyRunMonitorController.readBoard(null);
            Test.stopTest();
            System.assertEquals(1, b.repos.size(), 'One Git connection');
            System.assertEquals('acme/release', b.repository, 'The first connection is picked');
            System.assertEquals(true, b.anyActive, 'A run is going');
            System.assertEquals(1, b.tiles.running, 'Running now');
            System.assert(b.tiles.succeededToday >= 2, 'Succeeded today: ' + b.tiles.succeededToday);
            System.assertEquals(1, b.tiles.failedToday, 'Failed today');
            System.assertEquals(4, b.lanes.size(), 'One lane per org');
            System.assertEquals('DEV1', b.lanes[0].name, 'Developer orgs first');
            System.assertEquals('development', b.lanes[0].groupKey, 'Development group');
            System.assertEquals('SIT', b.lanes[1].name, 'Then the stages');
            System.assertEquals('stage 1', b.lanes[1].roleText, 'Stage number');
            System.assertEquals('PROD', b.lanes[2].name, 'Production last on the route');
            System.assertEquals('production', b.lanes[2].roleText, 'Production');
            System.assertEquals('backpromote', b.lanes[3].groupKey, 'Back promote orgs at the end');
            System.assertEquals('Raise', laneOf(b, 'DEV1').run.step, 'A developer org shows the Raise of its release');
            System.assertEquals('In progress', laneOf(b, 'SIT').run.status, 'The newest run in SIT, matched without case');
            System.assertEquals(rel.Name, laneOf(b, 'SIT').run.releaseName, 'With its release');
            System.assertEquals(null, laneOf(b, 'TRAIN').run, 'No runs today in TRAIN');
            System.assertNotEquals(null, laneOf(b, 'TRAIN').lastRun, 'Its last run instead');
            System.assert(!b.branches.isEmpty(), 'Active branches');
            System.assertEquals('running', b.branches[0].state, 'Running first');
            System.assertEquals(170, b.branches[0].prNumber, 'The release\'s pull request');
            System.assertEquals('open', b.branches[0].prState, 'Open while the release is');
            System.assertEquals(b.branches.size(), b.tiles.branches, 'The tile counts the branches');
            System.assertEquals('In progress', b.runs[0].status, 'Runs still going first');
            System.assertEquals(51, b.runs.size(), 'The run going and 50 finished runs');
            System.assertEquals(true, b.hasMore, 'Older runs to load');
        }
    }

    @IsTest
    static void loadsOlderRuns() {
        System.runAs(RlyTestData.admin()) {
            board();
            RlyRunMonitorViews.Board b = RlyRunMonitorController.readBoard('acme/release');
            RlyRunMonitorViews.Run oldest = b.runs[b.runs.size() - 1];
            Test.startTest();
            RlyRunMonitorViews.OlderPage p = RlyRunMonitorController.readOlder('acme/release',
                JSON.serialize(oldest.started).remove('"'), oldest.id);
            String refused;
            try {
                RlyRunMonitorController.readOlder(null, 'not a time', null);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(6, p.runs.size(), '56 finished runs: 50 shown, 6 older');
            System.assertEquals(false, p.hasMore, 'Nothing older');
            System.assert(p.runs[0].started <= oldest.started, 'Older than the oldest shown');
            System.assertNotEquals(null, refused, 'A cursor without a time is refused');
            System.assertEquals('1', String.valueOf(p.runs[0].attempt), 'Attempt from the run key');
        }
    }

    @IsTest
    static void filtersByRepository() {
        System.runAs(RlyTestData.admin()) {
            board();
            insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/other_repo', Named_Credential__c = 'RLY_GitHub',
                Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default',
                Status__c = 'Connected');
            RLY_Pipeline_Run__c other = run('900-1|Failed|sit', System.now().addMinutes(-1));
            other.Run_Url__c = 'https://github.com/acme/other_repo/actions/runs/900';
            insert other;
            Test.startTest();
            RlyRunMonitorViews.Board b = RlyRunMonitorController.readBoard('acme/other_repo');
            RlyRunMonitorViews.Board unknown = RlyRunMonitorController.readBoard('acme/missing');
            Test.stopTest();
            System.assertEquals(2, b.repos.size(), 'Two connections');
            System.assertEquals(1, b.runs.size(), 'Only that repository\'s runs');
            System.assertEquals('900-1', b.runs[0].runKey, 'The other repository\'s run');
            System.assertEquals(false, b.anyActive, 'Nothing going there');
            System.assertEquals('acme/release', unknown.repository, 'An unknown repository falls back to the first');
            System.assertEquals('%/acme/my\\_repo/actions/runs/%', RlyRunMonitorQueries.urlPattern('acme/my_repo'), 'Wildcards escaped');
            System.assertEquals(null, RlyRunMonitorQueries.urlPattern(' '), 'No filter for blank');
        }
    }

    @IsTest
    static void emptyBoard() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyRunMonitorViews.Board b = RlyRunMonitorController.readBoard('');
            Test.stopTest();
            System.assertEquals(0, b.repos.size(), 'No connection');
            System.assertEquals(null, b.repository, 'No repository');
            System.assertEquals(0, b.runs.size(), 'No runs');
            System.assertEquals(0, b.lanes.size(), 'No orgs');
            System.assertEquals(false, b.hasMore, 'Nothing older');
        }
    }

    @IsTest
    static void branchStates() {
        System.runAs(RlyTestData.admin()) {
            RlyRunMonitorViews.BranchRow b = new RlyRunMonitorViews.BranchRow();
            RLY_Release__c rel = new RLY_Release__c(Status__c = 'Deployed', PR_Number__c = 9);
            RlyRunMonitorBranchRow.withRelease(b, rel);
            System.assertEquals('merged', b.prState, 'Deployed means merged');
            rel.Status__c = 'Rejected';
            RlyRunMonitorBranchRow.withRelease(b, rel);
            System.assertEquals('closed', b.prState, 'Rejected means closed');
            System.assertEquals('idle', RlyRunMonitorBranchRow.runState('Cancelled'), 'Cancelled is idle');
            System.assertEquals('failed', RlyRunMonitorBranchRow.runState('Failed'), 'Failed');
            System.assertEquals('ok', RlyRunMonitorBranchRow.runState('Succeeded'), 'Succeeded');
            System.assertEquals('running', RlyRunMonitorBranchRow.runState('Queued'), 'Queued counts as running');
        }
    }

    @IsTest
    static void retentionRemovesOldRuns() {
        System.runAs(RlyTestData.admin()) {
            insert new List<RLY_Pipeline_Run__c>{ run('1-1|Succeeded|sit', System.now().addDays(-40)),
                run('2-1|Succeeded|sit', System.now().addDays(-41)), run('3-1|Failed|sit', System.now().addDays(-1)) };
            insert new List<RLY_Sync_Check__c>{
                new RLY_Sync_Check__c(Sync_Id__c = 'SYN-1700000000000', Kind__c = 'Route', Status__c = 'Succeeded', Checked_At__c = System.now().addDays(-45)),
                new RLY_Sync_Check__c(Sync_Id__c = 'SYN-1700000000001', Kind__c = 'Route', Status__c = 'Succeeded', Checked_At__c = System.now()) };
            RlyRunMonitorRetention.perCall = 1;
            Test.startTest();
            Integer none = RlyRunMonitorRetention.prune(null);
            Integer first = RlyRunMonitorRetention.prune(30);
            RlyRunMonitorRetention.perCall = 2000;
            Integer second = RlyRunMonitorRetention.prune(30);
            Integer third = RlyRunMonitorRetention.prune(30);
            Test.stopTest();
            System.assertEquals(0, none, 'No days keeps every run');
            System.assertEquals(1, first, 'At most perCall per call');
            System.assertEquals(1, second, 'The rest at the next call');
            System.assertEquals(0, third, 'Nothing older left');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE Id != null], 'The recent run stays');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Sync_Check__c WHERE Id != null], 'An old Sync status check goes, the recent one stays');
        }
    }

    @IsTest
    static void nightlyCallRemovesOldRuns() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.nightly(30);
            insert run('5-1|Succeeded|sit', System.now().addDays(-45));
            RestRequest req = new RestRequest();
            req.requestURI = '/services/apexrest/rly/archive';
            req.httpMethod = 'POST';
            req.requestBody = Blob.valueOf('{}');
            RestContext.request = req;
            RestContext.response = new RestResponse();
            Test.startTest();
            RlyArchiveRest.archive();
            Test.stopTest();
            Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
            System.assertEquals(1, out.get('pipelineRuns'), 'The nightly call removed the old run: ' + out);
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Pipeline_Run__c WHERE Id != null], 'Removed');
        }
    }
}
