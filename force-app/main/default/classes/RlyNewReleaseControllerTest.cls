/**
 * Tests for New Release in the hub, steps 1 and 2 (RlyNewReleaseController, RlyChangeFinder, RlyMetadata).
 * Every test runs as an existing active System Administrator through System.runAs.
 * DML happens before Test.startTest; callouts after it (a callout can't follow DML).
 */
@IsTest
private class RlyNewReleaseControllerTest {

    private static final String SINCE = '2026-10-01T00:00:00Z';
    private static final String NEW_DATE = '2026-10-30T10:00:00.000Z';
    private static final String OLD_DATE = '2026-01-01T10:00:00.000Z';

    /** Plays a developer org: the Metadata API (SOAP) and REST/Tooling queries. */
    private class OrgMock implements HttpCalloutMock {
        public Boolean fault = false;
        public Boolean garbage = false;
        /** type, or type/folder => rows of { fullName, lastModifiedDate, manageableState, namespacePrefix } */
        public Map<String, List<List<String>>> items = new Map<String, List<List<String>>>();

        public OrgMock add(String key, String fullName, String modified, String state, String ns) {
            if (!items.containsKey(key)) {
                items.put(key, new List<List<String>>());
            }
            items.get(key).add(new List<String>{ fullName, modified, state, ns });
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String url = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            if (url.contains('/services/Soap/m/')) {
                res.setHeader('Content-Type', 'text/xml');
                res.setBody(soap(req.getBody()));
                if (fault || garbage) {
                    res.setStatusCode(500);
                }
                return res;
            }
            res.setHeader('Content-Type', 'application/json');
            if (url.contains('FROM SourceMember')) {
                res.setBody('{"records":['
                    + '{"MemberName":"AccountService","MemberType":"ApexClass","IsNameObsolete":false,"LastModifiedDate":"2026-10-30T10:00:00.000+0000","LastModifiedById":"005xx0000000001AAA"},'
                    + '{"MemberName":"Account.Industry","MemberType":"CustomField","IsNameObsolete":false,"LastModifiedDate":"2026-10-29T10:00:00.000+0000","LastModifiedById":"005xx0000000001AAA"},'
                    + '{"MemberName":"OldPage","MemberType":"ApexPage","IsNameObsolete":true,"LastModifiedDate":"2026-10-28T10:00:00.000+0000","LastModifiedById":null}]}');
            } else if (url.contains('FROM User')) {
                res.setBody('{"records":[{"Id":"005xx0000000001AAA","Name":"Dev One"}]}');
            } else if (url.contains('FROM ApexClass')) {
                res.setBody('{"records":['
                    + '{"Name":"AccountService","Body":"public with sharing class AccountService { }"},'
                    + '{"Name":"AccountServiceTest","Body":"@IsTest\\nprivate class AccountServiceTest { }"},'
                    + '{"Name":"Helper","Body":"@isTest\\npublic class Helper { }"}]}');
            } else {
                res.setStatusCode(404);
                res.setBody('[]');
            }
            return res;
        }

        private String soap(String body) {
            String head = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
                + ' xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
            String tail = '</soapenv:Body></soapenv:Envelope>';
            if (garbage) {
                return '<html>Service unavailable';
            }
            if (fault) {
                return head + '<soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>Invalid Session ID</faultstring></soapenv:Fault>' + tail;
            }
            if (body.contains('<met:describeMetadata>')) {
                return head + '<describeMetadataResponse><result>'
                    + mdo('ApexClass', false, null) + mdo('CustomObject', false, 'CustomField') + mdo('ConnectedApp', false, null)
                    + mdo('AccountSettings', false, null) + mdo('Report', true, null) + mdo('ReportFolder', false, null)
                    + '<organizationNamespace></organizationNamespace></result></describeMetadataResponse>' + tail;
            }
            String out = head + '<listMetadataResponse>';
            Matcher m = Pattern.compile('<met:queries>(?:<met:folder>([^<]*)</met:folder>)?<met:type>([^<]*)</met:type></met:queries>').matcher(body);
            while (m.find()) {
                String key = m.group(1) == null ? m.group(2) : m.group(2) + '/' + m.group(1);
                for (List<String> row : items.containsKey(key) ? items.get(key) : new List<List<String>>()) {
                    out += '<result><fullName>' + row[0] + '</fullName><lastModifiedByName>Dev One</lastModifiedByName>'
                        + '<lastModifiedDate>' + row[1] + '</lastModifiedDate><manageableState>' + row[2] + '</manageableState>'
                        + (row[3] == null ? '' : '<namespacePrefix>' + row[3] + '</namespacePrefix>')
                        + '<type>' + m.group(2) + '</type></result>';
                }
            }
            return out + '</listMetadataResponse>' + tail;
        }

        private String mdo(String name, Boolean inFolder, String child) {
            return '<metadataObjects>' + (child == null ? '' : '<childXmlNames>' + child + '</childXmlNames>')
                + '<inFolder>' + inFolder + '</inFolder><xmlName>' + name + '</xmlName></metadataObjects>';
        }
    }

    private static User admin() {
        return [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true
                ORDER BY CreatedDate ASC LIMIT 1];
    }

    private static RLY_Org__c org(String name, String role, String branch, Decimal stageOrder) {
        return new RLY_Org__c(Name = name, Role__c = role, Branch__c = branch, Stage_Order__c = stageOrder,
            Git_Environment__c = branch, My_Domain__c = 'https://' + name.toLowerCase() + '.my.salesforce.com',
            Login_Type__c = 'Production', Username__c = 'relay@' + name.toLowerCase() + '.demo',
            Client_Id__c = '3MVG9demo', Certificate__c = 'release_relay', Status__c = 'Connected');
    }

    /** DEV1 -> SIT -> UAT -> hub, with a checked Git connection. Returns DEV1's Id. */
    private static Id insertRoute() {
        RLY_Org__c dev = org('DEV1', 'Developer', 'dev1', null);
        insert new List<RLY_Org__c>{ dev, org('UAT', 'Stage', 'uat', 2), org('SIT', 'Stage', 'sit', 1), org('PROD', 'Hub', 'prod', null) };
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
        System.runAs(admin()) {
            RlyNewReleaseController.Start s = RlyNewReleaseController.getStart();
            System.assertEquals(3, s.problems.size(), 'No Git, no stage and no developer org: ' + s.problems);
            System.assertEquals(null, s.targetName, 'Nothing to release into yet');
        }
    }

    @IsTest
    static void startFindsTheFirstStage() {
        System.runAs(admin()) {
            insertRoute();
            RlyNewReleaseController.Start s = RlyNewReleaseController.getStart();
            System.assert(s.problems.isEmpty(), 'Route is complete: ' + s.problems);
            System.assertEquals('SIT', s.targetName, 'Releases go to the lowest stage order');
            System.assertEquals('sit', s.targetBranch, 'Target branch');
            System.assertEquals(1, s.developers.size(), 'One developer org');
            System.assertEquals('acme/release', s.repository, 'Repository');
            System.assertEquals(UserInfo.getName(), s.hubUserName, 'Hub user name, for Changed by me');
        }
    }

    @IsTest
    static void describeListsCustomAndStandardTypes() {
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            RlyMetadata.TypeList types = RlyNewReleaseController.describeTypes(devId);
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
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock()
                .add('ApexClass', 'AccountService', NEW_DATE, 'unmanaged', null)
                .add('ApexClass', 'OldClass', OLD_DATE, 'unmanaged', null)
                .add('ApexClass', 'pkg__Thing', NEW_DATE, 'installed', 'pkg')
                .add('CustomObject', 'Account', NEW_DATE, 'unmanaged', null)
                .add('CustomObject', 'Invoice__c', NEW_DATE, 'unmanaged', null)
                .add('CustomField', 'Account.Industry', NEW_DATE, 'unmanaged', null)
                .add('CustomField', 'Account.Region__c', NEW_DATE, 'unmanaged', null)
                .add('Layout', 'Account-Account Layout', NEW_DATE, 'unmanaged', null));
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyNewReleaseController.listChanges(devId,
                new List<String>{ 'ApexClass', 'CustomObject', 'CustomField', 'Layout' }, SINCE));
            List<RlyChangeFinder.Change> everything = RlyNewReleaseController.listChanges(devId, new List<String>{ 'ApexClass' }, null);
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
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock()
                .add('ReportFolder', 'Sales', NEW_DATE, 'unmanaged', null)
                .add('ReportFolder', 'PkgReports', NEW_DATE, 'installed', 'pkg')
                .add('Report/Sales', 'Sales/Pipeline_Report', NEW_DATE, 'unmanaged', null)
                .add('Report/Sales', 'Sales/Old_Report', OLD_DATE, 'unmanaged', null)
                .add('Report/PkgReports', 'PkgReports/Never', NEW_DATE, 'unmanaged', null));
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyNewReleaseController.listFolderChanges(devId, 'Report', SINCE));
            Test.stopTest();
            System.assert(found.containsKey('ReportFolder:Sales'), 'The folder itself: ' + found.keySet());
            System.assert(found.containsKey('Report:Sales/Pipeline_Report'), 'The changed report');
            System.assertEquals(2, found.size(), 'Old reports and managed folders are left out: ' + found.keySet());
        }
    }

    @IsTest
    static void trackedChangesComeInOneCall() {
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            Map<String, RlyChangeFinder.Change> found = byKey(RlyNewReleaseController.listTracked(devId, SINCE));
            Map<String, RlyChangeFinder.Change> anyTime = byKey(RlyNewReleaseController.listTracked(devId, null));
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
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            List<String> tests = RlyNewReleaseController.detectTests(devId, new List<String>{ 'AccountService', 'AccountServiceTest', 'Helper' });
            List<String> none = RlyNewReleaseController.detectTests(devId, new List<String>());
            Test.stopTest();
            System.assertEquals(new List<String>{ 'AccountServiceTest', 'Helper' }, tests, '@IsTest in any case');
            System.assert(none.isEmpty(), 'Nothing to check');
        }
    }

    @IsTest
    static void refusesBadInput() {
        System.runAs(admin()) {
            insertRoute();
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
            Id devId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1'].Id;
            List<String> tooMany = new List<String>();
            for (Integer i = 0; i < 25; i++) {
                tooMany.add('Type' + i);
            }
            Integer refused = 0;
            try { RlyNewReleaseController.listChanges(devId, new List<String>(), null); } catch (AuraHandledException e) { refused++; }
            try { RlyNewReleaseController.listChanges(devId, tooMany, null); } catch (AuraHandledException e) { refused++; }
            try { RlyNewReleaseController.listTracked(sitId, null); } catch (AuraHandledException e) { refused++; }
            try { RlyNewReleaseController.listTracked(devId, 'not a date'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Empty or too many types, a stage as source, and a bad date are refused');
            System.assertEquals(2026, RlyNewReleaseController.since(SINCE).yearGmt(), 'Date read');
            System.assertEquals(null, RlyNewReleaseController.since(''), 'No date: any time');
        }
    }

    @IsTest
    static void reportsOrgErrors() {
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            OrgMock mock = new OrgMock();
            mock.fault = true;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            String faultMessage;
            try {
                RlyNewReleaseController.describeTypes(devId);
            } catch (AuraHandledException e) {
                faultMessage = e.getMessage();
            }
            mock.fault = false;
            mock.garbage = true;
            String garbageMessage;
            try {
                RlyNewReleaseController.listChanges(devId, new List<String>{ 'ApexClass' }, null);
            } catch (AuraHandledException e) {
                garbageMessage = e.getMessage();
            }
            String folderMessage;
            try {
                RlyNewReleaseController.listFolderChanges(devId, 'ApexClass', null);
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
        System.runAs(admin()) {
            Id devId = insertRoute();
            RlyOrgSession.testToken = '00Dxx!token';
            Test.setMock(HttpCalloutMock.class, new OrgMock());
            Test.startTest();
            List<RlyChangeFinder.Change> found = RlyNewReleaseController.listChanges(devId, new List<String>{ 'Flow' }, SINCE);
            Test.stopTest();
            System.assert(found.isEmpty(), 'No flows');
            System.assert(RlyChangeFinder.isStandard('StandardValueSet', 'Industry'), 'Standard picklist');
            System.assert(!RlyChangeFinder.isStandard('Layout', 'Account-Account Layout'), 'Other types are custom');
        }
    }
}
