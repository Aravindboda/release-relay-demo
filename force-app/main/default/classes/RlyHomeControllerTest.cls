/**
 * @description Tests for the Home tab (RlyHomeController, RlyHomeStats, RlyHomeNeeds, RlyHomeProblems, RlyHomeRoute,
 * RlyHomeHealth, RlyHomeSlackHealth). Route DEV1 -> SIT -> PROD (hub). Each test runs through System.runAs: as an active
 * System Administrator with Release Relay Admin (approver, deployment team and developer), or as a new user without
 * Release Relay permission sets (developer only). Nothing calls out: the page reads saved records only.
 */
@IsTest
private class RlyHomeControllerTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    // A release between two orgs at a status (not inserted).
    private static RLY_Release__c rel(String status, String source, String target) {
        return new RLY_Release__c(Title__c = status + ' change', Status__c = status, Mode__c = 'Org changes', Request_Type__c = 'Changes',
            Release_Type__c = 'Release', Source_Org__c = orgId(source), Target_Org__c = orgId(target), Org_Label__c = source,
            Target_Branch__c = target.toLowerCase(), Approval_Status__c = 'Pending');
    }

    private static RLY_Release_Event__c event(Id releaseId, String eventType, String org) {
        return new RLY_Release_Event__c(Release__c = releaseId, Event_Type__c = eventType, Org__c = orgId(org),
            Actor__c = UserInfo.getUserId(), Via__c = 'Salesforce', Detail__c = eventType + ' detail', Occurred_On__c = System.now());
    }

    // Releases raised by the current user: one ready, a promotion ready, a hotfix needing two approvers (left out for
    // whoever raised it), failed checks with conflicts, a failed deploy, a deploy with a back-merge conflict.
    private static Map<String, RLY_Release__c> releases() {
        RlyReleaseTestData.route();
        RLY_Release__c promotion = rel('Ready for approval', 'SIT', 'PROD');
        promotion.Release_Type__c = 'Promotion';
        RLY_Release__c hotfix = rel('Ready for approval', 'DEV1', 'SIT');
        hotfix.Is_Hotfix__c = true;
        hotfix.Hotfix_Reason__c = 'Duplicate emails';
        RLY_Release__c hotProd = rel('Ready for approval', 'SIT', 'PROD');
        hotProd.Is_Hotfix__c = true;
        hotProd.Hotfix_Reason__c = 'Payments down';
        RLY_Release__c conflict = rel('Checks failed', 'DEV1', 'SIT');
        conflict.Validation_Result__c = RlyReleaseTestData.conflictResult();
        RLY_Release__c deployFailed = rel('Deploy failed', 'DEV1', 'SIT');
        deployFailed.Error_Message__c = 'Missing field Region__c\nmore';
        RLY_Release__c backMerge = rel('Deployed', 'SIT', 'PROD');
        backMerge.Back_Merge_Result__c = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'branch' => 'sit', 'status' => 'Synced' },
            new Map<String, Object>{ 'branch' => 'dev1', 'status' => 'Conflict', 'message' => '1 file' } });
        Map<String, RLY_Release__c> byKey = new Map<String, RLY_Release__c>{ 'ready' => rel('Ready for approval', 'DEV1', 'SIT'),
            'promotion' => promotion, 'hotfix' => hotfix, 'hotProd' => hotProd, 'conflict' => conflict, 'deployFailed' => deployFailed,
            'backMerge' => backMerge, 'approved' => rel('Approved', 'DEV1', 'SIT') };
        insert byKey.values();
        update new RLY_Org__c(Id = orgId('SIT'), Hotfix_Two_Approvers__c = true, Code_Scan__c = 'Off');
        update new RLY_Org__c(Id = orgId('PROD'), Last_Checked__c = System.now().addDays(-10));
        // A hotfix someone else raised, approved once by them already: the viewer can be its second approver.
        User other = RlyTestData.plainUser();
        RLY_Release__c second = rel('Ready for approval', 'DEV1', 'SIT');
        second.Is_Hotfix__c = true;
        second.Hotfix_Reason__c = 'Login broken';
        second.Approved_By__c = other.Id;
        System.runAs(other) {
            insert second;
        }
        byKey.put('second', second);
        return byKey;
    }

    // Manual steps: before deploy on the approved release (to do), after deploy on the deployed one (to do), and an after
    // deploy step of the approved release (not yet: it isn't deployed).
    private static void steps(Map<String, RLY_Release__c> rels) {
        RLY_Manual_Step__c stepBefore = new RLY_Manual_Step__c(Release__c = rels.get('approved').Id, Title__c = 'Turn off the sync job',
            Category__c = 'Setup', Timing__c = 'Before_Deploy', Sequence__c = 1);
        RLY_Manual_Step__c later = new RLY_Manual_Step__c(Release__c = rels.get('approved').Id, Title__c = 'Reload values',
            Category__c = 'Data', Timing__c = 'After_Deploy', Sequence__c = 2);
        RLY_Manual_Step__c stepAfter = new RLY_Manual_Step__c(Release__c = rels.get('backMerge').Id, Title__c = 'Assign permission set',
            Category__c = 'Permissions', Timing__c = 'After_Deploy', Sequence__c = 1);
        insert new List<RLY_Manual_Step__c>{ stepBefore, later, stepAfter };
        insert new List<RLY_Manual_Step_Run__c>{
            new RLY_Manual_Step_Run__c(Step__c = stepBefore.Id, Release__c = rels.get('approved').Id, Org__c = orgId('SIT'), Status__c = 'To_Do'),
            new RLY_Manual_Step_Run__c(Step__c = later.Id, Release__c = rels.get('approved').Id, Org__c = orgId('SIT'), Status__c = 'To_Do'),
            new RLY_Manual_Step_Run__c(Step__c = stepAfter.Id, Release__c = rels.get('backMerge').Id, Org__c = orgId('PROD'), Status__c = 'To_Do')
        };
    }

    private static void events(Map<String, RLY_Release__c> rels) {
        RLY_Release_Event__c failed = event(rels.get('deployFailed').Id, 'Deploy_Failed', 'SIT');
        failed.Occurred_On__c = System.now().addDays(-8);
        insert new List<RLY_Release_Event__c>{ event(rels.get('backMerge').Id, 'Deployed', 'PROD'),
            event(rels.get('approved').Id, 'Deployed', 'SIT'), failed, event(rels.get('backMerge').Id, 'Rolled_Back', 'SIT'),
            event(rels.get('ready').Id, 'Raised', 'DEV1') };
    }

    private static RlyHomeNeeds.NeedGroup groupOf(RlyHomeController.Home h, String key) {
        for (RlyHomeNeeds.NeedGroup g : h.needs.groups) {
            if (g.key == key) {
                return g;
            }
        }
        return null;
    }

    private static Map<String, RLY_Release__c> everything() {
        Map<String, RLY_Release__c> rels = releases();
        steps(rels);
        events(rels);
        return rels;
    }

    @IsTest
    static void adminNeedsEveryRole() {
        System.runAs(RlyTestData.admin()) {
            Map<String, RLY_Release__c> rels = everything();
            Test.startTest();
            RlyHomeController.Home h = RlyHomeController.read();
            Test.stopTest();
            System.assert(h.isAdmin, 'Admin');
            System.assertEquals(new List<String>{ 'approver', 'deploy team', 'developer' }, h.needs.roles, 'Every role');
            RlyHomeNeeds.NeedGroup approvals = groupOf(h, RlyHomeNeeds.GROUP_APPROVALS);
            System.assertEquals(4, approvals.rows.size(), 'All but the own hotfix needing two approvers');
            System.assertEquals(4, h.needs.approvalCount, 'Counted for the tile');
            Map<Id, RlyHomeNeeds.NeedRow> approvalRows = new Map<Id, RlyHomeNeeds.NeedRow>();
            for (RlyHomeNeeds.NeedRow r : approvals.rows) {
                approvalRows.put(r.releaseId, r);
            }
            System.assertEquals('DEV1 → SIT', approvalRows.get(rels.get('ready').Id).org, 'Source to target');
            System.assertEquals('Ready', approvalRows.get(rels.get('ready').Id).pill, 'Ready pill');
            System.assertEquals('Promotion', approvalRows.get(rels.get('promotion').Id).pill, 'Promotion pill');
            System.assertEquals('Hotfix', approvalRows.get(rels.get('hotProd').Id).pill, 'Hotfix pill');
            System.assertEquals('2nd approver', approvalRows.get(rels.get('second').Id).pill, 'Second approver pill');
            System.assert(approvalRows.get(rels.get('second').Id).note.endsWith('Waiting for a second approver.'), 'Note');
            RlyHomeNeeds.NeedGroup todo = groupOf(h, RlyHomeNeeds.GROUP_STEPS);
            System.assertEquals(2, todo.rows.size(), 'Before deploy of the approved one, after deploy of the deployed one');
            Set<String> stepPills = new Set<String>();
            for (RlyHomeNeeds.NeedRow r : todo.rows) {
                stepPills.add(r.pill + ' ' + r.org);
            }
            System.assertEquals(new Set<String>{ 'Before deploy SIT', 'After deploy PROD' }, stepPills, 'Steps and orgs');
            RlyHomeNeeds.NeedGroup mine = groupOf(h, RlyHomeNeeds.GROUP_MINE);
            System.assertEquals(3, mine.rows.size(), 'Conflicts, deploy failed, back-merge conflict');
            Set<String> pills = new Set<String>();
            for (RlyHomeNeeds.NeedRow r : mine.rows) {
                pills.add(r.pill);
            }
            System.assert(pills.contains('2 to review') && pills.contains('Deploy failed') && pills.contains('1 to review'), 'Pills ' + pills);
        }
    }

    @IsTest
    static void tilesChartAndActivity() {
        System.runAs(RlyTestData.admin()) {
            Map<String, RLY_Release__c> rels = everything();
            Test.startTest();
            RlyHomeController.Home h = RlyHomeController.read();
            Test.stopTest();
            RlyHomeStats.Kpis k = h.kpis;
            System.assertEquals(7, k.openCount, 'Five ready, checks failed, approved');
            System.assertEquals(3, k.hotfixCount, 'Three open hotfixes');
            System.assertEquals(5, k.waitingCount, 'Five ready');
            System.assertEquals(4, k.waitingForYou, 'Four for the viewer');
            System.assertEquals(1, k.checksFailed, 'One failed check');
            System.assertEquals(1, k.checksFailedYours, 'Raised by the viewer');
            System.assertEquals(2, k.deployedWeek, 'Two deploys now');
            System.assertEquals(1, k.deployedToHub, 'One to the hub');
            System.assertEquals(1, k.rollbacks, 'One rollback');
            System.assertEquals(rels.get('backMerge').Id, [SELECT Id FROM RLY_Release__c WHERE Name = :k.lastRollbackName].Id, 'Its release');
            System.assertEquals(2, k.leadCount, 'Two releases deployed');
            System.assertNotEquals(null, k.leadDays, 'Average known');

            System.assertEquals(RlyHomeStats.WEEK_COUNT, h.weeks.size(), 'Eight weeks');
            System.assertEquals(2, h.weeks[RlyHomeStats.WEEK_COUNT - 1].deployed, 'This week');
            Integer failedBars = 0;
            for (RlyHomeStats.WeekBar b : h.weeks) {
                failedBars += b.failed;
            }
            System.assertEquals(1, failedBars, 'The failed deploy of last week');
            System.assertEquals(5, h.activity.size(), 'Every event');
            System.assertEquals(2, h.weekByOrg.size(), 'PROD and SIT this week');
            System.assertEquals('PROD', h.weekByOrg[0].orgName, 'By name');
            System.assertEquals(1, h.weekByOrg[0].deployed, 'One deploy to PROD');
        }
    }

    @IsTest
    static void routeBoard() {
        System.runAs(RlyTestData.admin()) {
            Map<String, RLY_Release__c> rels = everything();
            Test.startTest();
            RlyHomeController.Home h = RlyHomeController.read();
            Test.stopTest();
            RlyHomeRoute.Route route = h.route;
            System.assert(route.isSet, 'Route set');
            System.assertEquals('DEV1 → SIT → PROD', route.path, 'Path');
            System.assertEquals(3, route.stops.size(), 'Three stops');
            System.assertEquals(RlyHomeRoute.KIND_DEVELOPER, route.stops[0].kind, 'Developer first');
            System.assertEquals('PROD', route.stops[1].nextName, 'SIT goes to PROD');
            System.assertEquals('Stage 1', route.stops[1].roleText, 'Stage 1');
            System.assertEquals(2, route.stops[2].count, 'Promotion and hotfix waiting into PROD');
            System.assertEquals('Not checked 10 days', route.stops[2].statusText, 'Stale hub');
            System.assertEquals('wait', route.stops[2].statusTone, 'Amber');
            System.assertEquals(rels.get('backMerge').Id, route.stops[2].lastId, 'Last deploy to PROD');
        }
    }

    @IsTest
    static void healthReadsSavedChecks() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Git_Connection__c git = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            git.Status_Message__c = 'Connected. Pipeline files found on main.';
            git.Last_Checked__c = System.now();
            update git;
            update new RLY_Org__c(Id = orgId('SIT'), Code_Scan__c = 'Off', Approval_In__c = 'Slack');
            RlyReleaseTestData.slackOn('Deployed');
            Test.startTest();
            RlyHomeHealth.Health h = RlyHomeHealth.read();
            Test.stopTest();
            Map<String, RlyHomeHealth.Item> byKey = new Map<String, RlyHomeHealth.Item>();
            for (RlyHomeHealth.Item i : h.items) {
                byKey.put(i.key, i);
            }
            System.assertEquals('Connected', byKey.get('git').text, 'Git connected');
            System.assert(byKey.get('files').text.startsWith('found'), 'Files found: ' + byKey.get('files').text);
            System.assertEquals('Not tested', byKey.get('slack').text, 'Slack on, nothing sent yet');
            System.assertNotEquals(null, byKey.get('approve'), 'SIT approves in Slack');
            System.assertEquals('Off for SIT', byKey.get('scan').text, 'Scan off for SIT');
            System.assert(!h.allOk && h.attention >= 1, 'Something needs attention');
            System.assertNotEquals(null, h.checkedOn, 'Checked time');
        }
    }

    @IsTest
    static void slackItemsWord() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('Off', RlyHomeSlackHealth.slackItem(null).text, 'No record');
            RLY_Notification__c s = new RLY_Notification__c(Enabled__c = true, Last_Result__c = 'Sent 2 messages');
            System.assertEquals('Connected', RlyHomeSlackHealth.slackItem(s).text, 'Sent');
            s.Last_Result__c = 'Error: channel_not_found';
            System.assertEquals(RlyHomeHealth.TONE_BAD, RlyHomeSlackHealth.slackItem(s).tone, 'Failed');
            System.assertEquals(null, RlyHomeSlackHealth.approveItem(null, new List<RLY_Org__c>()), 'Slack off');
            RlyReleaseTestData.route();
            update new RLY_Org__c(Id = orgId('PROD'), Approval_In__c = 'Slack');
            RLY_Notification__c saved = new RLY_Notification__c(Name = 'Slack', Channel__c = 'Slack', Enabled__c = true);
            insert saved;
            List<RLY_Org__c> orgs = [SELECT Id, Name, Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c FROM RLY_Org__c
                                     WHERE Role__c IN ('Stage', 'Hub') ORDER BY Name];
            System.assertEquals('signing secret not saved', RlyHomeSlackHealth.approveItem(saved, orgs).text, 'No secret');
            saved.Signing_Secret__c = RlyReleaseTestData.SIGNING_SECRET;
            RlyHomeHealth.Item i = RlyHomeSlackHealth.approveItem(saved, orgs);
            System.assert(i.text == 'Site not set up' || i.text == 'Ready' || i.text.endsWith('not linked'), 'Site or approvers: ' + i.text);
            System.assertEquals('Ready', RlyHomeSlackHealth.linkState(RlyHomeHealth.item('a', 'A'), 0).text, 'All linked');
            System.assertEquals('1 approver not linked', RlyHomeSlackHealth.linkState(RlyHomeHealth.item('a', 'A'), 1).text, 'One');
            System.assertEquals('2 approvers not linked', RlyHomeSlackHealth.linkState(RlyHomeHealth.item('a', 'A'), 2).text, 'Two');
            s.Last_Result__c = null;
            System.assertEquals('Not tested', RlyHomeSlackHealth.slackItem(s).text, 'Nothing sent yet');
        }
    }

    @IsTest
    static void emptyOrgAsDeveloper() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            Test.startTest();
            RlyHomeController.Home h = RlyHomeController.read();
            Test.stopTest();
            System.assert(!h.isAdmin, 'Not an admin');
            System.assertEquals(new List<String>{ 'developer' }, h.needs.roles, 'Developer only');
            System.assertEquals(0, h.needs.groups[0].rows.size(), 'Nothing wrong');
            System.assertEquals(0, h.kpis.openCount, 'No releases');
            System.assertEquals(null, h.kpis.leadDays, 'No deploys yet');
            System.assert(!h.route.isSet, 'No route yet');
            System.assertEquals(0, h.route.stops.size(), 'No stops');
            System.assertEquals(0, h.activity.size(), 'No events');
            System.assertEquals('Not set up', h.health.items[0].text, 'No Git connection');
            System.assertEquals('Off', h.health.items[3].text, 'Code scan off without a connection');
        }
    }

    @IsTest
    static void developerOrgsGroupAndStatuses() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Org__c dev2 = RlyTestData.org('DEV2', 'Developer', 'dev2');
            dev2.Status__c = 'Failed';
            insert dev2;
            update new RLY_Org__c(Id = orgId('SIT'), Status__c = 'Refreshed');
            update new RLY_Org__c(Id = orgId('PROD'), Status__c = null);
            insert rel('Validating', 'DEV1', 'SIT');
            RLY_Release__c deployed = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            update new RLY_Release__c(Id = deployed.Id, Is_Hotfix__c = true, Hotfix_Reason__c = 'Urgent');
            Test.startTest();
            RlyHomeRoute.Route r = RlyHomeRoute.read();
            Test.stopTest();
            RlyHomeRoute.Stop devs = r.stops[0];
            System.assertEquals('2 developer orgs', devs.name, 'Grouped');
            System.assertEquals('Failed', devs.statusText, 'The org that failed shows');
            System.assertEquals(1, devs.count, 'One open release raised');
            System.assertNotEquals(null, devs.lastName, 'Last raised');
            System.assertEquals('Refreshed', r.stops[1].statusText, 'Refreshed SIT');
            System.assertEquals(1, r.stops[1].count, 'One ready to promote');
            System.assertEquals(1, r.stops[1].hotfixCount, 'A hotfix');
            System.assertEquals('Not checked', r.stops[2].statusText, 'Never checked');
        }
    }

    @IsTest
    static void rulesAndHelpers() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(Date.newInstance(2026, 10, 26), RlyHomeStats.weekStart(Date.newInstance(2026, 11, 1)), 'Sunday to Monday');
            System.assertEquals(Date.newInstance(2026, 10, 26), RlyHomeStats.weekStart(Date.newInstance(2026, 10, 26)), 'Monday stays');
            System.assertEquals(0, RlyHomeProblems.backMergeConflicts('not json'), 'Unreadable');
            System.assertEquals(0, RlyHomeProblems.backMergeConflicts(null), 'Blank');
            System.assertEquals(0, RlyHomeProblems.conflictFiles(null), 'No result');
            Id me = UserInfo.getUserId();
            RLY_Org__c two = new RLY_Org__c(Name = 'PROD', Hotfix_Two_Approvers__c = true);
            RLY_Release__c hot = new RLY_Release__c(Is_Hotfix__c = true, Status__c = 'Ready for approval', Approval_Status__c = 'Pending');
            hot.Target_Org__r = two;
            System.assert(RlyHomeNeeds.mayApprove(hot, me), 'Raised by someone else (no creator here)');
            hot.Approved_By__c = me;
            System.assert(!RlyHomeNeeds.mayApprove(hot, me), 'Already the first approver');
            System.assert(RlyHomeNeeds.mayApprove(new RLY_Release__c(Status__c = 'Ready for approval'), me), 'Plain release');
            RlyReleaseTestData.route();
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Code_Scan__c = false,
                Status__c = 'Failed', Status_Message__c = 'Bad credential');
            update new RLY_Org__c(Id = orgId('PROD'), Code_Scan__c = 'On');
            RlyHomeHealth.Health h = RlyHomeHealth.read();
            System.assertEquals('Failed', h.items[0].text, 'Git failed');
            System.assertEquals('not checked', h.items[1].text, 'Files not checked without a connection');
            System.assertEquals('On for PROD', h.items[h.items.size() - 1].text, 'Scan on for PROD only');
        }
    }
}
