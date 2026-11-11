/**
 * @description Tests for release windows on deploys (build 39: RlyWindowGate, RlyWindowController, RlyWindowStore): an
 * approval outside SIT's window waits (Waiting for window, History Window_Held) instead of starting the merge, a read
 * inside the window starts it, an admin can deploy now anyway with a reason (Window_Override), the Pipeline tab saves and
 * reads windows, and Home lists a freeze starting soon. GitHub answers through RlyFlowScenario's mock; the clock is set
 * with RlyWindowGate.nowForTest. Each test runs as an active System Administrator with Release Relay Admin and Approver
 * via System.runAs; records are inserted before Test.startTest, callouts come after it.
 */
@IsTest
private class RlyWindowGateTest {

    // Tue 10 Nov 2026 11:00 AM in Chicago: outside a Monday-evening window.
    private static final Datetime OUTSIDE = Datetime.newInstanceGmt(2026, 11, 10, 17, 0, 0);
    // Mon 16 Nov 2026 7:00 PM in Chicago: inside it.
    private static final Datetime INSIDE = Datetime.newInstanceGmt(2026, 11, 17, 1, 0, 0);

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
        RlyTestData.assignPermissionSet('RLY_Admin');
        RlyTestData.assignPermissionSet('RLY_Window_Bypass_Addon'); // build 49: Deploy now anyway is an add-on
    }

    // SIT deploys only on Monday evenings, Chicago time.
    private static RLY_Release__c releaseWithWindow(String status) {
        RLY_Release__c rel = RlyReleaseTestData.release(status, 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
        Id sitId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
        update new RLY_Org__c(Id = sitId, Window_Days__c = 'Mon', Window_From__c = '18:00', Window_To__c = '22:00',
            Window_Time_Zone__c = 'America/Chicago');
        return rel;
    }

    private static Integer events(Id relId, String eventType) {
        return [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c = :relId AND Event_Type__c = :eventType];
    }

    @IsTest
    static void anApprovalOutsideTheWindowWaits() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseWithWindow('Ready for approval');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            RlyWindowGate.nowForTest = OUTSIDE;
            Test.startTest();
            RlyReleasesController.approve(rel.Id, 'Looks good', null);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals(RlyWindowGate.WAITING, saved.Status__c, 'Waits for the window: ' + saved.Error_Message__c);
            System.assertEquals('Approved', saved.Approval_Status__c, 'The approval stands');
            System.assertEquals(null, mock.bodyFor('/dispatches'), 'No merge outside the window');
            System.assertEquals(1, events(rel.Id, RlyWindowGate.EVENT_HELD), 'History says why');
            RlyWindowGate.Notice n = RlyWindowController.releaseNotice(rel.Id);
            System.assertEquals('waiting', n.kind, 'Waiting, not frozen');
            System.assert(n.text.startsWith('Waiting for SIT\'s release window (Mon 6:00 PM–10:00 PM).'), n.text);
            System.assert(n.text.contains('Deploys Mon 16 Nov, 6:00 PM'), 'When it will deploy: ' + n.text);
        }
    }

    @IsTest
    static void aReadInsideTheWindowStartsTheDeploy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseWithWindow(RlyWindowGate.WAITING);
            update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            // Outside the window a read changes nothing and calls out to nothing; it saves the read (DML), so the read
            // that calls out comes after Test.startTest.
            RlyWindowGate.nowForTest = OUTSIDE;
            RlyStatusReader.advanceWithin(rel.Id, 0);
            RLY_Release__c stillWaiting = RlyReleaseTestData.reload(rel.Id);
            Test.startTest();
            RlyWindowGate.nowForTest = INSIDE;
            RlyStatusReader.advanceWithin(rel.Id, 0);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals(RlyWindowGate.WAITING, stillWaiting.Status__c, 'Still outside: still waiting');
            System.assertEquals('Deploying', saved.Status__c, 'Inside the window the merge starts: ' + saved.Error_Message__c);
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"merge"'), 'Merge run');
        }
    }

    @IsTest
    static void anAdminDeploysNowWithAReason() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseWithWindow(RlyWindowGate.WAITING);
            update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            RlyWindowGate.nowForTest = OUTSIDE;
            String refused;
            Test.startTest();
            try {
                RlyWindowController.deployNow(rel.Id, 'no');
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            String status = RlyWindowController.deployNow(rel.Id, 'Production incident INC0042');
            Test.stopTest();
            System.assert(refused != null && refused.contains('Say why'), 'A reason is needed: ' + refused);
            System.assertEquals('Deploying', status, 'Deploying now');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"merge"'), 'Merge run');
            List<RLY_Release_Event__c> e = [SELECT Detail__c FROM RLY_Release_Event__c WHERE Release__c = :rel.Id
                                            AND Event_Type__c = :RlyWindowGate.EVENT_OVERRIDE];
            System.assertEquals(1, e.size(), 'Recorded');
            System.assert(e[0].Detail__c.contains('Production incident INC0042'), 'With the reason: ' + e[0].Detail__c);
        }
    }

    @IsTest
    static void thePipelineTabSavesAndReadsWindows() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
            RlyWindowGate.nowForTest = OUTSIDE;
            Map<String, Object> input = new Map<String, Object>{ 'orgId' => sitId, 'days' => new List<String>{ 'Thu', 'Mon', 'Xyz' },
                'fromTime' => '18:00:00.000Z', 'toTime' => '22:00', 'timeZone' => 'America/Chicago',
                'freezes' => new List<Object>{ new Map<String, Object>{ 'fromDate' => '2026-11-16', 'toDate' => '2026-11-20', 'reason' => 'Go-live week' } } };
            Map<String, Object> badTime = input.clone();
            badTime.put('toTime', '');
            Map<String, Object> noReason = input.clone();
            noReason.put('freezes', new List<Object>{ new Map<String, Object>{ 'fromDate' => '2026-11-16', 'toDate' => '2026-11-20' } });
            Test.startTest();
            List<String> errors = new List<String>();
            for (Map<String, Object> bad : new List<Map<String, Object>>{ badTime, noReason }) {
                try {
                    RlyWindowController.saveWindow(JSON.serialize(bad));
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            RlyWindowController.WindowView saved = RlyWindowController.saveWindow(JSON.serialize(input));
            List<RlyWindowController.WindowView> views = RlyWindowController.windows();
            List<RlyWindowController.Upcoming> soon = RlyWindowController.upcomingFreezes();
            Test.stopTest();
            System.assertEquals(2, errors.size(), 'Both refused: ' + errors);
            System.assert(errors[0].contains('both From and To'), errors[0]);
            System.assert(errors[1].contains('Say why each freeze'), errors[1]);
            RLY_Org__c row = [SELECT Window_Days__c, Window_From__c, Window_Freezes__c FROM RLY_Org__c WHERE Id = :sitId];
            System.assertEquals('Mon,Thu', row.Window_Days__c, 'Days in week order, unknown left out');
            System.assertEquals('18:00', row.Window_From__c, 'Time cut to HH:mm');
            System.assert(saved.summary.startsWith('Mon, Thu 6:00 PM–10:00 PM'), saved.summary);
            System.assertEquals(false, saved.openNow, 'Tuesday morning: closed');
            System.assert(saved.stateText.startsWith('Closed: deploys'), saved.stateText);
            System.assert(saved.canEdit, 'Admins edit');
            Boolean listed = false;
            for (RlyWindowController.WindowView v : views) {
                listed = listed || v.orgId == sitId;
            }
            System.assert(listed, 'SIT is listed');
            System.assertEquals(1, soon.size(), 'One freeze within a week');
            System.assert(soon[0].text.startsWith('SIT freeze starts in 6 days (16 Nov 2026): Go-live week.'), soon[0].text);
        }
    }

    @IsTest
    static void aFreezeHoldsAndOrgsWithoutWindowsDont() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = releaseWithWindow(RlyWindowGate.WAITING);
            Id sitId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            update new RLY_Org__c(Id = sitId, Window_Days__c = null, Window_From__c = null, Window_To__c = null,
                Window_Freezes__c = '[{"from":"2026-11-09","to":"2026-11-11","reason":"Audit"}]');
            RLY_Release__c noWindow = new RLY_Release__c(Target_Org__c = null, Target_Environment__c = 'sit', Status__c = 'Ready for approval');
            RLY_Release__c branchOnly = new RLY_Release__c(Target_Org__c = sitId, Target_Environment__c = null, Status__c = 'Ready for approval');
            RlyWindowGate.nowForTest = OUTSIDE;
            Test.startTest();
            RlyWindowGate.Notice n = RlyWindowGate.noticeFor(RlyReleaseStore.release(rel.Id));
            Boolean heldNoOrg = RlyWindowGate.holds(noWindow);
            Boolean heldBranchOnly = RlyWindowGate.holds(branchOnly);
            RlyWindowGate.Notice none = RlyWindowGate.noticeFor(noWindow);
            Test.stopTest();
            System.assertEquals('frozen', n.kind, 'Frozen');
            System.assert(n.text.startsWith('Frozen until 11 Nov 2026 in SIT: Audit.'), n.text);
            System.assert(!heldNoOrg, 'No target org: nothing to hold');
            System.assert(!heldBranchOnly, 'A branch-only back promote isn\'t held');
            System.assertEquals('none', none.kind, 'Not waiting');
        }
    }
}
