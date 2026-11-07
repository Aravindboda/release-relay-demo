/**
 * @description Tests for Work items (build 40): tickets checked and saved on raise, carried by promotions and edited on
 * the release; the settings (admins, every value checked); the Work items tab worked out from the releases; posting
 * moments to Jira, Azure Boards, ServiceNow or a web call (and "tracked here" without an integration), a failed post
 * kept for Try again; the ServiceNow change gate holding a production deploy and letting it go once the change is
 * approved. Trackers answer through RlyHttpMock; nothing depends on org data. Each test runs as an active System
 * Administrator through System.runAs.
 */
@IsTest
private class RlyWorkItemsTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Work_Tracking__c settings(String tracker, Boolean post) {
        RLY_Work_Tracking__c s = new RLY_Work_Tracking__c(Name = 'Work tracking', Tracker__c = tracker, Post_Updates__c = post,
            Named_Credential__c = 'Tracker_NC', Ticket_Pattern__c = '[A-Z][A-Z0-9]+-\\d+ CHG\\d{7}',
            Link_Pattern__c = 'https://tracker.example.com/browse/{id}', State_Map__c = '{"Deployed to SIT":"In QA"}',
            Change_Pattern__c = 'CHG\\d{7}');
        insert s;
        return s;
    }

    // A release into an org of the route (RlyReleaseTestData.route() already run), with its tickets.
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

    private static RlyWorkTypes.Message msg(String ticket, String moment, Map<String, Object> data) {
        RlyWorkTypes.Message m = new RlyWorkTypes.Message();
        m.ticket = ticket;
        m.moment = moment;
        m.text = 'text';
        m.data = data;
        return m;
    }

    @IsTest
    static void ticketsAreCheckedAgainstTheFormat() {
        System.runAs(RlyTestData.admin()) {
            RLY_Work_Tracking__c s = new RLY_Work_Tracking__c(Ticket_Pattern__c = '[A-Z]+-\\d+ CHG\\d{7}', Required__c = true);
            Test.startTest();
            List<String> ok = RlyWorkItems.checked(new List<String>{ ' claims-412 ', 'CLAIMS-412', 'CHG0012345', '' }, s);
            List<String> errors = new List<String>();
            for (List<String> bad : new List<List<String>>{ new List<String>{ 'not a ticket' }, new List<String>(), new List<String>{ 'ABC' } }) {
                try {
                    RlyWorkItems.checked(bad, s);
                    errors.add('none');
                } catch (RlyReleaseException e) {
                    errors.add(e.getMessage());
                }
            }
            List<String> free = RlyWorkItems.checked(new List<String>{ 'anything-1' }, null);
            Test.stopTest();
            System.assertEquals(new List<String>{ 'CLAIMS-412', 'CHG0012345' }, ok, 'Trimmed, upper-cased, no repeats, blanks skipped');
            System.assert(errors[0].contains('isn\'t a ticket number'), 'Spaces refused: ' + errors[0]);
            System.assertEquals(RlyWorkItems.REQUIRED, errors[1], 'Required');
            System.assert(errors[2].contains('expected'), 'Format named: ' + errors[2]);
            System.assertEquals(new List<String>{ 'ANYTHING-1' }, free, 'No settings: any ticket');
        }
    }

    @IsTest
    static void ticketsAreSavedCarriedAndEdited() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Ready for approval', 'SIT', new List<String>{ 'CLAIMS-412', 'CLAIMS-418' });
            RLY_Release__c promotion = new RLY_Release__c(Title__c = 'Promote', Status__c = 'Submitted', Release_Type__c = 'Promotion',
                Source_Org__c = orgId('SIT'), Target_Org__c = orgId('PROD'));
            insert promotion;
            Test.startTest();
            RlyWorkItems.carry(promotion, new Set<Id>{ rel.Id });
            RlyWorkTypes.ReleaseTickets edited = RlyWorkItemsController.setReleaseTickets(rel.Id, new List<String>{ 'CLAIMS-418', 'CHG0012345' });
            Test.stopTest();
            System.assertEquals('CLAIMS-412, CLAIMS-418', [SELECT Work_Items__c FROM RLY_Release__c WHERE Id = :promotion.Id].Work_Items__c,
                'A promotion carries the tickets');
            System.assertEquals(2, edited.tickets.size(), 'Edited');
            System.assertEquals('CLAIMS-418, CHG0012345', [SELECT Work_Items__c FROM RLY_Release__c WHERE Id = :rel.Id].Work_Items__c,
                'The list follows the rows');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Work_Item__c WHERE Release__c = :rel.Id AND Ticket__c = 'CLAIMS-412'], 'A removed ticket goes');
            System.assert(edited.canEdit, 'Still editable before deploy');
        }
    }

    @IsTest
    static void aDeployedReleaseKeepsItsTickets() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-412' });
            String error;
            Test.startTest();
            try {
                RlyWorkItemsController.setReleaseTickets(rel.Id, new List<String>());
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assert(error != null && error.contains('stay as they are'), 'Deployed: tickets fixed: ' + error);
        }
    }

    @IsTest
    static void settingsAreCheckedAndSaved() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> good = new Map<String, Object>{ 'tracker' => 'ServiceNow', 'required' => true, 'ticketPattern' => 'CHG\\d{7}',
                'linkPattern' => 'https://acme.service-now.com/nav_to.do?uri=change_request.do?sysparm_query=number={id}',
                'namedCredential' => 'ServiceNow_NC', 'postUpdates' => true, 'requireChange' => true, 'stateMap' => '{"Deployed to PROD":"3"}' };
            List<Map<String, Object>> bads = new List<Map<String, Object>>{
                new Map<String, Object>{ 'tracker' => 'Trello' },
                new Map<String, Object>{ 'tracker' => 'Jira', 'ticketPattern' => '[A-Z' },
                new Map<String, Object>{ 'tracker' => 'Jira', 'linkPattern' => 'http://x/{id}' },
                new Map<String, Object>{ 'tracker' => 'Jira', 'postUpdates' => true },
                new Map<String, Object>{ 'tracker' => 'Jira', 'namedCredential' => 'has space' },
                new Map<String, Object>{ 'tracker' => 'Jira', 'stateMap' => '[1]' } };
            Test.startTest();
            RlyWorkTypes.Settings saved = RlyWorkItemsController.saveSettings(JSON.serialize(good));
            List<String> errors = new List<String>();
            for (Map<String, Object> b : bads) {
                try {
                    RlyWorkItemsController.saveSettings(JSON.serialize(b));
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            RlyWorkTypes.Settings read = RlyWorkItemsController.settings();
            Test.stopTest();
            System.assertEquals('ServiceNow', saved.tracker, 'Saved');
            System.assert(saved.requireChange && saved.postUpdates && saved.required, 'Toggles kept');
            System.assertEquals(6, errors.size(), 'Every bad value refused: ' + errors);
            System.assertEquals('ServiceNow', read.trackerLabel, 'Read back');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Work_Tracking__c WHERE Id != null], 'One record');
        }
    }

    @IsTest
    static void withoutIntegrationTicketsAreTrackedHere() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-412' });
            Test.startTest();
            RlyWorkTypes.ReleaseTickets t = RlyWorkItemsController.syncRelease(rel.Id);
            Integer again = RlyWorkItemsController.syncRecent();
            Integer onPage = RlyWorkItemsController.releaseTickets(rel.Id).tickets.size();
            RlyWorkTypes.Board b = RlyWorkItemsController.board();
            Test.stopTest();
            System.assertEquals(RlyWorkSync.TRACKED_HERE, t.tickets[0].status, 'Tracked in Release Relay');
            System.assertEquals('Deployed to SIT', t.tickets[0].posted, 'The moment');
            System.assertEquals(0, again, 'A moment is recorded once');
            System.assertEquals(1, onPage, 'The release page reads it');
            System.assertEquals(new List<String>{ 'SIT', 'PROD' }, b.orgs, 'Stages, then the hub');
            System.assertEquals(1, b.tickets.size(), 'One ticket');
            System.assertEquals('ok', b.tickets[0].cells[0].tone, 'Deployed in SIT');
            System.assertEquals('In progress', b.tickets[0].status, 'Not in PROD yet');
            System.assertEquals('Tracked in Release Relay', b.trackerLabel, 'No integration');
        }
    }

    @IsTest
    static void theBoardShowsBlockedWaitingAndInProduction() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            make('Checks failed', 'SIT', new List<String>{ 'CLAIMS-1' });
            make('Ready for approval', 'SIT', new List<String>{ 'CLAIMS-2' });
            make('Deployed', 'PROD', new List<String>{ 'CLAIMS-3' });
            settings('Jira', false);
            Test.startTest();
            RlyWorkTypes.Board b = RlyWorkItemsController.board();
            Test.stopTest();
            Map<String, RlyWorkTypes.TicketRow> byTicket = new Map<String, RlyWorkTypes.TicketRow>();
            for (RlyWorkTypes.TicketRow r : b.tickets) {
                byTicket.put(r.ticket, r);
            }
            System.assertEquals('Blocked', byTicket.get('CLAIMS-1').status, 'Checks failed blocks');
            System.assertEquals('In SIT approval', byTicket.get('CLAIMS-2').status, 'Waiting for approval');
            System.assertEquals('In PROD', byTicket.get('CLAIMS-3').status, 'Deployed to the hub');
            System.assertEquals('inprod', byTicket.get('CLAIMS-3').bucket, 'The filter');
            System.assertEquals('https://tracker.example.com/browse/CLAIMS-3', byTicket.get('CLAIMS-3').link, 'Link from the pattern');
            System.assertEquals('Jira', b.trackerLabel, 'Tracker named');
        }
    }

    @IsTest
    static void jiraGetsACommentAndTheMappedTransition() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-412' });
            settings('Jira', true);
            RlyHttpMock m = new RlyHttpMock()
                .match('POST', '/rest/api/2/issue/CLAIMS-412/comment').reply(201, '{"id":"1"}')
                .match('GET', '/rest/api/2/issue/CLAIMS-412/transitions').reply(200, '{"transitions":[{"id":"31","name":"In QA"}]}')
                .match('POST', '/rest/api/2/issue/CLAIMS-412/transitions').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyWorkTypes.ReleaseTickets t = RlyWorkItemsController.syncRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(RlyWorkSync.POSTED, t.tickets[0].status, 'Posted: ' + t.tickets[0].message);
            System.assert(m.bodyFor('/comment').contains('Deployed to SIT'), 'The moment in the comment');
            System.assert(m.bodyFor('/transitions').contains('"31"'), 'The mapped transition');
            System.assert(m.calls[0].contains('callout:Tracker_NC'), 'Through the Named Credential: ' + m.calls[0]);
        }
    }

    @IsTest
    static void azureServiceNowAndWebCallsArePosted() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Checks failed', 'SIT', new List<String>{ 'AB-1234' });
            RLY_Work_Tracking__c s = settings('Azure_Boards', true);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('PATCH', '/_apis/wit/workitems/1234').reply(200, '{"id":1234}')
                .match('GET', '/api/now/table/change_request').reply(200, '{"result":[{"sys_id":"abc"}]}')
                .match('PATCH', '/api/now/table/change_request/abc').reply(200, '{}')
                .match('POST', 'callout:Tracker_NC').reply(202, ''));
            Test.startTest();
            RlyWorkTypes.Outcome azure = RlyWorkTracker.post(s, msg('AB-1234', 'Checks failed in SIT', new Map<String, Object>()));
            s.Tracker__c = 'ServiceNow';
            RlyWorkTypes.Outcome now = RlyWorkTracker.post(s, msg('CHG0012345', 'Deployed to SIT', new Map<String, Object>()));
            s.Tracker__c = 'Other';
            RlyWorkTypes.Outcome other = RlyWorkTracker.post(s, msg('X-1', 'Raised', new Map<String, Object>{ 'release' => rel.Name }));
            s.Tracker__c = 'Azure_Boards';
            RlyWorkTypes.Outcome noNumber = RlyWorkTracker.post(s, msg('ABC', 'Raised', new Map<String, Object>()));
            Test.stopTest();
            System.assert(azure.ok, 'Azure Boards: ' + azure.message);
            System.assert(now.ok, 'ServiceNow: ' + now.message);
            System.assert(other.ok, 'Web call: ' + other.message);
            System.assert(!noNumber.ok, 'An Azure work item is a number');
        }
    }

    @IsTest
    static void aFailedPostIsKeptForTryAgain() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Deployed', 'SIT', new List<String>{ 'CLAIMS-9' });
            settings('Jira', true);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('POST', '/comment').reply(404, '{"errorMessages":["Issue does not exist"]}'));
            Test.startTest();
            RlyWorkTypes.ReleaseTickets t = RlyWorkItemsController.syncRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(RlyWorkSync.FAILED, t.tickets[0].status, 'Failed');
            System.assert(t.tickets[0].message.contains('404'), 'Why: ' + t.tickets[0].message);
            System.assertEquals(null, t.tickets[0].posted, 'Not marked posted: the next sync tries again');
        }
    }

    @IsTest
    static void productionWaitsForAnApprovedChange() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Ready for approval', 'PROD', new List<String>{ 'CHG0012345' });
            RLY_Work_Tracking__c s = settings('ServiceNow', false);
            s.Require_Change__c = true;
            update s;
            String pending = '{"result":[{"number":"CHG0012345","approval":"requested","state":"-3","start_date":"","end_date":""}]}';
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/api/now/table/change_request').reply(200, pending));
            RLY_Release__c full = RlyReleaseStore.release(rel.Id);
            Test.startTest();
            Boolean held = RlyWorkGate.holds(full);
            Test.stopTest();
            System.assert(held, 'Not approved: the deploy waits');
            System.assert(RlyWorkGate.isWaiting(full), 'Says why: ' + full.Error_Message__c);
            System.assert(full.Error_Message__c.contains('isn\'t approved'), 'The change\'s approval: ' + full.Error_Message__c);
        }
    }

    @IsTest
    static void anApprovedChangeLetsTheWaitingDeployGo() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Ready for approval', 'PROD', new List<String>{ 'CHG0012345' });
            update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved', Error_Message__c = RlyWorkGate.WAITING + ' CHG0012345 isn\'t approved yet.');
            RLY_Work_Tracking__c s = settings('ServiceNow', false);
            s.Require_Change__c = true;
            update s;
            String start = Datetime.now().addHours(-1).formatGmt('yyyy-MM-dd HH:mm:ss');
            String ends = Datetime.now().addHours(2).formatGmt('yyyy-MM-dd HH:mm:ss');
            RlyHttpMock m = new RlyHttpMock()
                .match('GET', '/api/now/table/change_request').reply(200, '{"result":[{"number":"CHG0012345","approval":"approved","state":"-1","start_date":"'
                    + start + '","end_date":"' + ends + '"}]}')
                .match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyWorkItemsController.syncRelease(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = [SELECT Status__c, Error_Message__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals('Deploying', saved.Status__c, 'The deploy starts once the change allows it');
            System.assertEquals(null, saved.Error_Message__c, 'No longer waiting');
            System.assert(m.bodyFor('/dispatches') != null, 'Merge dispatched');
        }
    }

    @IsTest
    static void aReleaseWithoutAChangeWaitsAndMomentsNameIt() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = make('Ready for approval', 'PROD', new List<String>{ 'CLAIMS-1' });
            RLY_Work_Tracking__c s = settings('ServiceNow', false);
            s.Require_Change__c = true;
            update s;
            RLY_Release__c full = RlyReleaseStore.release(rel.Id);
            Test.startTest();
            Boolean held = RlyWorkGate.holds(full);
            RLY_Release__c read = RlyWorkStore.release(rel.Id);
            read.Error_Message__c = full.Error_Message__c;
            String moment = RlyWorkSync.momentOf(read);
            read.Status__c = 'Rejected';
            String rejected = RlyWorkSync.momentOf(read);
            read.Status__c = 'Retrieving';
            String raised = RlyWorkSync.momentOf(read);
            read.Status__c = 'Deploying';
            String none = RlyWorkSync.momentOf(read);
            Test.stopTest();
            System.assert(held && full.Error_Message__c.contains('add the ServiceNow change'), 'No change: waits and says so');
            System.assertEquals('Waiting to deploy to PROD', moment, 'Waiting moment');
            System.assertEquals('Rejected', rejected, 'Rejected');
            System.assertEquals('Raised from DEV1', raised, 'Raised');
            System.assertEquals(null, none, 'Nothing new while deploying');
        }
    }

    @IsTest
    static void listsAndMessagesShowTicketLinks() {
        System.runAs(RlyTestData.admin()) {
            settings('Jira', false);
            Test.startTest();
            String csv = RlyWorkLinks.withLinks('CLAIMS-412, CLAIMS-418');
            String slack = RlyWorkLinks.slackLinks('CLAIMS-412');
            String none = RlyWorkLinks.withLinks(null);
            Test.stopTest();
            System.assertEquals('CLAIMS-412 (https://tracker.example.com/browse/CLAIMS-412), CLAIMS-418 (https://tracker.example.com/browse/CLAIMS-418)',
                csv, 'Each ticket with its link');
            System.assertEquals('<https://tracker.example.com/browse/CLAIMS-412|CLAIMS-412>', slack, 'A Slack link');
            System.assertEquals(null, none, 'No tickets');
        }
    }

    @IsTest
    static void changeWindowsAndMissingRecordsAreExplained() {
        System.runAs(RlyTestData.admin()) {
            RLY_Work_Tracking__c s = settings('ServiceNow', true);
            String later = Datetime.now().addHours(3).formatGmt('yyyy-MM-dd HH:mm:ss');
            String earlier = Datetime.now().addHours(-3).formatGmt('yyyy-MM-dd HH:mm:ss');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'number=CHG0000001').reply(200, '{"result":[{"approval":"approved","start_date":"' + later + '","end_date":""}]}')
                .match('GET', 'number=CHG0000002').reply(200, '{"result":[{"approval":"approved","start_date":"","end_date":"' + earlier + '"}]}')
                .match('GET', 'number=CHG0000003').reply(200, '{"result":[]}'));
            Test.startTest();
            RlyWorkTypes.Change notYet = RlyWorkTracker.change(s, 'CHG0000001');
            RlyWorkTypes.Change ended = RlyWorkTracker.change(s, 'CHG0000002');
            RlyWorkTypes.Change missing = RlyWorkTracker.change(s, 'CHG0000003');
            RlyWorkTypes.Outcome notFound = RlyWorkTracker.post(s, msg('CHG0000003', 'Raised', new Map<String, Object>()));
            Test.stopTest();
            System.assert(!notYet.allowed && notYet.message.contains('starts'), 'Window not started: ' + notYet.message);
            System.assert(!ended.allowed && ended.message.contains('ended'), 'Window ended: ' + ended.message);
            System.assert(!missing.allowed && missing.message.contains('wasn\'t found'), 'Not found: ' + missing.message);
            System.assert(!notFound.ok && notFound.message.contains('wasn\'t found'), 'Post to a missing record: ' + notFound.message);
        }
    }

    @IsTest
    static void jiraWithoutTheMappedTransitionKeepsTheComment() {
        System.runAs(RlyTestData.admin()) {
            RLY_Work_Tracking__c s = settings('Jira', true);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('POST', '/comment').reply(201, '{}')
                .match('GET', '/transitions').reply(200, '{"transitions":[{"id":"11","name":"Done"}]}'));
            Test.startTest();
            RlyWorkTypes.Outcome o = RlyWorkTracker.post(s, msg('CLAIMS-1', 'Deployed to SIT', new Map<String, Object>()));
            Test.stopTest();
            System.assert(o.ok, 'The comment went: ' + o.message);
            System.assert(o.message.contains('no transition'), 'Says the state wasn\'t set: ' + o.message);
        }
    }
}
