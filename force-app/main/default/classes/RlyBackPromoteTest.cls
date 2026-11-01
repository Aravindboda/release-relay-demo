/**
 * @description Tests for back promote (RlyBackPromote, RlyBackPromoteQueue, RlyBackPromoteRun, RlyBackPromoteSummary, the
 * back promote methods of RlyRouteController, RlyOrgSettings and the sync parts of RlyStatusReader, RlyApprovalRuns and
 * RlyReleaseEffects). Route DEV1 -> SIT -> PROD (hub), with TRAINING as a back promote org. Each test runs through
 * System.runAs: as an active System Administrator with Release Relay Admin, or as a new user without it. Records are
 * inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyBackPromoteTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // The route, TRAINING (back promote, synced when an admin clicks Sync now) and back promote switched on.
    private static RLY_Org__c training() {
        RlyReleaseTestData.route();
        RLY_Org__c o = RlyTestData.org('TRAINING', 'Back_Promote', 'training');
        o.Environment__c = 'Full_Copy';
        o.Back_Promote_When__c = 'Manual';
        insert o;
        RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
        update new RLY_Git_Connection__c(Id = conn.Id, Back_Promote__c = true);
        return o;
    }

    private static RLY_Release__c syncOf(RLY_Org__c o) {
        return [SELECT Id, Name, Status__c, Source_Branch__c, Target_Branch__c, Target_Environment__c, Source_Environment__c,
                       Release_Type__c, Pending_Run__c
                FROM RLY_Release__c WHERE Target_Org__c = :o.Id ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static RLY_Org__c reloadOrg(Id orgId) {
        return [SELECT Sync_Status__c, Synced_On__c, Back_Promote_When__c, Back_Promote_Approval__c, Hotfix_Two_Approvers__c
                FROM RLY_Org__c WHERE Id = :orgId];
    }

    private static String problem(String settingsJson) {
        try {
            RlyRouteController.saveBackPromoteOrg(settingsJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void boardShowsHowFarBehind() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            RLY_Release__c older = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('a'));
            RLY_Release__c newer = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('b'));
            update new RLY_Release__c(Id = newer.Id, Last_Synced__c = System.now().addMinutes(5));
            RlyBackPromote.BackPromoteBoard b = RlyRouteController.getBackPromote();
            System.assert(b.enabled, 'On');
            System.assert(b.isAdmin, 'Admin');
            System.assertEquals(1, b.orgs.size(), 'TRAINING');
            RlyBackPromote.BackPromoteOrg x = b.orgs[0];
            System.assertEquals('Manual', x.whenValue, 'Sync now');
            System.assertEquals('Full_Copy', x.environment, 'Its environment');
            System.assertEquals(1, x.behind, 'A never synced org counts the deploys since it was registered');
            System.assertEquals(new List<String>{ newer.Name }, x.behindNames, 'By number, not ' + older.Name);
            update new RLY_Org__c(Id = o.Id, Synced_On__c = System.now().addMinutes(10));
            System.assertEquals(0, RlyBackPromote.board().orgs[0].behind, 'Matches the hub');

            RlyRouteController.Setup s = RlyRouteController.getSetup();
            System.assertEquals(1, s.backPromoteOrgs.size(), 'Shown after the hub');
            System.assertEquals(2, s.stages.size(), 'Not a stage on the route');
            System.assertEquals(2, RlyChangesController.getStart().routeStops.size(), 'Not a route stop for New Release');
        }
    }

    @IsTest
    static void settingsAreSavedByAdmins() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            System.assert(!RlyRouteController.setBackPromote('off').enabled, 'Off');
            System.assert(RlyRouteController.setBackPromote('on').enabled, 'On again');
            Boolean refused = false;
            try {
                RlyRouteController.setBackPromote('maybe');
            } catch (AuraHandledException e) {
                refused = e.getMessage().contains('on or off');
            }
            System.assert(refused, 'Only on or off');
            RlyRouteController.saveBackPromoteOrg(JSON.serialize(new Map<String, Object>{ 'orgId' => o.Id, 'whenValue' => 'After_Deploy',
                'approval' => true }));
            RLY_Org__c saved = reloadOrg(o.Id);
            System.assertEquals('After_Deploy', saved.Back_Promote_When__c, 'When saved');
            System.assertEquals(true, saved.Back_Promote_Approval__c, 'Approval saved');
            System.assert(problem(JSON.serialize(new Map<String, Object>{ 'orgId' => o.Id, 'whenValue' => 'Hourly' })).contains('Pick when'),
                'Only Manual or After_Deploy');
            System.assert(problem('not json').contains('couldn\'t be read'), 'Bad JSON');
            System.assert(problem(JSON.serialize(new Map<String, Object>{ 'orgId' => o.Id + 'x' })).contains('back promote org'), 'Unknown org');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            System.assert(!RlyBackPromote.board().isAdmin, 'Not an admin');
            System.assert(problem('{}').contains('Admin permission'), 'Admins only');
        }
    }

    @IsTest
    static void saveOrgKeepsBackPromoteSettings() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> input = new Map<String, Object>{
                'Name' => 'DEMO', 'Role__c' => 'Back_Promote', 'My_Domain__c' => 'https://demo.my.salesforce.com',
                'Login_Type__c' => 'Sandbox', 'Username__c' => 'relay@demo.test', 'Consumer_Key__c' => RlyTestData.CONSUMER_KEY,
                'Certificate__c' => 'release_relay', 'Git_Environment__c' => 'demo', 'Branch__c' => 'demo'
            };
            Id orgId = RlyOrgController.saveOrg(JSON.serialize(input));
            System.assertEquals('Manual', reloadOrg(orgId).Back_Promote_When__c, 'A new back promote org syncs on Sync now');
            update new RLY_Org__c(Id = orgId, Back_Promote_When__c = 'After_Deploy', Back_Promote_Approval__c = true);
            input.put('Id', orgId);
            input.put('Hotfix_Two_Approvers__c', true);
            RlyOrgController.saveOrg(JSON.serialize(input));
            RLY_Org__c saved = reloadOrg(orgId);
            System.assertEquals('After_Deploy', saved.Back_Promote_When__c, 'Kept when the page doesn\'t send it');
            System.assertEquals(true, saved.Back_Promote_Approval__c, 'Kept too');
            System.assertEquals(true, saved.Hotfix_Two_Approvers__c, 'Two approvers saved');
            input.put('Back_Promote_When__c', '');
            input.put('Back_Promote_Approval__c', false);
            RlyOrgController.saveOrg(JSON.serialize(input));
            System.assertEquals('Manual', reloadOrg(orgId).Back_Promote_When__c, 'Blank is Manual');
            System.assertEquals(1, RlyOrgValidator.validate(new RLY_Org__c(Name = 'X', Role__c = 'Back_Promote',
                My_Domain__c = 'https://x.my.salesforce.com', Login_Type__c = 'Sandbox', Username__c = 'a@b.c',
                Consumer_Key__c = 'key', Certificate__c = 'cert', Back_Promote_When__c = 'Hourly'), null).size(), 'When is checked');
        }
    }

    @IsTest
    static void syncNowIsQueuedThenStartedByTheBoard() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            Id syncId = RlyRouteController.syncNow(o.Id);
            RLY_Release__c queued = syncOf(o);
            System.assertEquals(syncId, queued.Id, 'The sync release');
            System.assertEquals('Back_Promote', queued.Release_Type__c, 'A back promote');
            System.assertEquals('Submitted', queued.Status__c, 'Queued');
            System.assertEquals('prod', queued.Source_Branch__c, 'From the hub\'s branch');
            System.assertEquals('training', queued.Target_Branch__c, 'Into the org\'s branch');
            Boolean twice = false;
            try {
                RlyRouteController.syncNow(o.Id);
            } catch (AuraHandledException e) {
                twice = e.getMessage().contains('already waiting');
            }
            System.assert(twice, 'One sync at a time');
            RlyHttpMock mock = RlyFlowScenario.forRelease(queued).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyBackPromote.BackPromoteBoard b = RlyRouteController.getBackPromote();
            Test.stopTest();
            RLY_Release__c started = syncOf(o);
            String dispatched = mock.bodyFor('/dispatches');
            System.assertEquals('Deploying', started.Status__c, 'Started');
            System.assertEquals('sync', started.Pending_Run__c, 'Mode sync');
            System.assert(dispatched.contains('"mode":"sync"') && dispatched.contains('"branch":"prod"'), dispatched);
            System.assert(dispatched.contains('"target":"training"') && dispatched.contains('"target_environment":"training"'), dispatched);
            System.assertEquals('Running', reloadOrg(o.Id).Sync_Status__c, 'The org shows it running');
            System.assertEquals(syncId, b.orgs[0].lastSyncId, 'Linked on the board');
        }
    }

    @IsTest
    static void syncNowNeedsBackPromoteOn() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            RlyRouteController.setBackPromote('off');
            Boolean refused = false;
            try {
                RlyRouteController.syncNow(o.Id);
            } catch (AuraHandledException e) {
                refused = e.getMessage().contains('Turn on Back promote');
            }
            System.assert(refused, 'Off: no sync');
        }
    }

    @IsTest
    static void successfulSyncMarksTheOrg() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            Id syncId = RlyRouteController.syncNow(o.Id);
            update new RLY_Release__c(Id = syncId, Status__c = 'Deploying', Pending_Run__c = 'sync', Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(syncOf(o));
            scenario.runMode = 'sync';
            scenario.results.put('sync', RlyReleaseTestData.result('sync', '"status":"Nothing to deploy","sha":"' + RlyReleaseTestData.sha('d') + '"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(syncId);
            Test.stopTest();
            System.assertEquals('Deployed', d.release.Status__c, 'Nothing to deploy is a success');
            System.assertEquals('Back_Promote', d.releaseType, 'Type on the page');
            RLY_Org__c saved = reloadOrg(o.Id);
            System.assertEquals('Deployed', saved.Sync_Status__c, 'Org synced');
            System.assertNotEquals(null, saved.Synced_On__c, 'When');
        }
    }

    @IsTest
    static void conflictingSyncDeploysNothing() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            Id syncId = RlyRouteController.syncNow(o.Id);
            update new RLY_Release__c(Id = syncId, Status__c = 'Deploying', Pending_Run__c = 'sync', Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(syncOf(o));
            scenario.runMode = 'sync';
            scenario.results.put('sync', RlyReleaseTestData.result('sync',
                '"status":"Conflict","conflicts":[{"file":"classes/A.cls"},"classes/B.cls"],"message":"2 conflicts"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(syncId);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(syncId);
            System.assertEquals('Failed', saved.Status__c, 'Failed');
            System.assert(saved.Error_Message__c.contains('classes/A.cls, classes/B.cls'), saved.Error_Message__c);
            System.assertEquals('Conflict', reloadOrg(o.Id).Sync_Status__c, 'Org shows the conflict');
        }
    }

    @IsTest
    static void failedSyncRunWithoutResult() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            Id syncId = RlyRouteController.syncNow(o.Id);
            update new RLY_Release__c(Id = syncId, Status__c = 'Deploying', Pending_Run__c = 'sync', Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(syncOf(o));
            scenario.runMode = 'sync';
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', '"status":"Deployed"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyBackPromoteRun.catchUp();
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(syncId);
            System.assertEquals('Failed', saved.Status__c, 'The run failed');
            System.assertEquals('Failed', reloadOrg(o.Id).Sync_Status__c, 'Org shows it');
        }
    }

    @IsTest
    static void hubDeployQueuesAfterDeployOrgs() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            update new RLY_Org__c(Id = o.Id, Back_Promote_When__c = 'After_Deploy');
            RLY_Org__c manual = RlyTestData.org('DEMO', 'Back_Promote', 'demo');
            insert manual;
            RLY_Release__c rel = new RLY_Release__c(Title__c = 'Promote', Status__c = 'Deploying', Release_Type__c = 'Promotion',
                Source_Org__c = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id, Target_Org__c = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD'].Id,
                Target_Branch__c = 'prod', Source_Branch__c = 'promote/x', Pending_Run__c = 'merge', Deploy_Status__c = 'Deploying',
                Approval_Status__c = 'Approved', Checks_Requested__c = System.now().addMinutes(-1));
            insert rel;
            rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.runMode = 'merge';
            scenario.results.put('merge', RlyReleaseTestData.result('merge', '"status":"Merged","sha":"' + RlyReleaseTestData.sha('e') + '"'));
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', '"status":"Deployed"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals('Deployed', d.release.Status__c, 'Deployed: ' + d.release.Error_Message__c);
            RLY_Release__c sync = syncOf(o);
            System.assertEquals('Submitted', sync.Status__c, 'Queued for TRAINING');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release__c WHERE Target_Org__c = :manual.Id], 'DEMO waits for Sync now');
            System.assert(d.backPromote.contains('DEMO: waiting for Sync now'), d.backPromote);
            System.assert(d.backPromote.contains('Sent to TRAINING: Queued'), d.backPromote);
            System.assert(d.running, 'The page checks again to start the sync');
        }
    }

    @IsTest
    static void approvedSyncStartsTheSyncRun() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = training();
            update new RLY_Org__c(Id = o.Id, Back_Promote_Approval__c = true);
            Id syncId = RlyRouteController.syncNow(o.Id);
            System.assertEquals('Ready for approval', syncOf(o).Status__c, 'Waits for an approver');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.approve(syncId, null);
            Test.stopTest();
            RLY_Release__c saved = syncOf(o);
            System.assertEquals('Deploying', saved.Status__c, 'Syncing');
            System.assertEquals('sync', saved.Pending_Run__c, 'Mode sync, not merge');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"sync"'), mock.bodyFor('/dispatches'));
        }
    }
}
