/**
 * @description Tests for New Release steps 1 and 2 (RlyChangesController, RlyReleaseStart, RlyChangeFinder, RlyMetadata).
 * Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it (a callout can't follow DML).
 */
@IsTest
private class RlyChangesControllerTest {

    private static final String SINCE = '2026-10-01T00:00:00Z';
    private static final String RECENT = '2026-10-30T10:00:00.000Z';
    private static final String OLD = '2026-01-01T10:00:00.000Z';

    // DEV1 -> SIT -> UAT -> hub, with a checked Git connection. Returns DEV1's Id.
    private static Id insertRoute() {
        RLY_Org__c dev = RlyTestData.org('DEV1', 'Developer', 'dev1');
        insert new List<RLY_Org__c>{ dev, RlyTestData.stage('UAT', 'uat', 2), RlyTestData.stage('SIT', 'sit', 1), RlyTestData.org('PROD', 'Hub', 'prod') };
        insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
            Pipeline__c = '.github/workflows/release-relay.yml', Pipeline_Branch__c = 'main', Status__c = 'Connected');
        return dev.Id;
    }

    private static Map<String, RlyChangeFinder.Change> byKey(List<RlyChangeFinder.Change> changes) {
        Map<String, RlyChangeFinder.Change> out = new Map<String, RlyChangeFinder.Change>();
        for (RlyChangeFinder.Change c : changes) {
            out.put(c.key, c);
        }
        return out;
    }

    @IsTest
    static void startShowsWhatIsMissing() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assertEquals(3, s.problems.size(), 'No Git, no stage and no developer org: ' + s.problems);
            System.assertEquals(null, s.targetName, 'Nothing to release into yet');
        }
    }

    @IsTest
    static void startFindsTheFirstStage() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assert(s.problems.isEmpty(), 'Route is complete: ' + s.problems);
            System.assertEquals('SIT', s.targetName, 'Releases go to the lowest stage order');
            System.assertEquals('sit', s.targetBranch, 'Target branch');
            System.assertEquals(1, s.developers.size(), 'One developer org');
            System.assertEquals('acme/release', s.repository, 'Repository');
            System.assertEquals(UserInfo.getName(), s.hubUserName, 'Hub user name, for Changed by me');
            Map<String, Object> fields = s.developers[0].getPopulatedFieldsAsMap();
            System.assert(!fields.containsKey('Consumer_Key__c') && !fields.containsKey('Client_Id__c'), 'No consumer key goes to the page');
        }
    }

    @IsTest
    static void describeListsCustomAndStandardTypes() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock());
            Test.startTest();
            RlyMetadata.TypeList types = RlyChangesController.describeTypes(devId);
            Test.stopTest();
            System.assert(types.types.contains('ApexClass'), 'Top-level type: ' + types.types);
            System.assert(types.types.contains('CustomField'), 'Child types are listed too');
            System.assert(!types.types.contains('ConnectedApp'), 'Skipped type');
            System.assert(!types.types.contains('AccountSettings'), 'Settings are left out');
            System.assert(!types.types.contains('ReportFolder'), 'Folder types are listed through their folders');
            System.assertEquals(new List<String>{ 'Report' }, types.folderTypes, 'Folder-based types apart');
        }
    }

    @IsTest
    static void listChangesFiltersAndTags() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock()
                .add('ApexClass', 'AccountService', RECENT)
                .add('ApexClass', 'OldClass', OLD)
                .addManaged('ApexClass', 'pkg__Thing', RECENT)
                .add('CustomObject', 'Account', RECENT)
                .add('CustomObject', 'Invoice__c', RECENT)
                .add('CustomField', 'Account.Industry', RECENT)
                .add('CustomField', 'Account.Region__c', RECENT)
                .add('Layout', 'Account-Account Layout', RECENT));
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyChangesController.listChanges(devId,
                new List<String>{ 'ApexClass', 'CustomObject', 'CustomField', 'Layout' }, SINCE));
            List<RlyChangeFinder.Change> everything = RlyChangesController.listChanges(devId, new List<String>{ 'ApexClass' }, null);
            Test.stopTest();
            System.assertEquals(6, found.size(), 'Old and managed items are left out: ' + found.keySet());
            System.assert(!found.get('ApexClass:AccountService').standard, 'Apex is custom');
            System.assertEquals('Dev One', found.get('ApexClass:AccountService').modifiedBy, 'Changed by');
            System.assert(found.get('CustomObject:Account').standard, 'Account is standard');
            System.assert(!found.get('CustomObject:Invoice__c').standard, 'Invoice__c is custom');
            System.assert(found.get('CustomField:Account.Industry').standard, 'Industry is a standard field');
            System.assert(!found.get('CustomField:Account.Region__c').standard, 'Region__c is a custom field');
            System.assertEquals(2, everything.size(), 'Any time includes old items, still not managed ones');
        }
    }

    @IsTest
    static void listFolderChangesReadsEachFolder() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock()
                .add('ReportFolder', 'Sales', RECENT)
                .addManaged('ReportFolder', 'PkgReports', RECENT)
                .add('Report/Sales', 'Sales/Pipeline_Report', RECENT)
                .add('Report/Sales', 'Sales/Old_Report', OLD)
                .add('Report/PkgReports', 'PkgReports/Never', RECENT));
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyChangesController.listFolderChanges(devId, 'Report', SINCE));
            Test.stopTest();
            System.assert(found.containsKey('ReportFolder:Sales'), 'The folder itself: ' + found.keySet());
            System.assert(found.containsKey('Report:Sales/Pipeline_Report'), 'The changed report');
            System.assertEquals(2, found.size(), 'Old reports and managed folders are left out: ' + found.keySet());
        }
    }

    @IsTest
    static void trackedChangesComeInOneCall() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock());
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyChangesController.listTracked(devId, SINCE));
            Map<String, RlyChangeFinder.Change> anyTime = byKey(RlyChangesController.listTracked(devId, null));
            Test.stopTest();
            System.assertEquals(3, found.size(), 'Every tracked change');
            System.assertEquals('Dev One', found.get('ApexClass:AccountService').modifiedBy, 'User name looked up');
            System.assert(found.get('CustomField:Account.Industry').standard, 'Standard field');
            System.assert(found.get('ApexPage:OldPage').deleted, 'Deleted in the org');
            System.assertEquals(null, found.get('ApexPage:OldPage').modifiedBy, 'No user');
            System.assertEquals(2026, found.get('ApexClass:AccountService').modifiedOn.yearGmt(), 'Time parsed');
            System.assertEquals(3, anyTime.size(), 'Any time');
        }
    }

    @IsTest
    static void detectsTestClasses() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock());
            Test.startTest();
            List<String> tests = RlyChangesController.detectTests(devId, new List<String>{ 'AccountService', 'AccountServiceTest', 'Helper' });
            List<String> none = RlyChangesController.detectTests(devId, new List<String>());
            Test.stopTest();
            System.assertEquals(new List<String>{ 'AccountServiceTest', 'Helper' }, tests, '@IsTest in any case');
            System.assert(none.isEmpty(), 'Nothing to check');
        }
    }

    @IsTest
    static void refusesBadInput() {
        System.runAs(RlyTestData.admin()) {
            insertRoute();
            Id hubId = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id;
            Id devId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1' LIMIT 1].Id;
            List<String> tooMany = new List<String>();
            for (Integer i = 0; i < 25; i++) {
                tooMany.add('Type' + i);
            }
            Integer refused = 0;
            try { RlyChangesController.listChanges(devId, new List<String>(), null); } catch (AuraHandledException e) { refused++; }
            try { RlyChangesController.listChanges(devId, tooMany, null); } catch (AuraHandledException e) { refused++; }
            try { RlyChangesController.listTracked(hubId, null); } catch (AuraHandledException e) { refused++; }
            try { RlyChangesController.listTracked(devId, 'not a date'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Empty or too many types, the hub as source, and a bad date are refused');
            System.assertEquals(2026, RlyChangesController.since(SINCE).yearGmt(), 'Date read');
            System.assertEquals(null, RlyChangesController.since(''), 'No date: any time');
        }
    }

    @IsTest
    static void reportsOrgErrors() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyMetadataMock mock = new RlyMetadataMock();
            mock.fault = true;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            String faultMessage;
            try {
                RlyChangesController.describeTypes(devId);
            } catch (AuraHandledException e) {
                faultMessage = e.getMessage();
            }
            mock.fault = false;
            mock.garbage = true;
            String garbageMessage;
            try {
                RlyChangesController.listChanges(devId, new List<String>{ 'ApexClass' }, null);
            } catch (AuraHandledException e) {
                garbageMessage = e.getMessage();
            }
            String folderMessage;
            try {
                RlyChangesController.listFolderChanges(devId, 'ApexClass', null);
            } catch (AuraHandledException e) {
                folderMessage = e.getMessage();
            }
            Test.stopTest();
            System.assert(faultMessage.contains('Invalid Session ID'), 'SOAP fault shown: ' + faultMessage);
            System.assert(garbageMessage.contains('HTTP 500'), 'Non-XML answer shown: ' + garbageMessage);
            System.assert(folderMessage.contains('isn\'t a folder type'), 'Only folder types: ' + folderMessage);
        }
    }

    @IsTest
    static void emptyListIsFine() {
        System.runAs(RlyTestData.admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock());
            Test.startTest();
            List<RlyChangeFinder.Change> found = RlyChangesController.listChanges(devId, new List<String>{ 'Flow' }, SINCE);
            Test.stopTest();
            System.assert(found.isEmpty(), 'No flows');
            System.assert(RlyChangeFinder.isStandard('StandardValueSet', 'Industry'), 'Standard picklist');
            System.assert(!RlyChangeFinder.isStandard('Layout', 'Account-Account Layout'), 'Other types are custom');
        }
    }
}
