/**
 * @description Tests for adding changes to an open release (RlyAppendController, RlyAppendService, RlyAppendRules,
 * RlyAppendRun, RlyAppendInputs and their parts of RlyStatusReader, RlyPipelineRun, RlyPipelineOptions, RlyCheckReader
 * and RlyReleasesController). Route DEV1 -> SIT -> PROD (hub); the release has AccountService and AccountServiceTest and
 * an open pull request. Each test runs through System.runAs as an active System Administrator with Release Relay Admin
 * (or a new user without it). Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyAppendTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A release whose checks failed, with its pull request open.
    private static RLY_Release__c openRelease() {
        RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Passed', Validation_Status__c = 'Failed');
        return rel;
    }

    // A release waiting for the retrieve of an add: Holiday and its test, and the deletion of a layout.
    private static RLY_Release__c adding(String retrieveId) {
        RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
        RlyAppendRun.State st = new RlyAppendRun.State();
        st.adds = 1;
        st.pending = true;
        st.fromOrg = 'DEV1';
        st.components = retrieveId == null ? new List<String>() : new List<String>{ 'ApexClass:Holiday', 'ApexClass:HolidayTest' };
        st.deletions = new List<String>{ 'Layout:Old Layout' };
        st.tests = retrieveId == null ? new List<String>() : new List<String>{ 'HolidayTest' };
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Retrieve_Id__c = retrieveId, Append_State__c = JSON.serialize(st));
        return rel;
    }

    private static String request(Id releaseId, List<RlyRaiseService.Item> items, List<RlyRaiseService.Item> deletions) {
        RlyAppendService.AppendRequest r = new RlyAppendService.AppendRequest();
        r.releaseId = releaseId;
        r.items = items;
        r.deletions = deletions;
        r.testClasses = new List<String>();
        return JSON.serialize(r);
    }

    private static String refusal(String requestJson) {
        try {
            RlyAppendController.appendChanges(requestJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static RLY_Release__c saved(Id relId) {
        return [SELECT Status__c, Retrieve_Id__c, Append_State__c, Approval_Status__c, Scan_Status__c, Validation_Status__c, Test_Classes__c,
                       Deletions__c, Deletion_Count__c, Component_Count__c, Error_Message__c, Pending_Run__c, Source_Branch__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    @IsTest
    static void pageOffersTheAddAndTheBuilderStarts() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            RlyAppendService.AppendStart s = RlyAppendController.getAppend(rel.Id);
            Test.stopTest();
            System.assert(d.canAppend, 'The raiser (an admin) can add changes to an open release whose checks failed');
            System.assertEquals(rel.Name, s.name, 'The release');
            System.assertEquals('DEV1', s.sourceName, 'From its developer org');
            System.assertEquals('SIT', s.targetName, 'Into its target');
            System.assertEquals(2, s.components.size(), 'What it has already');
            System.assertEquals(new List<String>{ 'AccountServiceTest' }, s.tests, 'Its tests');
        }
    }

    @IsTest
    static void addStartsTheRetrieveAndReopensTheRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, RlyFlowScenario.forRelease(rel).build());
            List<RlyRaiseService.Item> items = new List<RlyRaiseService.Item>{
                RlyReleaseTestData.item('ApexClass', 'Holiday'), RlyReleaseTestData.item('ApexClass', 'AccountService') };
            Test.startTest();
            Id relId = RlyAppendController.appendChanges(request(rel.Id, items, null));
            Test.stopTest();
            RLY_Release__c row = saved(relId);
            System.assertEquals('Retrieving', row.Status__c, 'Waiting for the retrieve');
            System.assertEquals(RlyFlowScenario.RETRIEVE_ID, row.Retrieve_Id__c, 'Retrieve id');
            System.assertEquals('Pending', row.Approval_Status__c, 'Approval cleared');
            System.assertEquals('Pending', row.Validation_Status__c, 'The checks run again');
            RlyAppendRun.State st = RlyAppendRun.stateOf(row);
            System.assert(st.pending, 'Pending');
            System.assertEquals(1, st.adds, 'The first add');
            System.assertEquals(new List<String>{ 'ApexClass:Holiday' }, st.components, 'Only what is new; its test is the release\'s');
            RLY_Release_Event__c ev = [SELECT Event_Type__c, Detail__c FROM RLY_Release_Event__c WHERE Release__c = :relId
                                       ORDER BY CreatedDate DESC LIMIT 1];
            System.assertEquals('Added 1 component from DEV1: Holiday', ev.Detail__c, 'History');
            System.assert(!RlyReleasesController.getRelease(relId).canAppend, 'Not while it runs');
        }
    }

    @IsTest
    static void readerCommitsTheAddAndRunsAppend() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = adding(RlyFlowScenario.RETRIEVE_ID);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c row = saved(rel.Id);
            System.assertEquals('Workflow running', row.Status__c, 'Running: ' + row.Error_Message__c);
            System.assertEquals('hub', row.Pending_Run__c, 'Mode hub, as after a raise');
            System.assert(mock.callLog().contains('/contents/.relay-inbox/' + rel.Name + '-add-1.zip'), 'The add\'s zip: ' + mock.callLog());
            Map<String, Object> options = RlyReleaseTestData.dispatchedOptions(mock);
            System.assertEquals(true, options.get('append'), 'Append');
            System.assertEquals('.relay-inbox/' + rel.Name + '-add-1.zip', options.get('appendZip'), 'Its zip');
            Set<Object> tests = new Set<Object>((List<Object>) options.get('tests'));
            System.assertEquals(new Set<Object>{ 'AccountServiceTest', 'HolidayTest' }, tests, 'Old and new tests');
            Map<String, Object> inputs = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'))).get('inputs');
            System.assertEquals('ApexClass:Holiday,ApexClass:HolidayTest', inputs.get('components'), 'Only the new components');
            System.assertEquals('Layout:Old Layout', inputs.get('deletions'), 'Only the new deletions');
            System.assertEquals(5, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c = :rel.Id], 'The new items saved');
            System.assertEquals(4, row.Component_Count__c, 'Counted');
            System.assertEquals(1, row.Deletion_Count__c, 'Its deletion');
            System.assertEquals(false, RlyAppendRun.stateOf(row).pending, 'Done');
            System.assertEquals(1, RlyAppendRun.stateOf(row).adds, 'The count stays for the next zip');
        }
    }

    @IsTest
    static void deletionsOnlyAddCommitsAnEmptyZip() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = adding(null);
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Workflow running', saved(rel.Id).Status__c, 'Running');
            System.assert(mock.bodyFor('/contents/.relay-inbox/').contains(RlyAppendInputs.EMPTY_ZIP), 'An empty zip');
            System.assertEquals('', ((Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches')))
                .get('inputs')).get('components'), 'No components');
        }
    }

    @IsTest
    static void failedRetrieveLeavesTheReleaseAsItWas() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = adding(RlyFlowScenario.RETRIEVE_ID);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Failed';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c row = saved(rel.Id);
            System.assertEquals('Checks failed', row.Status__c, 'Back where it was, not Failed');
            System.assert(row.Error_Message__c.startsWith('Couldn\'t add the changes from DEV1'), row.Error_Message__c);
            System.assertEquals(2, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c = :rel.Id], 'Nothing added');
            System.assertEquals(false, RlyAppendRun.stateOf(row).pending, 'Not pending');
        }
    }

    @IsTest
    static void failedAppendRunSaysWhy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            scenario.results.put('raise', RlyReleaseTestData.result('raise', '"status":"Failed","message":"Layout Old isn\'t in the branch"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c row = saved(rel.Id);
            System.assertEquals('Checks failed', row.Status__c, 'The checks didn\'t run');
            System.assertEquals('Layout Old isn\'t in the branch', row.Error_Message__c, 'raise.json says why');
        }
    }

    @IsTest
    static void addIsRefused() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            List<RlyRaiseService.Item> existing = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexClass', 'AccountService') };
            List<RlyRaiseService.Item> holiday = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexClass', 'Holiday') };
            Test.startTest();
            System.assert(refusal(request(rel.Id, existing, null)).startsWith('Pick at least one component that isn\'t in'), 'Nothing new');
            System.assert(refusal(request(rel.Id, holiday, existing)).contains('is both added and deleted'), 'Deletes what it adds');
            update new RLY_Release__c(Id = rel.Id, Test_Classes__c = null);
            System.assert(refusal(request(rel.Id, holiday, null)).contains('test class'), 'Apex needs a test');
            update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved');
            System.assert(refusal(request(rel.Id, holiday, null)).contains('before it\'s approved'), 'Approved already');
            update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Pending', Release_Type__c = 'Promotion');
            System.assert(refusal(request(rel.Id, holiday, null)).contains('raised from a developer org'), 'Not a promotion');
            System.assertEquals('Release not found.', refusal(request(null, holiday, null)), 'No release');
            update new RLY_Release__c(Id = rel.Id, Release_Type__c = 'Release', Test_Classes__c = 'AccountServiceTest');
            Boolean wrapped = false;
            try {
                RlyAppendController.getAppend(null);
            } catch (AuraHandledException e) {
                wrapped = e.getMessage() == 'Release not found.';
            }
            Test.stopTest();
            System.assert(wrapped, 'The builder hears why');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RLY_Release__c rel = RlyReleaseStore.release([SELECT Id FROM RLY_Release__c LIMIT 1].Id);
            System.assert(!RlyAppendRules.mayAppend(rel), 'Not the raiser, not an admin');
        }
    }
}
