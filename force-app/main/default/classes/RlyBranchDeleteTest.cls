/**
 * @description Tests for Delete from the branch and deletions of every type (build 37.1): RlyPathRules (folder rules
 * from describeMetadata, the fixed rules, the checks on rules the page sends back), RlyDeletionPaths and
 * RlyDeletionKinds (paths of many types: files, bundles, objects' children, folders, settings, territory models),
 * RlyDeletable (what a deploy can't delete, managed packages), RlyDeletionRules refusing them at raise, and
 * RlyChangePartsController.branchPlan / deletionPart reading the target's branch. GitHub and the org answer through
 * RlyHttpMock; nothing depends on org data. Every test runs through System.runAs as an active System Administrator.
 */
@IsTest
private class RlyBranchDeleteTest {

    private static final String SHA_SIT = 'a'.repeat(40);
    private static final String SHA_QUEUES = 'b'.repeat(40);
    private static final String SHA_MODELS = 'c'.repeat(40);
    private static final String SHA_MODEL = 'd'.repeat(40);
    private static final String SHA_SETTINGS = 'e'.repeat(40);
    private static final String SOAP_HEAD = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope '
        + 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
    private static final String SOAP_TAIL = '</soapenv:Body></soapenv:Envelope>';

    // One describeMetadata type: xmlName, directoryName, suffix (blank: none); inFolder.
    private static String mdo(List<String> type, Boolean inFolder) {
        return '<metadataObjects><directoryName>' + type[1] + '</directoryName><inFolder>' + inFolder + '</inFolder>'
            + '<metaFile>false</metaFile>' + (String.isBlank(type[2]) ? '' : '<suffix>' + type[2] + '</suffix>')
            + '<xmlName>' + type[0] + '</xmlName></metadataObjects>';
    }

    private static String describeBody(String ns) {
        return '<describeMetadataResponse><result>'
            + mdo(new List<String>{ 'ApexClass', 'classes', 'cls' }, false) + mdo(new List<String>{ 'LightningComponentBundle', 'lwc', '' }, false)
            + mdo(new List<String>{ 'CustomObject', 'objects', 'object' }, false) + mdo(new List<String>{ 'Report', 'reports', 'report' }, true)
            + mdo(new List<String>{ 'CaseSettings', 'settings', 'settings' }, false) + mdo(new List<String>{ 'AccountSettings', 'settings', 'settings' }, false)
            + mdo(new List<String>{ 'Territory2', 'territory2Models', 'territory2' }, false) + mdo(new List<String>{ 'Territory2Model', 'territory2Models', 'territory2Model' }, false)
            + mdo(new List<String>{ 'Territory2Type', 'territory2Types', 'territory2Type' }, false) + mdo(new List<String>{ 'Queue', 'queues', 'queue' }, false)
            + mdo(new List<String>{ 'ExperienceBundle', 'experiences', 'site' }, false) + mdo(new List<String>{ 'CustomMetadata', 'customMetadata', 'md' }, false)
            + mdo(new List<String>{ 'CustomLabels', 'labels', 'labels' }, false) + mdo(new List<String>{ 'Document', 'documents', '' }, true)
            + mdo(new List<String>{ 'ObjectTerritory2AssignmentRule', 'objectTerritory2AssignmentRules', 'objectTerritory2AssignmentRule' }, false)
            + '<organizationNamespace>' + ns + '</organizationNamespace></result></describeMetadataResponse>';
    }

    private static Dom.XmlNode describeResult() {
        Dom.Document doc = new Dom.Document();
        doc.load(SOAP_HEAD + describeBody('') + SOAP_TAIL);
        Dom.XmlNode body = doc.getRootElement().getChildElements()[0];
        return body.getChildElements()[0].getChildElements()[0];
    }

    // A tree answer; entries are path, type, sha.
    private static String tree(List<List<String>> entries) {
        List<String> rows = new List<String>();
        for (List<String> e : entries) {
            rows.add('{"path":"' + e[0] + '","mode":"040000","type":"' + e[1] + '","sha":"' + e[2] + '"}');
        }
        return '{"sha":"' + SHA_SIT + '","tree":[' + String.join(rows, ',') + '],"truncated":false}';
    }

    private static List<String> entry(String path, String type, String sha) {
        return new List<String>{ path, type, sha };
    }

    // The sit branch (source path force-app/main/default is three levels down in RlyReleaseTestData; here the
    // connection's source path is blank) with queues, settings and a territory model.
    private static RlyHttpMock branchMock(String ns) {
        return new RlyHttpMock()
            .match('POST', '/services/Soap/m/').reply(200, SOAP_HEAD + describeBody(ns) + SOAP_TAIL)
            .match('GET', '/git/trees/sit').reply(200, tree(new List<List<String>>{ entry('queues', 'tree', SHA_QUEUES),
                entry('territory2Models', 'tree', SHA_MODELS), entry('settings', 'tree', SHA_SETTINGS), entry('notes', 'tree', 'f'.repeat(40)) }))
            .match('GET', '/git/trees/' + SHA_MODELS).reply(200, tree(new List<List<String>>{ entry('Sales_2027', 'tree', SHA_MODEL) }))
            .match('GET', '/git/trees/' + SHA_QUEUES + '?recursive=1').reply(200, tree(new List<List<String>>{
                entry('Support_Tier_2.queue-meta.xml', 'blob', '1'.repeat(40)), entry('ns__Partner.queue-meta.xml', 'blob', '2'.repeat(40)) }))
            .match('GET', '/git/trees/' + SHA_SETTINGS + '?recursive=1').reply(200, tree(new List<List<String>>{
                entry('Case.settings-meta.xml', 'blob', '3'.repeat(40)) }));
    }

    private static void blankSourcePath() {
        RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
        conn.Source_Path__c = null;
        update conn;
        RlyReleaseStore.forgetGit();
    }

    @IsTest
    static void describeGivesARuleForEveryFolder() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Map<String, RlyPathRules.Rule> rules = RlyPathRules.byDir(RlyPathRules.fromDescribe(describeResult()));
            Map<String, RlyPathRules.Rule> merged = RlyPathRules.byDir(new List<RlyPathRules.Rule>(rules.values()));
            Test.stopTest();
            System.assertEquals('ApexClass', rules.get('classes').type, 'Plain type');
            System.assertEquals(RlyPathRules.BUNDLE, rules.get('lwc').kind, 'No suffix: a folder per component');
            System.assertEquals(RlyPathRules.FOLDERED, rules.get('reports').kind, 'In folders');
            System.assertEquals('CaseSettings', rules.get('settings').type, 'The first type of a folder wins');
            System.assertEquals(RlyPathRules.OBJECTS, rules.get('objects').kind, 'Objects');
            System.assert(!rules.containsKey('documents'), 'Documents are left out (their names keep the extension)');
            System.assert(merged.containsKey('territory2Types'), 'Territory types');
        }
    }

    @IsTest
    static void pathsOfEveryKindMapToTheirComponents() {
        System.runAs(RlyTestData.admin()) {
            List<RlyPathRules.Rule> described = RlyPathRules.fromDescribe(describeResult());
            Map<String, RlyPathRules.Rule> rules = RlyPathRules.byDir(RlyPathRules.checked(described));
            // The fixed rules win for objects and territory models.
            Map<String, RlyPathRules.Rule> everyRule = new Map<String, RlyPathRules.Rule>(rules);
            everyRule.putAll(RlyPathRules.byDir(null));
            Map<String, String> expected = new Map<String, String>{
                'main/default/classes/AccountService.cls' => 'ApexClass:AccountService',
                'classes/AccountService.cls-meta.xml' => 'ApexClass:AccountService',
                'lwc/invoiceCard/invoiceCard.js' => 'LightningComponentBundle:invoiceCard',
                'objects/Invoice__c/compactLayouts/Mobile.compactLayout-meta.xml' => 'CompactLayout:Invoice__c.Mobile',
                'objects/Account/webLinks/Map.webLink-meta.xml' => 'WebLink:Account.Map',
                'objects/Invoice__c/fieldSets/Summary.fieldSet-meta.xml' => 'FieldSet:Invoice__c.Summary',
                'reports/Sales/Q1/Pipeline.report-meta.xml' => 'Report:Sales/Q1/Pipeline',
                'settings/Case.settings-meta.xml' => 'CaseSettings:Case',
                'territory2Models/Sales_2027/Sales_2027.territory2Model-meta.xml' => 'Territory2Model:Sales_2027',
                'territory2Models/Sales_2027/territories/West.territory2-meta.xml' => 'Territory2:Sales_2027.West',
                'territory2Models/Sales_2027/rules/Big_Accounts.territory2Rule-meta.xml' => 'Territory2Rule:Sales_2027.Big_Accounts',
                'territory2Types/Region.territory2Type-meta.xml' => 'Territory2Type:Region',
                'objectTerritory2AssignmentRules/Account.Assign.objectTerritory2AssignmentRule-meta.xml' => 'ObjectTerritory2AssignmentRule:Account.Assign',
                'experiences/Help1.site-meta.xml' => 'ExperienceBundle:Help1',
                'customMetadata/Rate.Standard.md-meta.xml' => 'CustomMetadata:Rate.Standard',
                'queues/Support_Tier_2.queue-meta.xml' => 'Queue:Support_Tier_2'
            };
            List<String> nothing = new List<String>{ 'reports/Sales.reportFolder-meta.xml', 'territory2Models/Sales_2027/notes.txt',
                'objects/Invoice__c/other/x.xml', 'documents/Shared/logo.png', 'readme.md' };
            Test.startTest();
            Map<String, String> got = new Map<String, String>();
            for (String p : expected.keySet()) {
                got.put(p, RlyDeletionPaths.keyOf(p, everyRule));
            }
            List<String> none = new List<String>();
            for (String p : nothing) {
                if (RlyDeletionPaths.keyOf(p, everyRule) != null) {
                    none.add(p);
                }
            }
            Test.stopTest();
            for (String p : expected.keySet()) {
                System.assertEquals(expected.get(p), got.get(p), 'Mapped: ' + p);
            }
            System.assert(none.isEmpty(), 'Not components: ' + none);
        }
    }

    @IsTest
    static void rulesFromThePageAreChecked() {
        System.runAs(RlyTestData.admin()) {
            RlyPathRules.Rule bad = new RlyPathRules.Rule();
            bad.dir = '../classes';
            bad.type = 'ApexClass';
            bad.kind = RlyPathRules.FILE;
            List<String> refused = new List<String>();
            Test.startTest();
            for (List<RlyPathRules.Rule> given : new List<List<RlyPathRules.Rule>>{ new List<RlyPathRules.Rule>{ bad }, new List<RlyPathRules.Rule>{ null } }) {
                try {
                    RlyPathRules.checked(given);
                } catch (RlyReleaseException e) {
                    refused.add(e.getMessage());
                }
            }
            List<RlyPathRules.Rule> fallback = RlyPathRules.checked(null);
            Test.stopTest();
            System.assertEquals(2, refused.size(), 'A path and a missing rule are refused');
            System.assert(refused[0].contains('isn\'t valid'), 'Says why: ' + refused[0]);
            System.assert(RlyPathRules.byDir(fallback).containsKey('classes'), 'No rules: the fixed ones');
        }
    }

    @IsTest
    static void whatADeployCantDelete() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            String standardObject = RlyDeletable.whyNot('CustomObject', 'Account');
            String standardField = RlyDeletable.whyNot('CustomField', 'Account.Industry');
            String settings = RlyDeletable.whyNot('CaseSettings', 'Case');
            String valueSet = RlyDeletable.whyNot('StandardValueSet', 'CaseOrigin');
            String admin = RlyDeletable.whyNot('Profile', 'Admin');
            String encoded = RlyDeletable.whyNot('Profile', 'Minimum Access %2D Salesforce');
            String labels = RlyDeletable.whyNot('CustomLabels', 'CustomLabels');
            String workflow = RlyDeletable.whyNot('Workflow', 'Case');
            Test.stopTest();
            System.assertEquals(RlyDeletable.STANDARD, standardObject, 'Standard object');
            System.assertEquals(RlyDeletable.STANDARD, standardField, 'Standard field');
            System.assertEquals(RlyDeletable.SETTINGS, settings, 'Settings');
            System.assert(valueSet.contains('inactive'), 'Value sets: ' + valueSet);
            System.assert(admin.contains('standard profiles'), 'Standard profile: ' + admin);
            System.assert(encoded != null, 'An encoded standard profile name too');
            System.assert(labels.contains('one file'), 'Labels: ' + labels);
            System.assert(workflow.contains('one file'), 'Workflow: ' + workflow);
            System.assertEquals(null, RlyDeletable.whyNot('CustomField', 'Account.Region__c'), 'A custom field on a standard object');
            System.assertEquals(null, RlyDeletable.whyNot('Profile', 'Custom%3A Sales Profile'), 'A custom profile');
            System.assertEquals(null, RlyDeletable.whyNot('Queue', 'Support_Tier_2'), 'Queues can be deleted');
            System.assertEquals(null, RlyDeletable.whyNot('Territory2Rule', 'Sales_2027.Big_Accounts'), 'Territory rules can be deleted');
        }
    }

    @IsTest
    static void managedPackagesAreToldApart() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            String managedClass = RlyDeletable.managedReason('ns__Util', '');
            String managedObject = RlyDeletable.managedReason('ns__Claim__c', '');
            String managedField = RlyDeletable.managedReason('Account.ns__Score__c', '');
            String onManagedObject = RlyDeletable.managedReason('ns__Claim__c.Note__c', '');
            String ownNamespace = RlyDeletable.managedReason('acme__Claim__c', 'acme');
            List<RlyDeletable.Blocked> blocked = RlyDeletable.blockedOf(new List<String>{ 'Queue:ns__Partner', 'Queue:Support',
                'CaseSettings:Case', 'Layout:Invoice__c-Invoice Layout' }, '');
            Test.stopTest();
            System.assertEquals(RlyDeletable.MANAGED, managedClass, 'ns__ class');
            System.assertEquals(RlyDeletable.MANAGED, managedObject, 'ns__ object');
            System.assertEquals(RlyDeletable.MANAGED, managedField, 'ns__ field on a standard object');
            System.assertEquals(RlyDeletable.MANAGED, onManagedObject, 'A field of a managed object');
            System.assertEquals(null, ownNamespace, 'The org\'s own namespace is its own');
            System.assertEquals(null, RlyDeletable.managedReason('Invoice__c.Total__c', ''), 'Custom names');
            System.assertEquals(null, RlyDeletable.managedReason('Rate__mdt', ''), 'Suffixes aren\'t namespaces');
            System.assertEquals(2, blocked.size(), 'The managed queue and the settings');
            System.assertEquals(RlyDeletable.MANAGED, blocked[0].reason, 'Managed first');
            System.assertEquals(RlyDeletable.SETTINGS, blocked[1].reason, 'Then settings');
        }
    }

    @IsTest
    static void raisingRefusesWhatADeployCantDelete() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = dev.Id;
            req.title = 'Remove settings';
            req.items = new List<RlyRaiseService.Item>();
            req.deletions = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('CaseSettings', 'Case') };
            req.testClasses = new List<String>();
            String refused;
            Test.startTest();
            try {
                RlyDeletionRules.deletions(req, dev);
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            req.deletions = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Queue', 'Support_Tier_2') };
            List<String> ok = RlyDeletionRules.deletions(req, dev);
            Test.stopTest();
            System.assertEquals('CaseSettings Case can\'t be deleted by a release: ' + RlyDeletable.SETTINGS, refused, 'Refused with why');
            System.assertEquals(new List<String>{ 'Queue:Support_Tier_2' }, ok, 'A queue can be deleted');
        }
    }

    @IsTest
    static void branchPlanReadsTheTargetsBranch() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            blankSourcePath();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, branchMock(''));
            Test.startTest();
            RlyDeletionPlan.Plan plan = RlyChangePartsController.branchPlan(devId, null);
            RlyDeletionPlan.Part queues;
            for (RlyDeletionPlan.Part p : plan.parts) {
                queues = p.label == 'queues' ? p : queues;
            }
            queues.rules = plan.rules;
            queues.namespace = plan.namespace;
            RlyDeletionPlan.PartResult r = RlyChangePartsController.deletionPart(devId, JSON.serialize(queues));
            String wrongBranch;
            try {
                RlyChangePartsController.branchPlan(devId, 'main-nope');
            } catch (AuraHandledException e) {
                wrongBranch = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('sit', plan.branch, 'The first stage\'s branch');
            Set<String> labels = new Set<String>();
            for (RlyDeletionPlan.Part p : plan.parts) {
                labels.add(p.label);
            }
            System.assert(labels.contains('queues') && labels.contains('settings') && labels.contains('Territory model Sales_2027'),
                'Every component folder, territory models by model: ' + labels);
            System.assert(!labels.contains('notes'), 'Other folders are left out');
            System.assert(!plan.rules.isEmpty(), 'The rules go to the page');
            System.assertEquals(new List<String>{ 'Queue:Support_Tier_2', 'Queue:ns__Partner' }, r.keys, 'Both queues are on the branch');
            System.assertEquals(1, r.blocked.size(), 'The managed queue can\'t be deleted');
            System.assertEquals('Queue:ns__Partner', r.blocked[0].key, 'Which one');
            System.assert(wrongBranch != null, 'Only a route branch can be read');
        }
    }
}
