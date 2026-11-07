/**
 * @description Tests for data sets (Sync status tab, Data): checking a definition, saving and removing sets, starting a
 * run (a stage source dispatches the dry run; a developer org's records are sent in parts first), reading the result
 * (Ready, Blocked, Loaded, Failed), who may load, and Refill when an org's Org Id changed. GitHub and the orgs answer
 * through RlyHttpMock; the route is RlyReleaseTestData's DEV1 → SIT → PROD. Every test runs as an active System
 * Administrator.
 */
@IsTest
private class RlyDataTest {

    private static final String RUN_ID = 'DAT-1762400000001';
    private static final String TOKEN = 'tok123';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static Map<String, Object> obj(String name, List<String> fields, List<String> key) {
        return new Map<String, Object>{ 'objectName' => name, 'fields' => fields, 'matchKey' => key, 'filter' => '',
            'parents' => new Map<String, Object>(), 'masks' => new Map<String, Object>() };
    }

    private static String definition() {
        Map<String, Object> rule = obj('Claim_Rule__c', new List<String>{ 'Name', 'Claim_Type__c', 'Limit__c' }, new List<String>{ 'Claim_Type__c', 'Name' });
        rule.put('parents', new Map<String, Object>{ 'Claim_Type__c' => 'Claim_Type__c' });
        Map<String, Object> contact = obj('Contact', new List<String>{ 'LastName', 'Email', 'Ext_Id__c' }, new List<String>{ 'Ext_Id__c' });
        contact.put('masks', new Map<String, Object>{ 'Email' => 'email', 'LastName' => 'name' });
        Map<String, Object> claimType = obj('Claim_Type__c', new List<String>{ 'Name', 'Code__c' }, new List<String>{ 'Code__c' });
        claimType.put('filter', 'Active__c = true');
        return JSON.serialize(new Map<String, Object>{ 'objects' => new List<Object>{ claimType, rule, contact },
            'bypass' => new Map<String, Object>{ 'kind' => 'setting', 'name' => 'Claims_Settings__c', 'field' => 'Bypass_Triggers__c' } });
    }

    private static RLY_Data_Set__c dataSet() {
        RLY_Data_Set__c s = new RLY_Data_Set__c(Title__c = 'Claims config', Definition__c = definition());
        insert s;
        return s;
    }

    private static RLY_Data_Run__c run(RLY_Data_Set__c s, String direction, String status) {
        RLY_Data_Run__c r = new RLY_Data_Run__c(Run_Id__c = RUN_ID, Data_Set__c = s.Id, Direction__c = direction,
            Source_Org__c = orgId('PROD'), Target_Org__c = orgId('SIT'), Status__c = status, Token__c = TOKEN, Mask__c = true,
            Requested_By__c = UserInfo.getUserId(), Checked_At__c = System.now(), Run_Title__c = RlyDataRuns.runTitle(RUN_ID));
        insert r;
        return r;
    }

    private static String result(Boolean dryRun, Boolean blocked, String attempt) {
        return JSON.serialize(new Map<String, Object>{ 'request' => RUN_ID, 'step' => 'data', 'status' => blocked ? 'Failed' : 'Succeeded', 'dryRun' => dryRun,
            'blocked' => blocked, 'attempt' => attempt, 'runUrl' => 'https://github.com/acme/release/actions/runs/7',
            'message' => blocked ? 'Blocked: Claim_Type__c (1 keys match more than one record in SIT: auto). Nothing was loaded.' : '',
            'objects' => new List<Object>{
                new Map<String, Object>{ 'objectName' => 'Claim_Type__c', 'insert' => 1, 'update' => 0, 'unchanged' => 1, 'failed' => 0,
                    'duplicates' => blocked ? new List<Object>{ 'auto' } : new List<Object>(), 'missingKeys' => 0, 'triggers' => false, 'errors' => new List<Object>() },
                new Map<String, Object>{ 'objectName' => 'Claim_Rule__c', 'insert' => 2, 'update' => 1, 'unchanged' => 0, 'failed' => 0,
                    'duplicates' => new List<Object>(), 'missingKeys' => 0, 'triggers' => true, 'errors' => new List<Object>() } } });
    }

    private static Map<String, Object> dispatched(RlyHttpMock m) {
        return (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(m.bodyFor('/dispatches'))).get('inputs');
    }

    private static Map<String, Object> optionsOf(Map<String, Object> inputs) {
        return (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(inputs.get('options')));
    }

    private static String problem(String definitionJson) {
        try {
            RlyDataSet.parse(definitionJson);
            return null;
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
    }

    private static String withObjects(List<Object> objects, Map<String, Object> bypass) {
        return JSON.serialize(new Map<String, Object>{ 'objects' => objects, 'bypass' => bypass });
    }

    @IsTest
    static void definitionsAreChecked() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyDataSet.Definition d = RlyDataSet.parse(definition());
            List<String> problems = new List<String>{
                problem(''), problem('{not json'),
                problem(withObjects(new List<Object>{ obj('Claim_Type__c', new List<String>{ 'Name' }, new List<String>()) }, null)),
                problem(withObjects(new List<Object>{ obj('Claim_Type__c', new List<String>{ 'Name' }, new List<String>{ 'Code__c' }) }, null)),
                problem(withObjects(new List<Object>{ obj('Bad Name', new List<String>{ 'Name' }, new List<String>{ 'Name' }) }, null)),
                problem(withObjects(new List<Object>{ obj('Claim_Type__c', new List<String>{ 'Parent.Name' }, new List<String>{ 'Name' }) }, null)),
                problem(withObjects(new List<Object>{ obj('A__c', new List<String>{ 'Name' }, new List<String>{ 'Name' }),
                    obj('a__c', new List<String>{ 'Name' }, new List<String>{ 'Name' }) }, null)),
                problem(withObjects(new List<Object>{ obj('A__c', new List<String>{ 'Name' }, new List<String>{ 'Name' }) },
                    new Map<String, Object>{ 'kind' => 'trigger', 'name' => 'X__c' })),
                problem(withObjects(new List<Object>{ obj('A__c', new List<String>{ 'Name' }, new List<String>{ 'Name' }) },
                    new Map<String, Object>{ 'kind' => 'setting', 'name' => 'X__c' }))
            };
            Test.stopTest();
            System.assertEquals(3, d.objects.size(), 'Three objects');
            System.assertEquals('SELECT Id, Name, Code__c FROM Claim_Type__c WHERE Active__c = true', RlyDataSet.queryOf(d.objects[0]),
                'Id, the fields and the filter');
            System.assertEquals('Add at least one object to the data set.', problems[0], 'Empty');
            System.assertEquals('The data set\'s definition isn\'t valid JSON.', problems[1], 'Not JSON');
            System.assert(problems[2].contains('has no match key'), 'No match key, no object: ' + problems[2]);
            System.assert(problems[3].contains('must be one of its fields'), 'Key among the fields: ' + problems[3]);
            System.assert(problems[4].contains('API name'), 'Object name: ' + problems[4]);
            System.assert(problems[5].contains('isn\'t a field API name'), 'No paths: ' + problems[5]);
            System.assert(problems[6].contains('twice'), 'Once per object: ' + problems[6]);
            System.assert(problems[7].contains('trigger bypass needs a kind'), 'Bypass kind: ' + problems[7]);
            System.assert(problems[8].contains('checkbox field'), 'Setting field: ' + problems[8]);
        }
    }

    @IsTest
    static void filtersParentsAndMasksAreChecked() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            List<String> problems = new List<String>();
            Map<String, Object> badFilter = obj('A__c', new List<String>{ 'Name' }, new List<String>{ 'Name' });
            badFilter.put('filter', 'Name != null LIMIT 5');
            problems.add(problem(withObjects(new List<Object>{ badFilter }, null)));
            Map<String, Object> orphanParent = obj('B__c', new List<String>{ 'Name', 'A__c' }, new List<String>{ 'Name' });
            orphanParent.put('parents', new Map<String, Object>{ 'A__c' => 'A__c' });
            problems.add(problem(withObjects(new List<Object>{ orphanParent }, null)));
            Map<String, Object> keyMasked = obj('A__c', new List<String>{ 'Name', 'Email__c' }, new List<String>{ 'Email__c' });
            keyMasked.put('masks', new Map<String, Object>{ 'Email__c' => 'email' });
            problems.add(problem(withObjects(new List<Object>{ keyMasked }, null)));
            Map<String, Object> unknownMask = obj('A__c', new List<String>{ 'Name', 'Email__c' }, new List<String>{ 'Name' });
            unknownMask.put('masks', new Map<String, Object>{ 'Email__c' => 'scramble' });
            problems.add(problem(withObjects(new List<Object>{ unknownMask }, null)));
            Test.stopTest();
            System.assert(problems[0].contains('one condition'), 'Filter: ' + problems[0]);
            System.assert(problems[1].contains('earlier in the data set'), 'Parents first: ' + problems[1]);
            System.assert(problems[2].contains('can\'t be masked'), 'Key not masked: ' + problems[2]);
            System.assert(problems[3].contains('needs one of its fields and a rule'), 'Mask rule: ' + problems[3]);
        }
    }

    @IsTest
    static void adminsSaveAndRemoveSets() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.startTest();
            Id setId = RlyDataController.saveSet(JSON.serialize(new Map<String, Object>{ 'title' => '  Claims   config ',
                'description' => 'Claim types', 'definition' => definition() }));
            RlyDataController.saveSet(JSON.serialize(new Map<String, Object>{ 'id' => setId, 'title' => 'Claims setup', 'definition' => definition() }));
            String noTitle;
            try {
                RlyDataController.saveSet(JSON.serialize(new Map<String, Object>{ 'title' => '', 'definition' => definition() }));
            } catch (AuraHandledException e) {
                noTitle = e.getMessage();
            }
            RlyDataBoard.Board b = RlyDataController.board();
            RlyDataController.removeSet(setId);
            Test.stopTest();
            System.assertEquals('Claims setup', b.sets[0].title, 'Saved, then renamed');
            System.assertEquals(3, b.sets[0].objectCount, 'Its objects');
            System.assertEquals(true, b.isAdmin, 'Admin');
            System.assertEquals(true, b.isApprover, 'An admin approves too');
            System.assertEquals(3, b.orgs.size(), 'The route orgs');
            System.assert(noTitle.contains('title'), 'A title is needed: ' + noTitle);
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Data_Set__c], 'Removed');
        }
    }

    @IsTest
    static void aStageSourceStartsTheDryRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Data_Set__c s = dataSet();
            RlyHttpMock m = new RlyHttpMock().match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            RlyDataRuns.Request req = new RlyDataRuns.Request();
            req.dataSetId = s.Id;
            req.sourceOrgId = orgId('PROD');
            req.targetOrgId = orgId('SIT');
            req.direction = RlyDataRuns.DOWN;
            Test.startTest();
            RlyDataRuns.Started st = RlyDataController.startRun(JSON.serialize(req));
            Test.stopTest();
            System.assertEquals('dryRun', st.next, 'The pipeline exports and dry-runs');
            Map<String, Object> inputs = dispatched(m);
            Map<String, Object> options = optionsOf(inputs);
            System.assertEquals('data', inputs.get('mode'), 'Mode data');
            System.assertEquals(st.runId, inputs.get('request_id'), 'Under the run id');
            System.assertEquals('prod', inputs.get('environment'), 'Read through the source\'s environment');
            System.assertEquals('sit', inputs.get('target_environment'), 'Loaded through the target\'s');
            System.assertEquals(true, options.get('dryRun'), 'A dry run first');
            System.assertEquals(true, options.get('mask'), 'Copy down masks by default');
            System.assertEquals('prod', options.get('sourceValuesEnv'), 'Per-org values from the source');
            RLY_Data_Run__c saved = [SELECT Status__c, Token__c, Run_Title__c, Direction__c FROM RLY_Data_Run__c WHERE Run_Id__c = :st.runId];
            System.assertEquals('Dry run', saved.Status__c, 'Dry run');
            System.assertEquals(saved.Token__c, options.get('attempt'), 'The result echoes the token');
            System.assertEquals('Release Relay ' + st.runId + ' (data)', saved.Run_Title__c, 'Run title kept');
        }
    }

    @IsTest
    static void aDeveloperOrgIsSentInPartsThenDryRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RLY_Data_Set__c s = dataSet();
            RlyHttpMock m = new RlyHttpMock()
                .match('GET', '/query/01g').reply(200, '{"done":true,"records":[{"attributes":{"type":"Claim_Type__c"},"Id":"a01","Code__c":"HOME"}]}')
                .match('GET', '/query/?q=').reply(200, '{"done":false,"nextRecordsUrl":"/services/data/v65.0/query/01gXX-2000",'
                    + '"records":[{"attributes":{"type":"Claim_Type__c"},"Id":"a00","Code__c":"AUTO"}]}')
                .match('PUT', '/contents/data-inbox/').reply(201, '{"commit":{"html_url":"https://github.com/acme/release/commit/1"}}')
                .match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            RlyDataRuns.Request req = new RlyDataRuns.Request();
            req.dataSetId = s.Id;
            req.sourceOrgId = orgId('DEV1');
            req.targetOrgId = orgId('SIT');
            req.direction = RlyDataRuns.UP;
            // Saving the run is DML: the page's later calls (callouts) come in their own requests.
            RlyDataRuns.Started st = RlyDataController.startRun(JSON.serialize(req));
            Test.startTest();
            RlyDataExport.Part first = RlyDataController.exportPart(JSON.serialize(new Map<String, Object>{ 'runId' => st.runId, 'index' => 0, 'page' => 1 }));
            RlyDataExport.Part second = RlyDataController.exportPart(JSON.serialize(new Map<String, Object>{ 'runId' => st.runId, 'index' => 0,
                'page' => 2, 'cursor' => first.nextCursor }));
            String title = RlyDataController.runExported(st.runId);
            Test.stopTest();
            System.assertEquals('export', st.next, 'A developer org is sent by the hub');
            System.assertEquals(3, st.queries.size(), 'One query per object');
            System.assertEquals(1, first.count, 'First page');
            System.assertEquals('/services/data/v65.0/query/01gXX-2000', first.nextCursor, 'More to come');
            System.assertEquals(null, second.nextCursor, 'Done');
            String put = m.bodyFor('/contents/data-inbox/' + st.runId + '/00-001.json');
            System.assert(put != null, 'Saved as the export job would: ' + m.callLog());
            String saved = EncodingUtil.base64Decode((String) ((Map<String, Object>) JSON.deserializeUntyped(put)).get('content')).toString();
            System.assert(saved.contains('"AUTO"') && !saved.contains('attributes'), 'The records without attributes: ' + saved);
            Map<String, Object> inputs = dispatched(m);
            System.assertEquals('', inputs.get('environment'), 'No export job: the records are there');
            System.assertEquals(true, optionsOf(inputs).get('sourceInbox'), 'From the inbox');
            System.assertEquals(false, optionsOf(inputs).get('mask'), 'Send up doesn\'t mask unless asked');
            System.assertEquals(RlyDataRuns.runTitle(st.runId), title, 'Run title');
            System.assertEquals('Dry run', [SELECT Status__c FROM RLY_Data_Run__c WHERE Run_Id__c = :st.runId].Status__c, 'Dry run');
        }
    }

    @IsTest
    static void startsAreChecked() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Data_Set__c s = dataSet();
            List<String> messages = new List<String>();
            List<List<Object>> cases = new List<List<Object>>{
                new List<Object>{ orgId('SIT'), orgId('SIT'), RlyDataRuns.DOWN, null },
                new List<Object>{ orgId('PROD'), orgId('SIT'), 'Sideways', null },
                new List<Object>{ orgId('SIT'), orgId('DEV1'), RlyDataRuns.DOWN, null },
                new List<Object>{ orgId('PROD'), orgId('SIT'), RlyDataRuns.DOWN, 'REL-99999' }
            };
            Test.startTest();
            for (List<Object> c : cases) {
                RlyDataRuns.Request req = new RlyDataRuns.Request();
                req.dataSetId = s.Id;
                req.sourceOrgId = (Id) c[0];
                req.targetOrgId = (Id) c[1];
                req.direction = (String) c[2];
                req.releaseName = (String) c[3];
                try {
                    RlyDataController.startRun(JSON.serialize(req));
                    messages.add('started');
                } catch (AuraHandledException e) {
                    messages.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assert(messages[0].contains('different target'), 'Two orgs: ' + messages[0]);
            System.assert(messages[1].contains('Send up or Copy down'), 'Direction: ' + messages[1]);
            System.assert(messages[2].contains('no sign-in in GitHub'), 'The pipeline loads stages and the hub: ' + messages[2]);
            System.assert(messages[3].contains('no release REL-99999'), 'Linked release: ' + messages[3]);
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Data_Run__c], 'Nothing started');
        }
    }

    @IsTest
    static void aPassedDryRunIsReady() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.DRY_RUN);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + RUN_ID + '/data.json').reply(200, result(true, false, TOKEN)));
            Test.startTest();
            RlyDataResult.View v = RlyDataController.readRun(RUN_ID);
            RlyDataResult.View again = RlyDataController.readRun(RUN_ID);
            Test.stopTest();
            System.assertEquals('Ready', v.status, 'Ready to load');
            System.assertEquals(3, v.counts.get('insert'), 'Totals');
            System.assertEquals(true, v.objects[1].triggers, 'Triggers that fire are flagged');
            System.assertEquals(true, again.done, 'Read from the saved summary');
            System.assertEquals(2, again.objects.size(), 'Per object, kept');
            RLY_Data_Run__c saved = [SELECT Status__c, Counts__c, Run_Url__c FROM RLY_Data_Run__c WHERE Run_Id__c = :RUN_ID];
            System.assertEquals('Ready', saved.Status__c, 'Saved');
            System.assert(saved.Counts__c.contains('"insert":3'), 'Counts saved: ' + saved.Counts__c);
        }
    }

    @IsTest
    static void duplicatesBlockTheRun() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.DRY_RUN);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + RUN_ID + '/data.json').reply(200, result(true, true, TOKEN)));
            Test.startTest();
            RlyDataResult.View v = RlyDataController.readRun(RUN_ID);
            String refused;
            try {
                RlyDataController.loadRun(RUN_ID);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('Blocked', v.status, 'Blocked');
            System.assertEquals('auto', v.objects[0].duplicates[0], 'The key that matches twice');
            System.assert(refused.contains('Blocked'), 'A blocked run isn\'t loaded: ' + refused);
        }
    }

    @IsTest
    static void aLoadIsLoadedAndAnEndedRunWithoutResultFails() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.LOADING);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + RUN_ID + '/data.json').reply(200, result(false, false, 'older'))
                .match('GET', '/runs?event=workflow_dispatch').reply(200, '{"workflow_runs":[{"id":7,"display_title":"Release Relay '
                    + RUN_ID + ' (data)","html_url":"https://x/7","status":"completed","conclusion":"failure"}]}'));
            Test.startTest();
            RlyDataResult.View failed = RlyDataController.readRun(RUN_ID);
            Test.stopTest();
            System.assertEquals('Failed', failed.status, 'An older result isn\'t this run\'s');
            System.assertEquals('https://x/7', failed.runUrl, 'Linked to the run');
            RLY_Data_Run__c saved = [SELECT Status__c, Message__c FROM RLY_Data_Run__c WHERE Run_Id__c = :RUN_ID];
            System.assertEquals('Failed', saved.Status__c, 'Saved as failed');
            System.assert(saved.Message__c.contains('without writing its result'), 'Why: ' + saved.Message__c);
        }
    }

    @IsTest
    static void aLoadResultIsLoaded() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.LOADING);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + RUN_ID + '/data.json').reply(200, result(false, false, TOKEN)));
            Test.startTest();
            RlyDataResult.View v = RlyDataController.readRun(RUN_ID);
            Test.stopTest();
            System.assertEquals('Loaded', v.status, 'Loaded');
            System.assertEquals(false, v.dryRun, 'The load\'s counts');
        }
    }

    @IsTest
    static void sentUpDataIsLoadedBySomeoneElse() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            User other = RlyTestData.plainUser();
            RLY_Data_Set__c s = dataSet();
            run(s, RlyDataRuns.UP, RlyDataStore.READY);
            RlyHttpMock m = new RlyHttpMock().match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, m);
            String ownRun;
            try {
                RlyDataController.loadRun(RUN_ID);
            } catch (AuraHandledException e) {
                ownRun = e.getMessage();
            }
            update new RLY_Data_Run__c(Id = [SELECT Id FROM RLY_Data_Run__c WHERE Run_Id__c = :RUN_ID].Id, Requested_By__c = other.Id);
            Test.startTest();
            String title = RlyDataController.loadRun(RUN_ID);
            Test.stopTest();
            System.assert(ownRun.contains('Someone else approves'), 'Not your own run: ' + ownRun);
            System.assertEquals(RlyDataRuns.runTitle(RUN_ID), title, 'Run title');
            Map<String, Object> inputs = dispatched(m);
            System.assertEquals(false, optionsOf(inputs).get('dryRun'), 'The load');
            System.assertEquals('', inputs.get('environment'), 'From the dry run\'s records');
            RLY_Data_Run__c saved = [SELECT Status__c, Token__c, Approved_By__c FROM RLY_Data_Run__c WHERE Run_Id__c = :RUN_ID];
            System.assertEquals('Loading', saved.Status__c, 'Loading');
            System.assertNotEquals(TOKEN, saved.Token__c, 'A new token for the load\'s result');
            System.assertEquals(UserInfo.getUserId(), saved.Approved_By__c, 'Who allowed it');
        }
    }

    @IsTest
    static void copyDownIsForAdmins() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            User other = RlyTestData.plainUser();
            run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.READY);
            String refused;
            Test.startTest();
            System.runAs(other) {
                try {
                    RlyDataRules.requireLoader(RlyDataStore.run(RUN_ID));
                } catch (RlyReleaseException e) {
                    refused = e.getMessage();
                }
            }
            Test.stopTest();
            System.assert(refused.contains('admins'), 'Admins load data copied down: ' + refused);
        }
    }

    @IsTest
    static void aRefreshedOrgIsDueARefill() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            update new RLY_Org__c(Id = orgId('SIT'), Org_Id__c = RlyTestData.fakeId('00D', 2));
            RLY_Data_Run__c r = run(dataSet(), RlyDataRuns.DOWN, RlyDataStore.LOADED);
            r.Target_Org_Id__c = RlyTestData.fakeId('00D', 1);
            r.Summary__c = result(false, false, TOKEN);
            update r;
            Test.startTest();
            RlyDataBoard.Board b = RlyDataController.board();
            RlyDataResult.View v = RlyDataController.readRun(RUN_ID);
            Integer removed = RlyDataStore.removeOlderThan(System.now().addDays(1), 100);
            Test.stopTest();
            RlyDataBoard.OrgRow sit;
            for (RlyDataBoard.OrgRow o : b.orgs) {
                sit = o.name == 'SIT' ? o : sit;
            }
            System.assertEquals(true, sit.refillDue, 'Its Org Id changed since the last load');
            System.assertEquals(RUN_ID, sit.lastRunId, 'Refill repeats that load');
            System.assertEquals('Claims config', b.runs[0].setTitle, 'Runs listed');
            System.assertEquals(false, v.dryRun, 'A finished run reads its summary');
            System.assertEquals(1, removed, 'Old runs are removed');
        }
    }

    @IsTest
    static void exportHelpersAreStrict() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            List<Object> records = RlyDataExport.withoutAttributes(JSON.deserializeUntyped('[{"attributes":{"type":"A"},"Id":"1"},"x"]'));
            String bad;
            try {
                RlyDataExport.checkedCursor('https://evil.example.com/services/data/v65.0/query/01g');
            } catch (RlyReleaseException e) {
                bad = e.getMessage();
            }
            String missing;
            try {
                RlyDataController.readRun('DAT-0000000000000');
            } catch (AuraHandledException e) {
                missing = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(1, records.size(), 'Records only');
            System.assertEquals(false, ((Map<String, Object>) records[0]).containsKey('attributes'), 'Without attributes');
            System.assert(bad.contains('isn\'t valid'), 'Only the org\'s own cursors: ' + bad);
            System.assert(missing.contains('isn\'t there'), 'Unknown run: ' + missing);
        }
    }
}
