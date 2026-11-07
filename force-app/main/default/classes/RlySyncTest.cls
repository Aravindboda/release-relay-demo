/**
 * @description Tests for the Sync status tab's Apex (RlySyncController and RlySync*): the route from the top down, starting
 * org and route checks (dispatch inputs), reading drift.json / route.json from the results branch, files, installed
 * packages and what uses one, and back promote / push of picked components. GitHub and the orgs answer through
 * RlyHttpMock; the route is RlyReleaseTestData's DEV1 → SIT → PROD. Every test runs as an active System Administrator.
 */
@IsTest
private class RlySyncTest {

    private static final String SYNC_ID = 'SYN-1762400000001';
    private static final String TOKEN = 'tok123';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RlyHttpMock dispatchMock() {
        return new RlyHttpMock().match('POST', '/dispatches').reply(204, '');
    }

    private static Map<String, Object> dispatched(RlyHttpMock m) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(m.bodyFor('/dispatches'));
        return (Map<String, Object>) body.get('inputs');
    }

    private static Map<String, Object> optionsOf(Map<String, Object> inputs) {
        return (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(inputs.get('options')));
    }

    private static void runningCheck(String kind, Id org, String runTitle) {
        insert new RLY_Sync_Check__c(Sync_Id__c = SYNC_ID, Kind__c = kind, Org__c = org, Branch__c = 'sit', Token__c = TOKEN,
            Status__c = 'Running', Checked_At__c = System.now(), Run_Title__c = runTitle);
    }

    private static String driftJson(String attempt) {
        return JSON.serialize(new Map<String, Object>{ 'request' => SYNC_ID, 'step' => 'drift', 'status' => 'Succeeded', 'attempt' => attempt,
            'runUrl' => 'https://github.com/acme/release/actions/runs/9',
            'counts' => new Map<String, Object>{ 'onlyInOrg' => 1, 'onlyOnBranch' => 1, 'different' => 1, 'same' => 40 },
            'components' => new List<Object>{
                new Map<String, Object>{ 'key' => 'CustomField:Case.Reason__c', 'type' => 'CustomField', 'status' => 'onlyInOrg',
                    'lastChangedBy' => 'J. Patel', 'files' => new List<Object>{ new Map<String, Object>{ 'path' => 'force-app/main/default/objects/Case/fields/Reason__c.field-meta.xml', 'status' => 'new', 'n' => 1, 'kind' => 'text' } } },
                new Map<String, Object>{ 'key' => 'ApexClass:LegacyMapper', 'type' => 'ApexClass', 'status' => 'onlyOnBranch', 'files' => new List<Object>() },
                new Map<String, Object>{ 'key' => 'ApexClass:InvoiceTotals', 'type' => 'ApexClass', 'status' => 'different', 'files' => new List<Object>{
                    new Map<String, Object>{ 'path' => 'force-app/main/default/classes/InvoiceTotals.cls', 'status' => 'changed', 'reason' => 'Binary file: open it in GitHub.' } } }
            } });
    }

    @IsTest
    static void boardShowsTheRouteFromTheTopDown() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.startTest();
            RlySyncBoard.Board b = RlySyncController.board();
            Test.stopTest();
            System.assertEquals(3, b.orgs.size(), 'Every route org');
            System.assertEquals('PROD', b.orgs[0].name, 'The hub first');
            System.assertEquals('DEV1', b.orgs[2].name, 'Developer orgs last');
            System.assertEquals(true, b.orgs[1].signIn, 'The pipeline signs in to a stage');
            System.assertEquals(false, b.orgs[2].signIn, 'Not to a developer org');
            System.assertEquals(2, b.pairs.size(), 'PROD over SIT, SIT over DEV1');
            System.assertEquals('sit', b.pairs[0].lowerBranch, 'Top pair first');
            System.assertEquals(false, b.pairs[1].lowerSignIn, 'DEV1 gets its branch only');
            System.assertEquals(null, b.route, 'No route check yet');
        }
    }

    @IsTest
    static void aStageIsCheckedByThePipeline() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHttpMock m = dispatchMock();
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlySyncRuns.Started s = RlySyncController.startOrgCheck(orgId('SIT'));
            Test.stopTest();
            System.assertEquals('drift', s.mode, 'Mode drift');
            Map<String, Object> inputs = dispatched(m);
            System.assertEquals('drift', inputs.get('mode'), 'Dispatched as drift');
            System.assertEquals('sit', inputs.get('target'), 'Against its own branch');
            System.assertEquals('sit', inputs.get('environment'), 'Signed in through its environment');
            RLY_Sync_Check__c check = [SELECT Status__c, Token__c, Run_Title__c, Kind__c FROM RLY_Sync_Check__c WHERE Sync_Id__c = :s.syncId];
            System.assertEquals('Running', check.Status__c, 'Running');
            System.assertEquals(check.Token__c, optionsOf(inputs).get('attempt'), 'The result will echo the token');
            System.assertEquals('Release Relay ' + s.syncId + ' (drift)', check.Run_Title__c, 'Run title kept to find the run');
        }
    }

    @IsTest
    static void aDeveloperOrgIsSentInPartsThenCompared() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock m = dispatchMock();
            Test.setMock(HttpCalloutMock.class, m);
            // Saving the check is DML; in a test the later callout must come after Test.startTest (the page makes
            // these two calls in separate requests).
            RlySyncRuns.Started s = RlySyncController.startOrgCheck(orgId('DEV1'));
            Boolean noDispatchYet = m.bodyFor('/dispatches') == null;
            Test.startTest();
            String title = RlySyncController.runDeveloperCheck(s.syncId, 2, new List<String>{ 'ApexClass', 'CustomObject' });
            Test.stopTest();
            System.assertEquals('parts', s.mode, 'The page sends a developer org');
            System.assert(noDispatchYet, 'Nothing runs before the parts are sent');
            Map<String, Object> inputs = dispatched(m);
            Map<String, Object> options = optionsOf(inputs);
            System.assertEquals('compare', inputs.get('mode'), 'Mode compare');
            System.assertEquals(s.syncId, inputs.get('request_id'), 'Under the check\'s id');
            System.assertEquals('dev1', inputs.get('target'), 'Against the org\'s own branch');
            System.assertEquals(true, options.get('full'), 'The whole org');
            Map<String, Object> folders = (Map<String, Object>) options.get('folders');
            System.assertEquals('ApexClass', folders.get('classes'), 'The listed types\' folders');
            System.assertEquals('CustomObject', folders.get('objects'), 'Objects when listed');
            System.assertEquals('Release Relay ' + s.syncId + ' (compare)', title, 'Run title');
        }
    }

    @IsTest
    static void theResultOfThisRunIsRead() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            runningCheck('Org', orgId('SIT'), 'Release Relay ' + SYNC_ID + ' (drift)');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'results/' + SYNC_ID + '/drift.json').reply(200, driftJson(TOKEN)));
            Test.startTest();
            RlySyncResult.View v = RlySyncController.readCheck(SYNC_ID);
            Test.stopTest();
            System.assertEquals(true, v.done, 'Read');
            System.assertEquals('Succeeded', v.status, 'Succeeded');
            System.assertEquals(3, v.components.size(), 'The differences');
            System.assertEquals('Case.Reason__c', v.components[0].name, 'Name from the key');
            System.assertEquals(1, v.components[0].files[0].n, 'File number to open it');
            System.assertEquals(1, v.counts.get('onlyInOrg'), 'Counts');
            RLY_Sync_Check__c saved = [SELECT Status__c, Counts__c, Run_Url__c FROM RLY_Sync_Check__c WHERE Sync_Id__c = :SYNC_ID];
            System.assertEquals('Succeeded', saved.Status__c, 'The check is saved as done');
            System.assert(saved.Counts__c.contains('"different":1'), 'With its counts for the card');
        }
    }

    @IsTest
    static void anOlderRunIsIgnoredAndARunWithoutResultFails() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            runningCheck('Org', orgId('SIT'), 'Release Relay ' + SYNC_ID + ' (drift)');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + SYNC_ID + '/drift.json').reply(200, driftJson('older'))
                .match('GET', '/runs?event=workflow_dispatch').reply(200, '{"workflow_runs":[{"id":9,"display_title":"Release Relay '
                    + SYNC_ID + ' (drift)","html_url":"https://x/9","status":"completed","conclusion":"failure"}]}'));
            Test.startTest();
            RlySyncResult.View v = RlySyncController.readCheck(SYNC_ID);
            Test.stopTest();
            System.assertEquals('Failed', v.status, 'The run ended without this check\'s result');
            System.assertEquals('https://x/9', v.runUrl, 'Linked to the run');
            System.assertEquals('Failed', [SELECT Status__c FROM RLY_Sync_Check__c WHERE Sync_Id__c = :SYNC_ID].Status__c, 'Saved as failed');
        }
    }

    @IsTest
    static void theRouteIsCheckedPairByPair() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHttpMock m = dispatchMock();
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlySyncRuns.Started s = RlySyncController.startRouteCheck();
            Test.stopTest();
            Map<String, Object> inputs = dispatched(m);
            Map<String, Object> options = optionsOf(inputs);
            System.assertEquals('routediff', inputs.get('mode'), 'Mode routediff');
            System.assertEquals(new List<Object>{ 'prod', 'sit', 'dev1' }, options.get('route'), 'From the top down');
            System.assertEquals(2, ((List<Object>) options.get('pairs')).size(), 'Each pair');
            System.assertEquals('routediff', s.mode, 'Started');
        }
    }

    @IsTest
    static void routeResultsAndFilesAreRead() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            runningCheck('Route', null, 'Release Relay ' + SYNC_ID + ' (routediff)');
            String route = JSON.serialize(new Map<String, Object>{ 'status' => 'Succeeded', 'attempt' => TOKEN, 'pairs' => new List<Object>{
                new Map<String, Object>{ 'higher' => 'prod', 'lower' => 'sit', 'count' => 1, 'components' => new List<Object>{
                    new Map<String, Object>{ 'key' => 'ApexClass:InvoiceDueDate', 'status' => 'onlyInHigher', 'lowerChangedToo' => true,
                        'cameFrom' => 'REL-00036', 'files' => new List<Object>{ new Map<String, Object>{ 'path' => 'force-app/main/default/classes/InvoiceDueDate.cls', 'status' => 'changed', 'n' => 1 } } } } } } });
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', 'results/' + SYNC_ID + '/route.json').reply(200, route)
                .match('GET', 'results/' + SYNC_ID + '/f/1.json').reply(200, '{"path":"force-app/main/default/classes/InvoiceDueDate.cls","left":"a","right":"b"}')
                .match('GET', 'results/' + SYNC_ID + '/f/2.json').reply(200, '{"path":"x","patch":"@@ -1 +1 @@"}'));
            Test.startTest();
            // The files first: reading the result saves the check (DML), and no callout may follow it in one request.
            RlyCompareFiles.FileDiff text = RlySyncController.syncFile(SYNC_ID, 1);
            RlyCompareFiles.FileDiff patch = RlySyncController.syncFile(SYNC_ID, 2);
            RlySyncResult.View v = RlySyncController.readCheck(SYNC_ID);
            Test.stopTest();
            System.assertEquals(1, v.pairs.size(), 'The pair');
            System.assertEquals(true, v.pairs[0].components[0].lowerChangedToo, 'Changed below too');
            System.assertEquals('REL-00036', v.pairs[0].components[0].cameFrom, 'Where it came from');
            System.assertEquals('changed', text.status, 'Both copies compared');
            System.assertEquals('changed', patch.status, 'A diff means changed');
        }
    }

    @IsTest
    static void badIdsAreRefused() {
        System.runAs(RlyTestData.admin()) {
            String error;
            Test.startTest();
            try {
                RlySyncController.readCheck('SYN-12');
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assert(error != null && error.contains('SYN-'), 'Ids are checked: ' + error);
        }
    }

    @IsTest
    static void packagesAreReadPerOrgAndSaved() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'InstalledSubscriberPackage').reply(200,
                '{"done":true,"records":[{"SubscriberPackage":{"Name":"Health Cloud","NamespacePrefix":"HealthCloudGA"},'
                + '"SubscriberPackageVersion":{"MajorVersion":252,"MinorVersion":4,"PatchVersion":0}}]}'));
            Test.startTest();
            RlySyncPackages.Packages p = RlySyncController.readPackages();
            RlySyncBoard.Board b = RlySyncController.board();
            Test.stopTest();
            System.assertEquals(3, p.orgs.size(), 'Every route org read');
            System.assertEquals(1, p.packages.size(), 'One package');
            System.assertEquals('252.4', p.packages[0].versions.get('SIT'), 'Version per org');
            System.assertEquals('HealthCloudGA', b.packages.packages[0].namespace, 'The board shows the saved packages');
        }
    }

    @IsTest
    static void whatUsesAPackageIsListed() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'MetadataComponentDependency').reply(200,
                '{"done":true,"records":[{"MetadataComponentName":"Send_Survey","MetadataComponentType":"Flow","MetadataComponentNamespace":null,'
                + '"RefMetadataComponentName":"SendInvite","RefMetadataComponentType":"ApexClass"},'
                + '{"MetadataComponentName":"Send_Survey","MetadataComponentType":"Flow","MetadataComponentNamespace":null,'
                + '"RefMetadataComponentName":"Survey__c","RefMetadataComponentType":"CustomObject"},'
                + '{"MetadataComponentName":"Inner","MetadataComponentType":"ApexClass","MetadataComponentNamespace":"osk",'
                + '"RefMetadataComponentName":"X","RefMetadataComponentType":"ApexClass"}]}'));
            Test.startTest();
            RlySyncPackages.Usage u = RlySyncController.packageUsage(null, 'osk');
            String error;
            try {
                RlySyncController.packageUsage(null, 'bad ns');
            } catch (AuraHandledException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('SIT', u.org, 'Read in the first stage');
            System.assertEquals(1, u.uses.size(), 'Own components once; the package\'s own left out');
            System.assertEquals('Flow:Send_Survey', u.uses[0].key, 'Type:Name');
            System.assert(error != null && error.contains('namespace'), 'Namespaces are checked: ' + error);
        }
    }

    @IsTest
    static void pickedComponentsAreBackPromotedOrPushed() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Map<String, Object> pick = new Map<String, Object>{ 'higherOrgId' => orgId('PROD'), 'lowerOrgId' => orgId('SIT'),
                'keys' => new List<String>{ 'ApexClass:InvoiceDueDate' }, 'paths' => new List<String>{ 'force-app/main/default/classes/InvoiceDueDate.cls' } };
            Test.startTest();
            Id backId = RlySyncController.backPromotePicked(JSON.serialize(pick));
            pick.put('higherOrgId', orgId('SIT'));
            pick.put('lowerOrgId', orgId('DEV1'));
            Id devId = RlySyncController.backPromotePicked(JSON.serialize(pick));
            String refused;
            try {
                pick.put('higherOrgId', orgId('DEV1'));
                RlySyncController.pushToOrg(JSON.serialize(pick));
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            RLY_Release__c back = [SELECT Release_Type__c, Source_Branch__c, Target_Branch__c, Sync_Paths__c, Component_Count__c, Target_Environment__c
                                   FROM RLY_Release__c WHERE Id = :backId];
            System.assertEquals('Back_Promote', back.Release_Type__c, 'A back promote release');
            System.assertEquals('prod', back.Source_Branch__c, 'From the higher branch');
            System.assertEquals('sit', back.Target_Branch__c, 'To the lower one');
            System.assert(back.Sync_Paths__c.contains('InvoiceDueDate.cls'), 'Just the picked files');
            System.assertEquals(1, back.Component_Count__c, 'Its components');
            Map<String, Object> options = RlyPipelineOptions.forMode(RlyReleaseStore.release(backId), 'sync');
            System.assertEquals(1, ((List<Object>) options.get('paths')).size(), 'The pipeline gets the paths');
            RLY_Release__c dev = [SELECT Sync_Paths__c, Target_Environment__c FROM RLY_Release__c WHERE Id = :devId];
            System.assert(dev.Sync_Paths__c.contains('"branchOnly":true'), 'A developer org gets its branch only');
            System.assertEquals(null, dev.Target_Environment__c, 'Nothing to deploy to');
            System.assert(refused != null && refused.contains('developer org'), 'No push to a developer org: ' + refused);
        }
    }

    @IsTest
    static void backPromoteKeepsToTheRouteAndOneAtATime() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            List<String> errors = new List<String>();
            Test.startTest();
            Id everything = RlySyncController.backPromoteAll(orgId('PROD'), orgId('SIT'));
            for (List<Id> ids : new List<List<Id>>{ new List<Id>{ orgId('PROD'), orgId('SIT') }, new List<Id>{ orgId('PROD'), orgId('DEV1') } }) {
                try {
                    RlySyncController.backPromoteAll(ids[0], ids[1]);
                    errors.add('none');
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assertEquals(null, [SELECT Sync_Paths__c FROM RLY_Release__c WHERE Id = :everything].Sync_Paths__c, 'Everything: no picks');
            System.assert(errors[0].contains('already waiting'), 'One back promote per org at a time: ' + errors[0]);
            System.assert(errors[1].contains('isn\'t the org below'), 'Only down the route: ' + errors[1]);
        }
    }
}
