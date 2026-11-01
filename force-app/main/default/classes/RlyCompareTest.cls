/**
 * @description Tests for Compare on Review (RlyCompareController, RlyCompareRun, RlyCompareZip, RlyCompareFiles).
 * DEV1's retrieve answers with a zip built here (Compression.ZipWriter); the sit branch answers through RlyHttpMock.
 * Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyCompareTest {

    private static final String SOAP_HEAD = '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope '
        + 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body>';
    private static final String SOAP_TAIL = '</soapenv:Body></soapenv:Envelope>';
    private static final String RETRIEVE_ID = RlyTestData.fakeId('09S', 7);
    private static final String CLASS_TEXT = 'public with sharing class AccountService {\n    // v2\n}';
    private static final String META_TEXT = '<?xml version="1.0" encoding="UTF-8"?>\n<ApexClass/>';
    private static final String FLOW_TEXT = '<?xml version="1.0" encoding="UTF-8"?>\n<Flow/>';
    private static final String RAW = '/contents/force-app/main/default/';

    // DEV1's copy: a class with its meta file, an LWC bundle, a flow, a static resource (not compared) and package.xml.
    private static String zipBase64() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('package.xml', Blob.valueOf('<Package/>'));
        writer.addEntry('classes/AccountService.cls', Blob.valueOf(CLASS_TEXT));
        writer.addEntry('classes/AccountService.cls-meta.xml', Blob.valueOf(META_TEXT));
        writer.addEntry('lwc/accountCard/accountCard.html', Blob.valueOf('<template></template>'));
        writer.addEntry('lwc/accountCard/accountCard.js', Blob.valueOf('export default class AccountCard {}'));
        writer.addEntry('flows/Welcome.flow', Blob.valueOf(FLOW_TEXT));
        writer.addEntry('staticresources/logo.resource', Blob.valueOf('png'));
        return EncodingUtil.base64Encode(writer.getArchive());
    }

    private static String statusXml(String state) {
        if (state == 'InProgress') {
            return '<checkRetrieveStatusResponse><result><done>false</done><id>' + RETRIEVE_ID + '</id><status>InProgress</status></result></checkRetrieveStatusResponse>';
        }
        if (state == 'Failed') {
            return '<checkRetrieveStatusResponse><result><done>true</done><errorMessage>Session expired</errorMessage><id>' + RETRIEVE_ID
                + '</id><status>Failed</status></result></checkRetrieveStatusResponse>';
        }
        return '<checkRetrieveStatusResponse><result><done>true</done><id>' + RETRIEVE_ID + '</id>'
            + '<messages><fileName>classes/Gone.cls</fileName><problem>Entity of type ApexClass named Gone cannot be found</problem></messages>'
            + '<status>Succeeded</status><success>true</success><zipFile>' + zipBase64() + '</zipFile></result></checkRetrieveStatusResponse>';
    }

    // DEV1's Metadata API and the sit branch: the class changed, its meta file the same, the bundle's js changed and
    // its html new, the flow the same; OldService (deleted) and the oldCard bundle (deleted) are on the branch.
    private static RlyHttpMock mock(String state) {
        return new RlyHttpMock()
            .match('POST', '/services/Soap/m/').ifBodyHas('<met:retrieve>').reply(200, SOAP_HEAD + '<retrieveResponse><result><done>false</done><id>'
                + RETRIEVE_ID + '</id><state>Queued</state></result></retrieveResponse>' + SOAP_TAIL)
            .match('POST', '/services/Soap/m/').reply(200, SOAP_HEAD + statusXml(state) + SOAP_TAIL)
            .match('GET', RAW + 'classes/AccountService.cls-meta.xml?ref=sit').reply(200, META_TEXT)
            .match('GET', RAW + 'classes/AccountService.cls?ref=sit').reply(200, 'public with sharing class AccountService {\n}')
            .match('GET', RAW + 'lwc/accountCard/accountCard.js?ref=sit').reply(200, 'export default class Card {}')
            .match('GET', RAW + 'flows/Welcome.flow-meta.xml?ref=sit').reply(200, FLOW_TEXT)
            .match('GET', RAW + 'classes/OldService.cls?ref=sit').reply(200, 'public class OldService {}')
            .match('GET', RAW + 'lwc/oldCard/oldCard.js?ref=sit').reply(200, 'export default class OldCard {}')
            .match('GET', '/git/trees/sit').reply(200, '{"tree":[{"path":"force-app/main/default/lwc/oldCard/oldCard.js","type":"blob"},'
                + '{"path":"force-app/main/default/lwc/other/other.js","type":"blob"}]}')
            .match('GET', 'FlowDefinition').reply(200, '{"records":[{"Id":"300000000000001AAA","DeveloperName":"Welcome",'
                + '"ActiveVersion":{"VersionNumber":7},"LatestVersion":{"VersionNumber":7,"Status":"Active"}}]}');
    }

    private static Map<String, Object> job(Id devId, String retrieveId) {
        return new Map<String, Object>{
            'retrieveId' => retrieveId, 'sourceOrgId' => devId,
            'keys' => new List<String>{ 'ApexClass:AccountService', 'LightningComponentBundle:accountCard', 'Flow:Welcome',
                'CustomField:Account.Region__c', 'ApexClass:Gone' },
            'deleted' => new List<String>{ 'ApexClass:OldService', 'LightningComponentBundle:oldCard', 'CustomObject:Old__c' }
        };
    }

    private static Map<String, RlyCompareFiles.ComponentDiff> byKey(RlyCompareRun.Result r) {
        Map<String, RlyCompareFiles.ComponentDiff> out = new Map<String, RlyCompareFiles.ComponentDiff>();
        for (RlyCompareFiles.ComponentDiff c : r.components) {
            out.put(c.key, c);
        }
        return out;
    }

    @IsTest
    static void startRetrievesOnlyWhatCompareShows() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock m = mock('Succeeded');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            String startedId = RlyCompareController.startCompare(dev.Id, new List<String>{ 'ApexClass:AccountService', 'CustomField:Account.Region__c' });
            String none = RlyCompareController.startCompare(dev.Id, new List<String>{ 'CustomField:Account.Region__c' });
            Test.stopTest();
            System.assertEquals(RETRIEVE_ID, startedId, 'The retrieve id comes back');
            System.assertEquals(null, none, 'Nothing compare shows: no retrieve');
            String body = m.bodyFor('/services/Soap/m/');
            System.assert(body.contains('AccountService') && !body.contains('Region__c'), 'Only supported types are retrieved');
        }
    }

    @IsTest
    static void checkWaitsForTheRetrieve() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, mock('InProgress'));
            Test.startTest();
            RlyCompareRun.Result r = RlyCompareController.checkCompare(JSON.serialize(job(dev.Id, RETRIEVE_ID)));
            Test.stopTest();
            System.assertEquals(false, r.done, 'Still retrieving');
            System.assert(r.components.isEmpty(), 'No files yet');
            System.assertEquals('SIT', r.targetName, 'Target org named');
        }
    }

    @IsTest
    static void checkComparesEachFile() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, mock('Succeeded'));
            Test.startTest();
            RlyCompareRun.Result r = RlyCompareController.checkCompare(JSON.serialize(job(dev.Id, RETRIEVE_ID)));
            Test.stopTest();
            Map<String, RlyCompareFiles.ComponentDiff> c = byKey(r);
            System.assert(r.done && !r.more, 'Finished in one check');
            System.assertEquals('sit', r.targetBranch, 'First stage branch');
            System.assertEquals(RlyCompareFiles.CHANGED, c.get('ApexClass:AccountService').status, 'Class changed');
            System.assertEquals('classes/AccountService.cls', c.get('ApexClass:AccountService').files[0].path, 'Main file first');
            System.assertEquals(RlyCompareFiles.SAME, c.get('ApexClass:AccountService').files[1].status, 'Meta file the same');
            RlyCompareFiles.ComponentDiff card = c.get('LightningComponentBundle:accountCard');
            System.assertEquals('lwc/accountCard/accountCard.js', card.files[0].path, 'Bundle js first');
            System.assertEquals(RlyCompareFiles.ADDED, card.files[1].status, 'html not on the branch');
            System.assertEquals('flows/Welcome.flow-meta.xml', c.get('Flow:Welcome').files[0].path, 'Flow in source format');
            System.assertEquals(RlyCompareFiles.SAME, c.get('Flow:Welcome').status, 'Flow the same');
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, c.get('CustomField:Account.Region__c').status, 'Field not compared');
            System.assert(c.get('ApexClass:Gone').reason.contains('cannot be found'), 'Retrieve problem shown');
            System.assertEquals(RlyCompareFiles.REMOVED, c.get('ApexClass:OldService').status, 'Deleted class');
            System.assertEquals(RlyCompareFiles.REMOVED, c.get('LightningComponentBundle:oldCard').status, 'Deleted bundle listed from the branch');
            System.assertEquals(1, c.get('LightningComponentBundle:oldCard').files.size(), 'Only its own files');
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, c.get('CustomObject:Old__c').status, 'Object deletion not compared');
        }
    }

    @IsTest
    static void checkLeavesFilesPendingOverTheBudget() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, mock('Succeeded'));
            RlyCompareRun.callBudget = 0;
            Map<String, Object> j = job(dev.Id, null);
            j.put('keys', new List<String>());
            j.put('deleted', new List<String>{ 'ApexClass:OldService', 'ApexClass:Other' });
            Test.startTest();
            RlyCompareRun.Result r = RlyCompareController.checkCompare(JSON.serialize(j));
            RlyCompareRun.callBudget = 50;
            j.put('pendingPaths', new List<String>{ 'classes/OldService.cls', 'classes/Other.cls' });
            RlyCompareRun.Result followed = RlyCompareController.checkCompare(JSON.serialize(j));
            Test.stopTest();
            System.assert(r.more, 'Some files left for the next check');
            System.assertEquals(2, followed.fetched.size(), 'Follow-up reads the paths asked');
            System.assertEquals('public class OldService {}', followed.fetched[0].left, 'Branch copy read');
            System.assertEquals(null, followed.fetched[1].left, 'Not on the branch');
        }
    }

    @IsTest
    static void checkRefusesBadJobs() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            List<String> many = new List<String>();
            for (Integer i = 0; i <= RlyCompareFiles.MAX_COMPONENTS; i++) {
                many.add('ApexClass:C' + i);
            }
            List<Map<String, Object>> bad = new List<Map<String, Object>>();
            for (Integer i = 0; i < 4; i++) {
                bad.add(job(dev.Id, null));
            }
            bad[0].put('keys', many);
            bad[1].put('keys', new List<String>{ 'NoColon' });
            bad[2].put('targetBranch', 'elsewhere');
            bad[3].put('pendingPaths', new List<String>{ '../secret' });
            Integer refused = 0;
            for (Map<String, Object> j : bad) {
                try {
                    RlyCompareController.checkCompare(JSON.serialize(j));
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            try {
                RlyCompareController.startCompare(dev.Id, new List<String>());
            } catch (AuraHandledException e) {
                refused++;
            }
            System.assertEquals(5, refused, 'Each bad request refused before any callout');
        }
    }

    @IsTest
    static void checkReportsAFailedRetrieveAndAnUnsetConnection() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, mock('Failed'));
            String failed;
            Test.startTest();
            try {
                RlyCompareController.checkCompare(JSON.serialize(job(dev.Id, RETRIEVE_ID)));
            } catch (AuraHandledException e) {
                failed = e.getMessage();
            }
            Test.stopTest();
            System.assert(failed.contains('Session expired'), 'Retrieve error shown');
            RLY_Git_Connection__c g = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            g.Status__c = 'Not checked';
            update g;
            String unset;
            try {
                RlyCompareController.checkCompare(JSON.serialize(job(dev.Id, null)));
            } catch (AuraHandledException e) {
                unset = e.getMessage();
            }
            System.assert(unset.contains('Git connection'), 'Connection must be checked');
        }
    }

    @IsTest
    static void zipMarksLargeFiles() {
        System.runAs(RlyTestData.admin()) {
            Compression.ZipWriter writer = new Compression.ZipWriter();
            writer.addEntry('classes/Big.cls', Blob.valueOf('x'.repeat(RlyCompareFiles.MAX_FILE_CHARS + 1)));
            writer.addEntry('lwc/', Blob.valueOf(''));
            Map<String, List<RlyCompareFiles.FileDiff>> files = RlyCompareZip.read(EncodingUtil.base64Encode(writer.getArchive()), 'DEV1');
            RlyCompareFiles.FileDiff big = files.get('apexclass:big')[0];
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, big.status, 'Too large');
            System.assert(big.reason.startsWith(RlyCompareFiles.TOO_LARGE), 'Reason given');
            System.assert(RlyCompareZip.read(null, 'DEV1').isEmpty(), 'No zip, no files');
        }
    }

    @IsTest
    static void zipTooLargeIsRefusedBeforeDecoding() {
        System.runAs(RlyTestData.admin()) {
            String tooBig = 'A'.repeat(RlyCompareZip.MAX_ZIP_CHARS + 1);
            String refusal;
            try {
                RlyCompareZip.read(tooBig, 'DEV1');
            } catch (RlyReleaseException e) {
                refusal = e.getMessage();
            }
            System.assertEquals(RlyCompareZip.TOO_BIG, refusal, 'Compare fewer at a time, instead of running out of heap');
        }
    }

    @IsTest
    static void filesMapBetweenFormats() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('Layout:Account-Account (Sales) Layout', RlyCompareFiles.keyOf('layouts/Account-Account %28Sales%29 Layout.layout'), 'Decoded');
            System.assertEquals('AuraDefinitionBundle:box', RlyCompareFiles.keyOf('aura/box/boxController.js'), 'Aura bundle');
            System.assertEquals(null, RlyCompareFiles.keyOf('objects/Account.object'), 'Objects not compared');
            System.assertEquals(null, RlyCompareFiles.keyOf('classes/.cls'), 'No name');
            System.assertEquals('permissionsets/Ops.permissionset-meta.xml', RlyCompareFiles.sourcePathOf('permissionsets/Ops.permissionset'), 'XML type');
            System.assertEquals(new List<String>{ 'layouts/A.layout-meta.xml' }, RlyCompareFiles.pathsOf('Layout:A'), 'Deleted layout');
            System.assertEquals('aura/box/', RlyCompareFiles.bundleFolder('AuraDefinitionBundle:box'), 'Bundle folder');
            System.assertEquals(RlyCompareFiles.CHANGED, RlyCompareParts.statusOf('a', 'A'), 'Case matters');
            System.assertEquals(RlyCompareFiles.SAME, RlyCompareParts.statusOf('a\r\nb', 'a\nb'), 'Line endings ignored');
            System.assert(RlyCompareFiles.reasonFor('StaticResource').contains('binary'), 'Static resources');
            System.assert(RlyCompareParts.tooLarge('a\nb', 'in DEV1').contains('2 lines in DEV1'), 'Line count');
            RlyCompareFiles.FileDiff ctrl = new RlyCompareFiles.FileDiff();
            ctrl.path = 'aura/box/boxController.js';
            RlyCompareFiles.FileDiff cmp = new RlyCompareFiles.FileDiff();
            cmp.path = 'aura/box/box.cmp';
            List<RlyCompareFiles.FileDiff> ordered = RlyCompareFiles.mainFirst('AuraDefinitionBundle:box', new List<RlyCompareFiles.FileDiff>{ ctrl, cmp });
            System.assertEquals('aura/box/box.cmp', ordered[0].path, 'Aura main file first');
            RlyCompareFiles.ComponentDiff empty = new RlyCompareFiles.ComponentDiff();
            RlyCompareParts.settle(empty);
            System.assertEquals(RlyCompareFiles.UNSUPPORTED, empty.status, 'No files');
        }
    }
}
