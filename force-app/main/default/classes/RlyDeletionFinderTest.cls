/**
 * @description Tests for deletions (RlyDeletions, RlyDeletionFinder, RlyChangesController.findDeletions, RlyGit.listFiles,
 * and the deletion parts of RlyRaiseService, RlyRaiseRules, RlyStatusReader, RlyPipelineRun, RlyPipelineOptions,
 * RlyPromotion, RlyCarried, RlyReleaseLinks, RlyReleasesController, RlyPromoteController and RlySlackCardText).
 * Route DEV1 -> SIT -> PROD (hub). Every test runs through System.runAs as an active System Administrator (with
 * Release Relay Admin). Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyDeletionFinderTest {

    private static final String RECENT = '2026-10-30T10:00:00.000Z';
    private static final String SRC = 'force-app/main/default/';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static String tree(List<String> paths) {
        List<Object> rows = new List<Object>{ new Map<String, Object>{ 'path' => SRC + 'classes', 'type' => 'tree' } };
        for (String p : paths) {
            rows.add(new Map<String, Object>{ 'path' => p, 'type' => 'blob' });
        }
        return JSON.serialize(new Map<String, Object>{ 'sha' => 'abc', 'tree' => rows, 'truncated' => false });
    }

    private static RlyRaiseService.RaiseRequest deletionRequest(Id sourceOrgId) {
        RlyRaiseService.RaiseRequest r = new RlyRaiseService.RaiseRequest();
        r.sourceOrgId = sourceOrgId;
        r.title = 'Remove old helpers';
        r.items = new List<RlyRaiseService.Item>();
        r.deletions = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexClass', 'OldHelper'),
            RlyReleaseTestData.item('ApexTrigger', 'OldTrigger') };
        r.testClasses = new List<String>();
        return r;
    }

    private static String refusal(RlyRaiseService.RaiseRequest req) {
        try {
            RlyRaiseService.raise(req);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return null;
    }

    private static RLY_Release__c saved(Id relId) {
        return [SELECT Status__c, Retrieve_Id__c, Deletions__c, Deletion_Count__c, Component_Count__c, Error_Message__c, Pending_Run__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    private static List<RLY_Release_Item__c> itemsOf(Id relId) {
        return [SELECT Metadata_Type__c, Component_Name__c, Is_Deletion__c FROM RLY_Release_Item__c
                WHERE Release__c = :relId ORDER BY Component_Name__c];
    }

    @IsTest
    static void pathsMapToComponents() {
        System.runAs(RlyTestData.admin()) {
            List<String> paths = new List<String>{
                SRC + 'classes/OldHelper.cls', SRC + 'classes/OldHelper.cls-meta.xml', SRC + 'triggers/OldTrigger.trigger',
                SRC + 'lwc/oldCard/oldCard.js', SRC + 'lwc/oldCard/oldCard.html', SRC + 'lwc/jsconfig.json', SRC + 'aura/oldCmp/oldCmp.cmp',
                SRC + 'objects/Invoice__c/Invoice__c.object-meta.xml', SRC + 'objects/Invoice__c/fields/Total__c.field-meta.xml',
                SRC + 'objects/Invoice__c/validationRules/Positive.validationRule-meta.xml',
                SRC + 'objects/Invoice__c/recordTypes/Credit.recordType-meta.xml', SRC + 'objects/Invoice__c/listViews/All.listView-meta.xml',
                SRC + 'objects/Invoice__c/compactLayouts/Small.compactLayout-meta.xml', SRC + 'flows/Old_Flow.flow-meta.xml',
                SRC + 'layouts/Invoice__c-Invoice Layout.layout-meta.xml', SRC + 'permissionsets/Old_Access.permissionset-meta.xml',
                SRC + 'labels/CustomLabels.labels-meta.xml', SRC + 'pages/OldPage.page', SRC + 'components/OldComp.component',
                SRC + 'staticresources/OldLogo.resource-meta.xml', SRC + 'staticresources/OldLogo.resource', SRC + 'tabs/Old_Tab.tab-meta.xml',
                SRC + 'classes/.cls', 'README.md', 'other/classes/Elsewhere.cls'
            };
            List<String> keys = RlyDeletionPaths.keysOf(paths, 'force-app/main/default/');
            System.assertEquals(new List<String>{ 'ApexClass:OldHelper', 'ApexTrigger:OldTrigger', 'LightningComponentBundle:oldCard',
                'AuraDefinitionBundle:oldCmp', 'CustomObject:Invoice__c', 'CustomField:Invoice__c.Total__c', 'ValidationRule:Invoice__c.Positive',
                'RecordType:Invoice__c.Credit', 'ListView:Invoice__c.All', 'Flow:Old_Flow', 'Layout:Invoice__c-Invoice Layout',
                'PermissionSet:Old_Access', 'ApexPage:OldPage', 'ApexComponent:OldComp', 'StaticResource:OldLogo', 'CustomTab:Old_Tab' },
                keys, 'Each supported component once; labels, unknown files and other folders left out');
            System.assertEquals('ApexClass:X', RlyDeletionPaths.keyOf('main/default/classes/X.cls'), 'Any depth below the source path');
            System.assertEquals(2, RlyDeletionPaths.keysOf(new List<String>{ 'classes/A.cls', 'x/classes/B.cls' }, ' ').size(), 'No source path');
        }
    }

    @IsTest
    static void findDeletionsListsWhatTheOrgLacks() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyMetadataMock mock = new RlyMetadataMock().add('ApexClass', 'AccountService', RECENT).add('CustomObject', 'Invoice__c', RECENT);
            mock.gitTree = tree(new List<String>{ SRC + 'classes/AccountService.cls', SRC + 'classes/OldHelper.cls',
                SRC + 'lwc/oldCard/oldCard.js', SRC + 'lwc/jsconfig.json', SRC + 'objects/Account/fields/Industry.field-meta.xml',
                SRC + 'objects/Account/fields/Old__c.field-meta.xml', SRC + 'objects/Invoice__c/Invoice__c.object-meta.xml',
                SRC + 'labels/CustomLabels.labels-meta.xml', SRC + 'layouts/Account-Account %28Old%29 Layout.layout-meta.xml', 'README.md' });
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<RlyChangeFinder.Change> found = RlyChangesController.findDeletions(devId);
            Test.stopTest();
            Set<String> keys = new Set<String>();
            for (RlyChangeFinder.Change c : found) {
                keys.add(c.key);
                System.assert(c.deleted, 'A deletion candidate: ' + c.key);
                System.assertEquals(c.type + ':' + c.name, c.key, 'Keyed type:name');
            }
            System.assertEquals(new Set<String>{ 'ApexClass:OldHelper', 'LightningComponentBundle:oldCard', 'CustomField:Account.Old__c',
                'Layout:Account-Account (Old) Layout' }, keys, 'On dev1 but not in DEV1; standard fields left out');
        }
    }

    @IsTest
    static void findDeletionsExplainsWhatStopsIt() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock());
            Test.startTest();
            String missingBranch;
            try {
                RlyChangesController.findDeletions(devId);
            } catch (AuraHandledException e) {
                missingBranch = e.getMessage();
            }
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            conn.Provider__c = 'GitLab';
            update conn;
            String unsupported;
            try {
                RlyChangesController.findDeletions(devId);
            } catch (AuraHandledException e) {
                unsupported = e.getMessage();
            }
            Test.stopTest();
            System.assert(missingBranch != null && missingBranch.contains('Listing the files on dev1'), 'No such branch: ' + missingBranch);
            System.assert(unsupported != null && unsupported.contains('isn\'t available for GitLab'), 'Other providers: ' + unsupported);
        }
    }

    @IsTest
    static void branchFallsBackToTheFirstStage() {
        System.runAs(RlyTestData.admin()) {
            String noStage;
            try {
                RlyDeletionFinder.branchOf(new RLY_Org__c(Name = 'DEV9'));
            } catch (RlyReleaseException e) {
                noStage = e.getMessage();
            }
            String noGit;
            try {
                RlyDeletionFinder.find(new RLY_Org__c(Name = 'DEV9'));
            } catch (RlyReleaseException e) {
                noGit = e.getMessage();
            }
            RlyReleaseTestData.route();
            System.assertEquals('sit', RlyDeletionFinder.branchOf(new RLY_Org__c(Name = 'DEV9')), 'The first stage\'s branch');
            System.assertEquals('dev9', RlyDeletionFinder.branchOf(new RLY_Org__c(Name = 'DEV9', Branch__c = ' dev9 ')), 'Its own branch');
            System.assertEquals('Give DEV9 its own branch on the Pipeline tab first.', noStage, 'No branch to read');
            System.assert(noGit.contains('Git connection'), 'Git connection needed: ' + noGit);
        }
    }

    @IsTest
    static void raiseWithOnlyDeletionsNeedsNoRetrieveOrTests() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            Id relId = RlyRaiseService.raise(deletionRequest(devId));
            RLY_Release__c rel = saved(relId);
            System.assertEquals('Retrieving', rel.Status__c, 'Saved for the next read');
            System.assertEquals(null, rel.Retrieve_Id__c, 'Nothing to retrieve');
            System.assertEquals('ApexClass:OldHelper,ApexTrigger:OldTrigger', rel.Deletions__c, 'Deletions saved');
            System.assertEquals(2, rel.Deletion_Count__c, 'Counted');
            System.assertEquals(0, rel.Component_Count__c, 'No components');
            List<RLY_Release_Item__c> items = itemsOf(relId);
            System.assertEquals(2, items.size(), 'An item per deletion');
            System.assert(items[0].Is_Deletion__c && items[1].Is_Deletion__c, 'Marked as deletions');
        }
    }

    @IsTest
    static void raiseMovesDeletedItemsAndRetrievesTheRest() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = deletionRequest(devId);
            RlyRaiseService.Item gone = RlyReleaseTestData.item('ApexPage', 'OldPage');
            gone.deleted = true;
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout'), gone };
            req.deletions.add(RlyReleaseTestData.item('ApexClass', 'OldHelper'));
            Test.startTest();
            RLY_Release__c rel = saved(RlyReleasesController.raiseRelease(JSON.serialize(req)));
            Test.stopTest();
            System.assertEquals(RlyFlowScenario.RETRIEVE_ID, rel.Retrieve_Id__c, 'The added layout is retrieved');
            System.assertEquals('ApexClass:OldHelper,ApexTrigger:OldTrigger,ApexPage:OldPage', rel.Deletions__c, 'Each deletion once');
            System.assertEquals(1, rel.Component_Count__c, 'One component added');
            System.assertEquals(3, rel.Deletion_Count__c, 'Three deleted');
        }
    }

    @IsTest
    static void raiseRefusesBadDeletions() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyRaiseService.RaiseRequest both = deletionRequest(devId);
            both.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexClass', 'OldHelper'),
                RlyReleaseTestData.item('ApexClass', 'OldHelperTest') };
            both.testClasses = new List<String>{ 'OldHelperTest' };
            RlyRaiseService.RaiseRequest comma = deletionRequest(devId);
            comma.deletions.add(RlyReleaseTestData.item('Layout', 'A,B'));
            RlyRaiseService.RaiseRequest blank = deletionRequest(devId);
            blank.deletions.add(RlyReleaseTestData.item(' ', 'X'));
            RlyRaiseService.RaiseRequest tooMany = deletionRequest(devId);
            tooMany.deletions.add(RlyReleaseTestData.item('ApexClass', 'X'.repeat(RlyDeletions.MAX_LENGTH)));
            RlyRaiseService.RaiseRequest nothing = deletionRequest(devId);
            nothing.deletions = null;
            System.assertEquals('ApexClass OldHelper is both added and deleted.', refusal(both), 'Added and deleted');
            System.assert(refusal(comma).contains('commas or colons'), 'Names the pipeline can\'t carry');
            System.assertEquals('Give each deletion a type and a name.', refusal(blank), 'Type and name needed');
            System.assert(refusal(tooMany).startsWith('Too many deletions'), 'More than the field holds');
            System.assertEquals('Select at least one component.', refusal(nothing), 'Nothing selected');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release__c], 'Nothing saved');
        }
    }

    @IsTest
    static void deletionsOnlyCommitTheMarkerAndDispatch() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            Id relId = RlyRaiseService.raise(deletionRequest(devId));
            RLY_Release__c rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :relId];
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.refreshRelease(relId);
            Test.stopTest();
            RLY_Release__c after = saved(relId);
            Map<String, Object> inputs = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'))).get('inputs');
            Map<String, Object> marker = (Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('.relay-inbox/' + rel.Name + '.deletions'));
            System.assertEquals('Workflow running', after.Status__c, 'Pipeline started: ' + after.Error_Message__c);
            System.assertEquals('ApexClass:OldHelper,ApexTrigger:OldTrigger', inputs.get('deletions'), 'Deletions input');
            System.assertEquals('', inputs.get('components'), 'No components');
            System.assertEquals('ApexClass:OldHelper,ApexTrigger:OldTrigger\n',
                EncodingUtil.base64Decode(String.valueOf(marker.get('content'))).toString(), 'The marker holds the list');
            System.assert(!mock.callLog().contains('/services/Soap/m/'), 'No retrieve');
            System.assertEquals(new List<Object>(), RlyReleaseTestData.dispatchedOptions(mock).get('tests'), 'Sandbox: NoTestRun');
        }
    }

    @IsTest
    static void nothingToReleaseFails() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            update new RLY_Release__c(Id = rel.Id, Retrieve_Id__c = null);
            Test.setMock(HttpCalloutMock.class, RlyFlowScenario.forRelease(rel).build());
            Test.startTest();
            RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            RLY_Release__c after = saved(rel.Id);
            System.assertEquals('Failed', after.Status__c, 'Ends');
            System.assertEquals('The release has no components and no deletions.', after.Error_Message__c, 'Why');
        }
    }

    @IsTest
    static void apexDeletionsIntoTheHubRunLocalTests() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c intoHub = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('c'));
            update new RLY_Release__c(Id = intoHub.Id, Test_Classes__c = null, Deletions__c = 'ApexClass:OldHelper', Deletion_Count__c = 1);
            RLY_Release__c intoSit = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('d'));
            update new RLY_Release__c(Id = intoSit.Id, Test_Classes__c = null, Deletions__c = 'ApexClass:OldHelper', Deletion_Count__c = 1);
            Map<String, Object> hub = RlyPipelineOptions.forMode(RlyReleaseStore.release(intoHub.Id), 'check');
            Map<String, Object> sit = RlyPipelineOptions.forMode(RlyReleaseStore.release(intoSit.Id), 'check');
            update new RLY_Release__c(Id = intoHub.Id, Deletions__c = 'Layout:Old');
            Map<String, Object> noApex = RlyPipelineOptions.forMode(RlyReleaseStore.release(intoHub.Id), 'check');
            System.assert(!hub.containsKey('tests'), 'Production: no tests list, so RunLocalTests');
            System.assertEquals(new List<String>(), sit.get('tests'), 'Sandbox: NoTestRun');
            System.assertEquals(new List<String>(), noApex.get('tests'), 'No Apex deleted: NoTestRun');
            System.assert(RlyDeletions.deletesApex(new RLY_Release__c(Deletions__c = 'ApexTrigger:T')), 'Triggers are Apex');
        }
    }

    @IsTest
    static void pagesShowTheDeletions() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c older = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            RLY_Release__c newer = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('b'));
            update new RLY_Release__c(Id = older.Id, Deletions__c = 'ApexClass:OldHelper,Layout:Old', Deletion_Count__c = 2);
            update new RLY_Release__c(Id = newer.Id, Deletions__c = 'Layout:Old,Flow:Old_Flow', Deletion_Count__c = 2,
                Last_Synced__c = System.now().addMinutes(-5));
            insert new RLY_Release_Item__c(Release__c = older.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'OldHelper',
                Is_Deletion__c = true, Change_Type__c = 'Modified', Source__c = 'Detected');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(older.Id);
            Integer listed = 0;
            for (RlyReleasesController.Row r : RlyReleasesController.listReleases('all')) {
                listed += r.deletionCount;
            }
            RlyPromoteController.PromoteBoard board = RlyPromoteController.getPromote();
            Id promotionId = RlyPromoteController.promote(JSON.serialize(new Map<String, Object>{ 'stageId' => orgId('SIT'),
                'releaseIds' => new List<Id>{ older.Id, newer.Id }, 'title' => 'Promote 2 releases to PROD' }));
            RLY_Release__c promotion = saved(promotionId);
            System.assertEquals(new List<String>{ 'ApexClass:OldHelper', 'Layout:Old' }, d.deletions, 'Detail lists them');
            System.assertEquals(4, listed, 'Rows count them');
            System.assertEquals(2, board.stages[0].ready[0].deletionCount, 'Promote rows count them');
            System.assertEquals('ApexClass:OldHelper,Layout:Old,Flow:Old_Flow', promotion.Deletions__c, 'The promotion carries them, each once');
            System.assertEquals(3, promotion.Deletion_Count__c, 'Counted');
            System.assertEquals(2, promotion.Component_Count__c, 'Components apart from deletions');
            System.assert(RlySlackCardText.aboutLines(RlyReleaseStore.release(older.Id)).contains('Deletes: ApexClass:OldHelper, Layout:Old\n'),
                'The Slack card lists them');
        }
    }

    @IsTest
    static void slackSummaryShowsTheFirstFive() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = new RLY_Release__c(Deletions__c = 'Flow:A, Flow:B,Flow:C,Flow:D,Flow:E,Flow:F,Flow:G,Flow:A');
            System.assertEquals('Deletes: Flow:A, Flow:B, Flow:C, Flow:D, Flow:E and 2 more', RlyDeletions.summary(rel), 'First five');
            System.assertEquals(null, RlyDeletions.summary(new RLY_Release__c()), 'Nothing deleted');
            System.assertEquals(null, RlyDeletions.marker(new RLY_Release__c(), 'feature/x'), 'No marker without deletions');
            System.assertEquals(new List<String>(), RlyDeletions.of(null), 'No release');
        }
    }
}
