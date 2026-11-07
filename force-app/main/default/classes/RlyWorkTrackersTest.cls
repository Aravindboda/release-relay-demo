/**
 * @description Tests for several work trackers (build 47): each ticket goes to the first active tracker whose pattern
 * matches (a tracker without a pattern takes the rest; no match is refused with the patterns named), keeps it, and
 * posts, links and the ServiceNow change gate use that ticket's own tracker; admins add, edit, turn off, reorder and
 * test trackers, with every value checked; the build 40 setting becomes the first tracker; tickets are added to a raised
 * release with a line in its history. Trackers answer through RlyHttpMock; nothing depends on org data. Each test runs
 * as an active System Administrator through System.runAs.
 */
@IsTest
private class RlyWorkTrackersTest {

    private static final String CLAIMS = 'CLAIMS-\\d+';
    private static final String CHANGES = 'CHG\\d{7}';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // An active tracker (not saved); its place in the routing order is set by the caller's list (saved()).
    private static RLY_Work_Tracker__c tracker(String name, String kind, String patterns) {
        return new RLY_Work_Tracker__c(Name = name, Type__c = kind, Ticket_Pattern__c = patterns, Active__c = true,
            Link_Pattern__c = 'https://' + kind.toLowerCase() + '.example.com/{id}');
    }

    private static List<RLY_Work_Tracker__c> saved(List<RLY_Work_Tracker__c> rows) {
        for (Integer i = 0; i < rows.size(); i++) {
            rows[i].Sort_Order__c = i + 1;
        }
        insert rows;
        RlyWorkStore.forgetTrackers();
        return rows;
    }

    private static RLY_Release__c make(String status, String orgName, List<String> tickets) {
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Release_Type__c = 'Release', Source_Org__c = orgId('DEV1'), Target_Org__c = orgId(orgName),
            Org_Label__c = 'DEV1', Target_Branch__c = orgName.toLowerCase(), Source_Environment__c = 'dev1',
            Target_Environment__c = orgName.toLowerCase(), Source_Branch__c = 'feature/region', Test_Classes__c = 'AccountServiceTest',
            Scan_Status__c = 'Passed', Validation_Status__c = 'Passed', Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending',
            Component_Count__c = 1);
        insert rel;
        rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
        RlyWorkItems.attach(rel, tickets);
        return rel;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static String errorOf(String trackerJson) {
        try {
            RlyWorkTrackersController.saveTracker(trackerJson);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    @IsTest
    static void eachTicketGoesToTheFirstTrackerThatMatches() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Work_Tracker__c> rows = saved(new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CLAIMS),
                tracker('Change requests', 'ServiceNow', CHANGES), tracker('Old board', 'Azure_Boards', 'AB#\\d+') });
            rows[2].Active__c = false;
            update rows[2];
            RlyWorkStore.forgetTrackers();
            Test.startTest();
            RLY_Work_Tracker__c story = RlyWorkRouting.route('CLAIMS-412');
            RLY_Work_Tracker__c change = RlyWorkRouting.route('CHG0012345');
            String refused;
            try {
                RlyWorkItems.checked(new List<String>{ 'AB#123' }, null);
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            String oldLink = RlyWorkLinks.linkOf('AB#123');
            insert tracker('Ops tasks', 'None', null);
            RlyWorkStore.forgetTrackers();
            RLY_Work_Tracker__c rest = RlyWorkRouting.route('XYZ-1');
            Test.stopTest();
            System.assertEquals('Claims stories', story.Name, 'Jira takes its pattern');
            System.assertEquals('Change requests', change.Name, 'ServiceNow takes its pattern');
            System.assert(refused.startsWith('No tracker matches "AB#123"'), 'No match is refused: ' + refused);
            System.assert(refused.contains('CLAIMS-\\d+ (Claims stories)') && !refused.contains('Old board'), 'Active patterns named: ' + refused);
            System.assertEquals('https://azure_boards.example.com/123', oldLink, 'An inactive tracker\'s ticket keeps its link (Azure: the number)');
            System.assertEquals('Ops tasks', rest.Name, 'A tracker without a pattern takes the rest');
            System.assertEquals('Azure Boards', RlyWorkRouting.kindLabel('Azure_Boards'), 'Kind in words');
            System.assertEquals('Other (link)', RlyWorkRouting.kindLabel('Other'), 'Kind in words');
            System.assertEquals('No integration', RlyWorkRouting.kindLabel('None'), 'Kind in words');
        }
    }

    @IsTest
    static void eachTicketPostsThroughItsOwnTracker() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            List<RLY_Work_Tracker__c> rows = new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CLAIMS),
                tracker('Change requests', 'ServiceNow', CHANGES) };
            rows[0].Named_Credential__c = 'RLY_Work_Jira';
            rows[1].Named_Credential__c = 'RLY_Work_ServiceNow';
            rows[0].Post_Updates__c = true;
            rows[1].Post_Updates__c = true;
            saved(rows);
            RLY_Release__c rel = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-412', 'CHG0012345' });
            RlyHttpMock m = new RlyHttpMock()
                .match('POST', '/rest/api/2/issue/CLAIMS-412/comment').reply(201, '{"id":"1"}')
                .match('GET', '/api/now/table/change_request').reply(200, '{"result":[{"sys_id":"abc"}]}')
                .match('PATCH', '/api/now/table/change_request/abc').reply(200, '{}');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyWorkTypes.ReleaseTickets t = RlyWorkItemsController.syncRelease(rel.Id);
            Test.stopTest();
            Map<String, RlyWorkTypes.TicketView> byTicket = new Map<String, RlyWorkTypes.TicketView>();
            for (RlyWorkTypes.TicketView v : t.tickets) {
                byTicket.put(v.ticket, v);
            }
            System.assertEquals(RlyWorkSync.POSTED, byTicket.get('CLAIMS-412').status, 'Jira: ' + byTicket.get('CLAIMS-412').message);
            System.assertEquals(RlyWorkSync.POSTED, byTicket.get('CHG0012345').status, 'ServiceNow: ' + byTicket.get('CHG0012345').message);
            System.assert(m.callLog().contains('callout:RLY_Work_Jira/rest/api/2/issue/CLAIMS-412/comment'), 'Jira ticket via Jira: ' + m.callLog());
            System.assert(m.callLog().contains('callout:RLY_Work_ServiceNow/api/now/table'), 'Change via ServiceNow: ' + m.callLog());
            System.assertEquals('Change requests', byTicket.get('CHG0012345').tracker, 'The ticket\'s tracker');
            System.assertEquals('https://jira.example.com/CLAIMS-412', byTicket.get('CLAIMS-412').link, 'Its tracker\'s link');
            System.assertEquals(2, [SELECT COUNT() FROM RLY_Work_Item__c WHERE Release__c = :rel.Id AND Tracker__c != null], 'Each row keeps its tracker');
        }
    }

    @IsTest
    static void theChangeGateCountsServiceNowTicketsOnly() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            List<RLY_Work_Tracker__c> rows = new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CHANGES),
                tracker('Change requests', 'ServiceNow', 'SN\\d+') };
            rows[1].Named_Credential__c = 'RLY_Work_ServiceNow';
            saved(rows);
            insert new RLY_Work_Tracking__c(SetupOwnerId = UserInfo.getOrganizationId(), Require_Change__c = true);
            RLY_Release__c rel = make('Ready for approval', 'PROD', new List<String>{ 'CHG0012345' });
            RLY_Release__c full = RlyReleaseStore.release(rel.Id);
            Test.startTest();
            Boolean held = RlyWorkGate.holds(full);
            Test.stopTest();
            System.assert(held, 'A change number in Jira doesn\'t open the gate');
            System.assert(full.Error_Message__c.contains('add the ServiceNow change'), 'Says why: ' + full.Error_Message__c);
        }
    }

    @IsTest
    static void adminsAddEditTurnOffAndReorderTrackers() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyWorkTypes.Settings one = RlyWorkTrackersController.saveTracker(JSON.serialize(new Map<String, Object>{ 'name' => 'Claims stories',
                'kind' => 'Jira', 'ticketPattern' => CLAIMS, 'linkPattern' => 'https://acme.atlassian.net/browse/{id}',
                'namedCredential' => 'RLY_Work_Jira', 'postUpdates' => true, 'stateMap' => '{"Deployed to PROD":"Done"}', 'active' => true }));
            RlyWorkTypes.Settings two = RlyWorkTrackersController.saveTracker(JSON.serialize(new Map<String, Object>{ 'name' => 'Change requests',
                'kind' => 'ServiceNow', 'ticketPattern' => CHANGES, 'serviceNowTable' => 'change_request', 'active' => true }));
            Id jiraId = two.trackers[0].id;
            Id snId = two.trackers[1].id;
            RlyWorkTypes.Settings moved = RlyWorkTrackersController.moveTracker(snId, RlyWorkTrackersController.DIRECTION_UP);
            RlyWorkTypes.Settings back = RlyWorkTrackersController.moveTracker(snId, 'down');
            RlyWorkTypes.Settings off = RlyWorkTrackersController.setTrackerActive(jiraId, 'off');
            RlyWorkTypes.Settings onAgain = RlyWorkTrackersController.setTrackerActive(jiraId, RlyWorkTrackersController.STATE_ON);
            Map<String, Object> rename = new Map<String, Object>{ 'id' => jiraId, 'name' => 'Claims', 'kind' => 'None', 'ticketPattern' => CLAIMS,
                'namedCredential' => 'RLY_Work_Jira', 'postUpdates' => true, 'active' => true };
            RlyWorkTypes.Settings renamed = RlyWorkTrackersController.saveTracker(JSON.serialize(rename));
            RlyWorkTypes.Outcome tested = RlyWorkTrackersController.testTracker(jiraId);
            Test.stopTest();
            System.assertEquals(1, one.trackers.size(), 'Added');
            System.assert(one.trackers[0].postUpdates && one.trackers[0].active, 'Chips kept');
            System.assertEquals('Change requests', moved.trackers[0].name, 'Moved up');
            System.assertEquals(1, moved.trackers[0].position, 'First');
            System.assertEquals('Claims stories', back.trackers[0].name, 'Moved back down');
            System.assert(!off.trackers[0].active, 'Turned off');
            System.assert(onAgain.trackers[0].active, 'Turned on');
            System.assertEquals('Claims', renamed.trackers[0].name, 'Edited');
            System.assertEquals(null, renamed.trackers[0].namedCredential, 'No integration keeps no Named Credential');
            System.assert(!renamed.trackers[0].postUpdates, 'No integration posts nothing');
            System.assertEquals('Change requests', renamed.trackerLabel, 'Label names the integrated trackers');
            System.assert(tested.ok && tested.message.contains('nothing to sign in to'), 'No integration: nothing to test: ' + tested.message);
            System.assertEquals(2, [SELECT COUNT() FROM RLY_Work_Tracker__c WHERE Id != null], 'Two records');
        }
    }

    @IsTest
    static void everyTrackerValueIsChecked() {
        System.runAs(RlyTestData.admin()) {
            saved(new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CLAIMS), tracker('Ops tasks', 'None', null) });
            Map<String, Object> base = new Map<String, Object>{ 'name' => 'Billing', 'kind' => 'Jira', 'ticketPattern' => 'BILL-\\d+', 'active' => true };
            List<Map<String, Object>> changes = new List<Map<String, Object>>{
                new Map<String, Object>{ 'kind' => 'Trello' },
                new Map<String, Object>{ 'name' => ' ' },
                new Map<String, Object>{ 'name' => 'claims STORIES' },
                new Map<String, Object>{ 'ticketPattern' => CLAIMS },
                new Map<String, Object>{ 'ticketPattern' => null },
                new Map<String, Object>{ 'ticketPattern' => '[A' },
                new Map<String, Object>{ 'linkPattern' => 'http://x/{id}' },
                new Map<String, Object>{ 'postUpdates' => true },
                new Map<String, Object>{ 'namedCredential' => 'has space' },
                new Map<String, Object>{ 'kind' => 'ServiceNow', 'serviceNowTable' => 'bad table' },
                new Map<String, Object>{ 'stateMap' => '[1]' },
                new Map<String, Object>{ 'id' => RlyTestData.fakeId('a0X', 1) } };
            List<String> errors = new List<String>();
            Test.startTest();
            for (Map<String, Object> c : changes) {
                Map<String, Object> v = new Map<String, Object>(base);
                v.putAll(c);
                errors.add(errorOf(JSON.serialize(v)));
            }
            String empty = errorOf('');
            String other;
            try {
                RlyWorkTrackersController.testTracker(null);
            } catch (AuraHandledException e) {
                other = e.getMessage();
            }
            String okAsOff = errorOf(JSON.serialize(new Map<String, Object>{ 'name' => 'Old', 'kind' => 'Other', 'ticketPattern' => CLAIMS, 'active' => false }));
            Test.stopTest();
            for (Integer i = 0; i < errors.size(); i++) {
                System.assertNotEquals(null, errors[i], 'Refused: ' + changes[i]);
            }
            System.assert(errors[3].contains('already has the pattern'), 'Same pattern: ' + errors[3]);
            System.assert(errors[4].contains('Ops tasks already takes'), 'One tracker takes the rest: ' + errors[4]);
            System.assertEquals('Nothing to save.', empty, 'Nothing sent');
            System.assert(other.contains('wasn\'t found'), 'Unknown tracker: ' + other);
            System.assertEquals(null, okAsOff, 'An inactive tracker may repeat a pattern');
        }
    }

    @IsTest
    static void testSignsInThroughTheNamedCredential() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Work_Tracker__c> rows = new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CLAIMS),
                tracker('Azure items', 'Azure_Boards', 'AB#\\d+'), tracker('Incidents', 'ServiceNow', 'INC\\d+'), tracker('Hook', 'Other', 'T-\\d+') };
            for (RLY_Work_Tracker__c t : rows) {
                t.Named_Credential__c = 'RLY_Work_' + t.Type__c;
            }
            rows[2].ServiceNow_Table__c = 'incident';
            saved(rows);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/rest/api/2/myself').reply(200, '{"displayName":"Release Bot"}')
                .match('GET', '/_apis/wit/workitemtypes').reply(200, '{"count":3}')
                .match('GET', '/api/now/table/incident').reply(401, '{"error":"no"}'));
            Test.startTest();
            RlyWorkTypes.Outcome jira = RlyWorkTrackersController.testTracker(rows[0].Id);
            RlyWorkTypes.Outcome azure = RlyWorkTrackersController.testTracker(rows[1].Id);
            RlyWorkTypes.Outcome now = RlyWorkTrackersController.testTracker(rows[2].Id);
            RlyWorkTypes.Outcome hook = RlyWorkTrackersController.testTracker(rows[3].Id);
            Test.stopTest();
            System.assert(jira.ok && jira.message.contains('Release Bot'), 'Jira: ' + jira.message);
            System.assert(azure.ok, 'Azure Boards: ' + azure.message);
            System.assert(!now.ok && now.message.contains('401'), 'ServiceNow refused: ' + now.message);
            System.assert(hook.ok && hook.message.contains('https://other.example.com/TICKET-1'), 'Other: its link: ' + hook.message);
        }
    }

    @IsTest
    static void theBuild40SettingBecomesTheFirstTracker() {
        System.runAs(RlyTestData.admin()) {
            insert new RLY_Work_Tracking__c(SetupOwnerId = UserInfo.getOrganizationId(), Tracker__c = 'Jira', Ticket_Pattern__c = CLAIMS,
                Link_Pattern__c = 'https://acme.atlassian.net/browse/{id}', Named_Credential__c = 'RLY_Work_Jira', Post_Updates__c = true,
                State_Map__c = '{"Deployed to SIT":"In QA"}', Required__c = true);
            RlyWorkStore.forgetTrackers();
            Test.startTest();
            List<RLY_Work_Tracker__c> before = RlyWorkStore.trackers();
            Id unsavedId = before[0].Id;
            String link = RlyWorkLinks.linkOf('CLAIMS-1');
            RlyWorkTypes.Settings s = RlyWorkItemsController.settings();
            RlyWorkStore.forgetTrackers();
            RlyWorkTypes.Settings again = RlyWorkItemsController.settings();
            Test.stopTest();
            System.assertEquals(null, unsavedId, 'Read before any page saves it: in memory');
            System.assertEquals('https://acme.atlassian.net/browse/CLAIMS-1', link, 'Links work as before');
            RLY_Work_Tracker__c row = [SELECT Name, Type__c, Ticket_Pattern__c, Named_Credential__c, Post_Updates__c, State_Map__c, Active__c
                                       FROM RLY_Work_Tracker__c];
            System.assertEquals('Jira', row.Name, 'Named after its kind');
            System.assert(row.Post_Updates__c && row.Active__c && row.Named_Credential__c == 'RLY_Work_Jira', 'Same posting');
            System.assertEquals(CLAIMS, row.Ticket_Pattern__c, 'Same pattern');
            System.assertEquals(1, s.trackers.size(), 'One tracker');
            System.assert(s.required, 'Tickets still required');
            System.assertEquals(1, again.trackers.size(), 'Made once');
            System.assertEquals(null, RlyWorkSettings.fromLegacy(null), 'No setting: no tracker');
        }
    }

    @IsTest
    static void ticketsAreAddedToARaisedRelease() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            List<RLY_Work_Tracker__c> rows = saved(new List<RLY_Work_Tracker__c>{ tracker('Claims stories', 'Jira', CLAIMS),
                tracker('Billing stories', 'Jira', 'BILL-\\d+') });
            RLY_Release__c rel = make('Ready for approval', 'SIT', new List<String>{ 'CLAIMS-1' });
            RLY_Release__c done = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-2' });
            rows[0].Active__c = false;
            update rows[0];
            RlyWorkStore.forgetTrackers();
            List<String> errors = new List<String>();
            Test.startTest();
            RlyWorkTypes.ReleaseTickets added = RlyWorkItemsController.addReleaseTickets(rel.Id, new List<String>{ ' bill-7 ' });
            for (List<Object> call : new List<List<Object>>{ new List<Object>{ rel.Id, new List<String>{ 'CLAIMS-1' } },
                    new List<Object>{ rel.Id, new List<String>{ 'ZZZ-1' } }, new List<Object>{ done.Id, new List<String>{ 'BILL-8' } } }) {
                try {
                    RlyWorkItemsController.addReleaseTickets((Id) call[0], (List<String>) call[1]);
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            RlyWorkTypes.ReleaseTickets synced = RlyWorkItemsController.syncRelease(rel.Id);
            RlyWorkTypes.Board b = RlyWorkItemsController.board();
            Test.stopTest();
            System.assertEquals(2, added.tickets.size(), 'Added beside the one already there (its tracker off: not matched again)');
            RLY_Release_Event__c ev = [SELECT Detail__c, Via__c FROM RLY_Release_Event__c WHERE Release__c = :rel.Id AND Event_Type__c = :RlyWorkHistory.EVENT_TYPE];
            System.assertEquals('Tickets added: BILL-7 (Billing stories), at Ready for approval in SIT', ev.Detail__c, 'History');
            System.assertEquals(RlyReleaseLog.VIA_SALESFORCE, ev.Via__c, 'By a person in Salesforce');
            System.assertEquals(3, errors.size(), 'Nothing new, no tracker, deployed: ' + errors);
            System.assert(errors[1].contains('No tracker matches'), 'No tracker: ' + errors[1]);
            System.assert(errors[2].contains('stay as they are'), 'Deployed: ' + errors[2]);
            for (RlyWorkTypes.TicketView t : synced.tickets) {
                System.assertEquals('Ready for approval in SIT', t.posted, 'Starts at the current stage: ' + t.ticket);
            }
            Map<String, RlyWorkTypes.TicketRow> byTicket = new Map<String, RlyWorkTypes.TicketRow>();
            for (RlyWorkTypes.TicketRow r : b.tickets) {
                byTicket.put(r.ticket, r);
            }
            System.assertEquals('Billing stories', byTicket.get('BILL-7').tracker, 'Tracker column');
            System.assertEquals('Jira', byTicket.get('BILL-7').trackerType, 'Its kind');
            System.assert(byTicket.get('BILL-7').searchText.contains('billing stories'), 'Searchable by tracker');
            System.assertEquals(new List<String>{ 'Claims stories', 'Billing stories' }, b.trackers, 'Filter: every tracker');
            System.assertEquals('Billing stories', b.trackerLabel, 'Active trackers named');
        }
    }

    @IsTest
    static void aTrackerTurnedOffPostsNothing() {
        System.runAs(RlyTestData.admin()) {
            RLY_Work_Tracker__c t = tracker('Claims stories', 'Jira', CLAIMS);
            t.Named_Credential__c = 'RLY_Work_Jira';
            t.Post_Updates__c = true;
            Test.startTest();
            Boolean onPosts = RlyWorkTracker.posts(t);
            t.Active__c = false;
            Boolean offPosts = RlyWorkTracker.posts(t);
            RlyWorkTypes.TrackerView v = RlyWorkSettings.trackerView(t, 1);
            Test.stopTest();
            System.assert(onPosts, 'Active and posting');
            System.assert(!offPosts, 'Off: nothing posted');
            System.assertEquals('Jira', v.kindLabel, 'View');
            System.assert(!v.active, 'View: off');
        }
    }
}
