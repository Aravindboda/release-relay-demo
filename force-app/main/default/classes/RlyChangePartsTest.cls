/**
 * @description Tests for New Release step 2 in parts (RlyChangePartsController, RlyChangePages, RlyFieldPages,
 * RlyDeletionPlan, RlyDeletionWalk, RlyDeletionPresence, RlyGitTree, RlyGitTreeReader, RlyMetadataList): listMetadata
 * read by scanning, Git trees read by sha in parts, cursors for source tracking, folders and custom fields, the Tooling
 * fallback for custom fields and the checks on what the page sends. The org and GitHub answer through RlyHttpMock or
 * RlyMetadataMock; nothing depends on org data. Every test runs through System.runAs as an active System Administrator.
 */
@IsTest
private class RlyChangePartsTest {

    private static final String SHA_FORCE = 'a'.repeat(40);
    private static final String SHA_MAIN = 'b'.repeat(40);
    private static final String SHA_DEFAULT = 'c'.repeat(40);
    private static final String SHA_CLASSES = 'd'.repeat(40);
    private static final String SHA_OBJECTS = 'e'.repeat(40);
    private static final String SHA_LABELS = 'f'.repeat(40);
    private static final String SHA_INVOICE = '1'.repeat(40);
    private static final String FIELD_CURSOR = '/services/data/v63.0/tooling/query/01gXX0000000001-2000';
    private static final String RECENT = '2026-10-30T10:00:00.000Z';

    // A tree answer; entries are path, type, sha (keys in an unusual order on purpose).
    private static String tree(List<List<String>> entries, Boolean truncated) {
        List<String> rows = new List<String>();
        for (List<String> e : entries) {
            rows.add('{"sha":"' + e[2] + '","type":"' + e[1] + '","mode":"040000","path":"' + e[0] + '","url":"https://x"}');
        }
        return '{"sha":"' + SHA_FORCE + '","url":"https://x","tree":[' + String.join(rows, ',') + '],"truncated":' + truncated + '}';
    }

    private static List<String> entry(String path, String type, String sha) {
        return new List<String>{ path, type, sha };
    }

    // dev1 → force-app → main → default: classes, objects (16 objects), labels (not a component folder).
    private static RlyHttpMock gitMock() {
        List<List<String>> objects = new List<List<String>>();
        for (Integer i = 1; i <= 16; i++) {
            objects.add(entry('Obj' + String.valueOf(i).leftPad(2, '0') + '__c', 'tree', String.valueOf(i).leftPad(40, '9')));
        }
        return new RlyHttpMock()
            .match('GET', '/git/trees/' + SHA_CLASSES + '?recursive=1').reply(200, tree(new List<List<String>>{
                entry('Old.cls', 'blob', '2'.repeat(40)), entry('Old.cls-meta.xml', 'blob', '3'.repeat(40)), entry('Kept.cls', 'blob', '4'.repeat(40)) }, false))
            .match('GET', '/git/trees/' + SHA_INVOICE + '?recursive=1').reply(200, tree(new List<List<String>>{
                entry('Invoice__c.object-meta.xml', 'blob', '5'.repeat(40)), entry('fields', 'tree', '6'.repeat(40)),
                entry('fields/Total__c.field-meta.xml', 'blob', '7'.repeat(40)) }, true))
            .match('GET', '/git/trees/sit').reply(200, tree(new List<List<String>>{ entry('force-app', 'tree', SHA_FORCE), entry('README.md', 'blob', '8'.repeat(40)) }, false))
            .match('GET', '/git/trees/' + SHA_FORCE).reply(200, tree(new List<List<String>>{ entry('main', 'tree', SHA_MAIN) }, false))
            .match('GET', '/git/trees/' + SHA_MAIN).reply(200, tree(new List<List<String>>{ entry('default', 'tree', SHA_DEFAULT) }, false))
            .match('GET', '/git/trees/' + SHA_DEFAULT).reply(200, tree(new List<List<String>>{ entry('classes', 'tree', SHA_CLASSES),
                entry('objects', 'tree', SHA_OBJECTS), entry('labels', 'tree', SHA_LABELS) }, false))
            .match('GET', '/git/trees/' + SHA_OBJECTS).reply(200, tree(objects, false));
    }

    @IsTest
    static void listMetadataIsReadByScanning() {
        System.runAs(RlyTestData.admin()) {
            String body = '<?xml version="1.0"?><soapenv:Envelope><soapenv:Body><listMetadataResponse>'
                + '<result xsi:type="FileProperties"><fullName>Account.Tom &amp; Jerry__c</fullName><lastModifiedByName>Dev One</lastModifiedByName>'
                + '<lastModifiedDate>2026-10-30T10:00:00.000Z</lastModifiedDate><manageableState>unmanaged</manageableState>'
                + '<namespacePrefix xsi:nil="true"/><type>CustomField</type></result>'
                + '<results><fullName>not a result</fullName></results>'
                + '<result><fullName></fullName><type>CustomField</type></result>'
                + '</listMetadataResponse></soapenv:Body></soapenv:Envelope>';
            List<RlyMetadata.FileProp> props = RlyMetadataList.read('DEV1', 200, body);
            String fault;
            try {
                RlyMetadataList.read('DEV1', 500, '<soapenv:Fault><faultstring>INVALID_TYPE: &apos;Nope&apos;</faultstring></soapenv:Fault>');
            } catch (RlyMetadata.MetadataException e) {
                fault = e.getMessage();
            }
            String garbage;
            try {
                RlyMetadataList.read('DEV1', 502, null);
            } catch (RlyMetadata.MetadataException e) {
                garbage = e.getMessage();
            }
            System.assertEquals(1, props.size(), 'One named result; <results> and blank names left out');
            System.assertEquals('Account.Tom & Jerry__c', props[0].fullName, 'XML escapes undone');
            System.assertEquals(null, props[0].namespacePrefix, 'xsi:nil reads as null');
            System.assertEquals('Dev One', props[0].lastModifiedByName, 'Changed by');
            System.assertNotEquals(null, props[0].lastModifiedDate, 'Date read');
            System.assertEquals('DEV1: listMetadata failed: INVALID_TYPE: \'Nope\'', fault, 'The org\'s fault');
            System.assert(garbage.contains('HTTP 502'), 'Not an answer: ' + garbage);
        }
    }

    @IsTest
    static void treesAreReadByScanning() {
        System.runAs(RlyTestData.admin()) {
            RlyGitTree.Tree t = RlyGitTree.read('{"sha":"x","tree":[{"path":"a \\"quoted\\".cls","mode":"100644","type":"blob","sha":"s1"},'
                + '{"type":"tree","sha":"s2","path":"lwc"},{"sha":"s3", "path" : "lwc/card/card.js" ,"type":"blob"}],"truncated": true}');
            RlyGitTree.Tree none = RlyGitTree.read('{"message":"Not Found"}');
            System.assertEquals(3, t.entries.size(), 'Every entry');
            System.assertEquals('a "quoted".cls', t.entries[0].path, 'Escapes undone');
            System.assertEquals('tree', t.entries[1].type, 'Type before path');
            System.assertEquals('s2', t.entries[1].sha, 'Sha before path');
            System.assertEquals('lwc/card/card.js', t.entries[2].path, 'Spaces around the colon');
            System.assertEquals(true, t.truncated, 'Truncated flag');
            System.assertEquals(new List<String>{ 'lwc/card/card.js' }, RlyGitTree.filesUnder(t, 'lwc/'), 'Files under a folder');
            System.assert(none.entries.isEmpty() && !none.truncated, 'No tree: nothing');
        }
    }

    @IsTest
    static void deletionPlanSplitsTheBranch() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            Test.setMock(HttpCalloutMock.class, gitMock());
            Test.startTest();
            RlyDeletionPlan.Plan plan = RlyChangePartsController.branchPlan(devId, null);
            Test.stopTest();
            System.assertEquals('sit', plan.branch, 'The first stage\'s branch');
            System.assertEquals(3, plan.parts.size(), 'classes, then objects in two groups; labels left out');
            System.assertEquals('classes', plan.parts[0].label, 'Folder part');
            System.assertEquals('classes/', plan.parts[0].folders[0].prefix, 'Path below the source path');
            System.assertEquals(SHA_CLASSES, plan.parts[0].folders[0].sha, 'By its tree sha');
            System.assertEquals(RlyDeletionPlan.OBJECTS_PER_PART, plan.parts[1].folders.size(), 'A full group of objects');
            System.assertEquals('Objects Obj01__c – Obj15__c', plan.parts[1].label, 'Group label');
            System.assertEquals('Object Obj16__c', plan.parts[2].label, 'The last object alone');
            System.assertEquals('p1', plan.parts[0].id, 'Numbered');
            System.assertEquals(false, plan.truncated, 'Nothing cut short');
        }
    }

    @IsTest
    static void deletionPartReadsItsFolders() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            Test.setMock(HttpCalloutMock.class, gitMock());
            RlyDeletionPlan.Part part = RlyDeletionPlan.newPart('mixed', new List<RlyDeletionPlan.Folder>{
                RlyDeletionPlan.folderAt('classes/', SHA_CLASSES), RlyDeletionPlan.folderAt('objects/Invoice__c/', SHA_INVOICE) });
            Test.startTest();
            RlyDeletionPlan.PartResult r = RlyChangePartsController.deletionPart(devId, JSON.serialize(part));
            List<String> refused = new List<String>();
            for (String bad : new List<String>{ '', '{"folders":[{"prefix":"../x/","sha":"' + SHA_CLASSES + '"}]}',
                    '{"folders":[{"prefix":"classes/","sha":"main"}]}', '{"folders":[]}' }) {
                try {
                    RlyChangePartsController.deletionPart(devId, bad);
                } catch (AuraHandledException e) {
                    refused.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assertEquals(new List<String>{ 'ApexClass:Old', 'ApexClass:Kept', 'CustomObject:Invoice__c', 'CustomField:Invoice__c.Total__c' },
                r.keys, 'Each component once, from both folders');
            System.assertEquals(true, r.truncated, 'GitHub cut a folder short');
            System.assertEquals(4, refused.size(), 'Blank, a path going up, a sha that isn\'t one and no folders are refused');
            System.assert(refused[1].contains('isn\'t valid'), 'Says why: ' + refused[1]);
        }
    }

    @IsTest
    static void deletionPlanNeedsGitHubAndTheSourcePath() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/git/trees/sit').reply(200, tree(new List<List<String>>{ entry('src', 'tree', SHA_MAIN) }, true)));
            Test.startTest();
            RlyDeletionPlan.Plan empty = RlyChangePartsController.branchPlan(devId, null);
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            conn.Provider__c = 'Bitbucket';
            update conn;
            RlyReleaseStore.forgetGit();
            String gitLab;
            try {
                RlyChangePartsController.branchPlan(devId, null);
            } catch (AuraHandledException e) {
                gitLab = e.getMessage();
            }
            Test.stopTest();
            System.assert(empty.parts.isEmpty(), 'No source path on the branch: no parts');
            System.assertEquals(true, empty.truncated, 'Cut short noted');
            System.assert(gitLab.contains('isn\'t available for Bitbucket'), 'Other providers: ' + gitLab);
        }
    }

    @IsTest
    static void presenceListsOneTypeInTheOrg() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyMetadataMock().add('ApexClass', 'Kept', RECENT).addManaged('ApexClass', 'pkg__Helper', RECENT));
            Test.startTest();
            RlyDeletionPresence.Presence p = RlyChangePartsController.presentNames(devId, 'ApexClass');
            String bad;
            try {
                RlyChangePartsController.presentNames(devId, 'Apex Class');
            } catch (AuraHandledException e) {
                bad = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(new List<String>{ 'kept', 'pkg__helper' }, p.names, 'Every one, managed too, lower case');
            System.assertEquals('ApexClass', p.type, 'Its type');
            System.assert(bad.contains('isn\'t a metadata type'), 'Type checked: ' + bad);
        }
    }

    @IsTest
    static void customFieldsComeAPageAtATime() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            String objectId = RlyTestData.fakeId('01I', 1);
            String lostId = RlyTestData.fakeId('01I', 9);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', FIELD_CURSOR).reply(200, '{"done":true,"records":[{"DeveloperName":"Region","NamespacePrefix":null,'
                    + '"TableEnumOrId":"Account","EntityDefinition":{"QualifiedApiName":"Account"}}]}')
                .match('GET', 'EntityDefinition.QualifiedApiName').reply(400, '[{"errorCode":"INVALID_FIELD"}]')
                .match('GET', 'FROM CustomObject').reply(200, '{"records":[{"Id":"' + objectId + 'AAA","DeveloperName":"Invoice","NamespacePrefix":null}]}')
                .match('GET', 'FROM CustomField').reply(200, '{"done":false,"nextRecordsUrl":"' + FIELD_CURSOR + '","records":['
                    + '{"DeveloperName":"Total","NamespacePrefix":null,"TableEnumOrId":"' + objectId + '"},'
                    + '{"DeveloperName":"Score","NamespacePrefix":"pkg","TableEnumOrId":"Contact"},'
                    + '{"DeveloperName":"Lost","NamespacePrefix":null,"TableEnumOrId":"' + lostId + '"}]}'));
            Test.startTest();
            RlyDeletionPresence.Presence page1 = RlyChangePartsController.presentFields(devId, null);
            RlyDeletionPresence.Presence page2 = RlyChangePartsController.presentFields(devId, page1.nextCursor);
            String foreign;
            try {
                RlyChangePartsController.presentFields(devId, '/services/apexrest/rly/archive');
            } catch (AuraHandledException e) {
                foreign = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(new List<String>{ 'invoice__c.total__c', 'contact.pkg__score__c' }, page1.names,
                'Custom object named through CustomObject (asked again without EntityDefinition); a field whose object isn\'t found is left out');
            System.assertEquals(FIELD_CURSOR, page1.nextCursor, 'Cursor to the next page');
            System.assertEquals(new List<String>{ 'account.region__c' }, page2.names, 'Next page, object from EntityDefinition');
            System.assertEquals(null, page2.nextCursor, 'Last page');
            System.assert(foreign.contains('isn\'t valid'), 'Only the org\'s query cursors: ' + foreign);
        }
    }

    @IsTest
    static void fieldChangesComeAPageAtATime() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            String userId = RlyTestData.fakeId('005', 3);
            RlyHttpMock m = new RlyHttpMock()
                .match('GET', 'FROM User').reply(200, '{"records":[{"Id":"' + userId + '","Name":"Dev One"}]}')
                .match('GET', 'FROM CustomField').reply(200, '{"done":true,"records":[{"DeveloperName":"Region","NamespacePrefix":null,'
                    + '"TableEnumOrId":"Account","EntityDefinition":{"QualifiedApiName":"Account"},"LastModifiedDate":"2026-10-30T10:00:00.000+0000",'
                    + '"LastModifiedById":"' + userId + '"}]}');
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            RlyChangePages.ChangePage p = RlyChangePartsController.listFieldPage(devId, '2026-10-01T00:00:00Z', null);
            Test.stopTest();
            String query = EncodingUtil.urlDecode(m.calls[0], 'UTF-8');
            System.assertEquals(1, p.changes.size(), 'One field');
            System.assertEquals('CustomField:Account.Region__c', p.changes[0].key, 'Object.Field__c');
            System.assertEquals('Dev One', p.changes[0].modifiedBy, 'Changed by');
            System.assertEquals(false, p.changes[0].standard, 'A custom field');
            System.assert(query.contains('NamespacePrefix = null') && query.contains('LastModifiedDate >= 2026-10-01T00:00:00Z'),
                'Unmanaged, since the date: ' + query);
            System.assertEquals(null, p.nextCursor, 'Last page');
        }
    }

    @IsTest
    static void trackedChangesComeAPageAtATime() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            String cursor = '/services/data/v63.0/tooling/query/01gYY0000000002-2000';
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', cursor).reply(200, '{"done":true,"records":[{"MemberName":"OldPage","MemberType":"ApexPage","IsNameObsolete":true,'
                    + '"LastModifiedDate":"2026-10-28T10:00:00.000+0000","LastModifiedById":null}]}')
                .match('GET', 'FROM SourceMember').reply(200, '{"done":false,"nextRecordsUrl":"' + cursor + '","records":[{"MemberName":"AccountService",'
                    + '"MemberType":"ApexClass","IsNameObsolete":false,"LastModifiedDate":"2026-10-30T10:00:00.000+0000","LastModifiedById":null}]}'));
            Test.startTest();
            RlyChangePages.ChangePage page1 = RlyChangePartsController.listTrackedPage(devId, null, null);
            RlyChangePages.ChangePage page2 = RlyChangePartsController.listTrackedPage(devId, null, page1.nextCursor);
            Test.stopTest();
            System.assertEquals('ApexClass:AccountService', page1.changes[0].key, 'First page');
            System.assertEquals(cursor, page1.nextCursor, 'Cursor to the rest');
            System.assertEquals(true, page2.changes[0].deleted, 'Second page: a deletion');
            System.assertEquals(null, page2.nextCursor, 'Last page');
        }
    }

    @IsTest
    static void foldersComeInRuns() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyMetadataMock mock = new RlyMetadataMock();
            for (Integer i = 1; i <= RlyChangePages.FOLDERS_PER_CALL + 2; i++) {
                mock.add('ReportFolder', 'Folder' + i, RECENT);
            }
            mock.add('Report/Folder1', 'Folder1/Pipeline', RECENT).add('Report/Folder32', 'Folder32/Wins', RECENT);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyChangePages.ChangePage page1 = RlyChangePartsController.listFolderPage(devId, 'Report', JSON.serialize(new Map<String, Object>{ 'sinceIso' => '' }));
            RlyChangePages.ChangePage second = RlyChangePartsController.listFolderPage(devId, 'Report',
                JSON.serialize(new Map<String, Object>{ 'cursor' => page1.nextCursor }));
            List<String> refused = new List<String>();
            for (String bad : new List<String>{ '{"cursor":"x"}', '{"cursor":"' + FIELD_CURSOR + '"}' }) {
                try {
                    RlyChangePartsController.listFolderPage(devId, 'Report', bad);
                } catch (AuraHandledException e) {
                    refused.add(e.getMessage());
                }
            }
            try {
                RlyChangePartsController.listFolderPage(devId, 'ApexClass', null);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            Test.stopTest();
            Set<String> firstKeys = new Set<String>();
            for (RlyChangeFinder.Change c : page1.changes) {
                firstKeys.add(c.key);
            }
            System.assert(firstKeys.contains('ReportFolder:Folder1') && firstKeys.contains('Report:Folder1/Pipeline'), 'Folders and their reports');
            System.assert(!firstKeys.contains('Report:Folder32/Wins'), 'Folder 32 waits for the next run');
            System.assertEquals(String.valueOf(RlyChangePages.FOLDERS_PER_CALL), page1.nextCursor, 'Next folder\'s position');
            System.assertEquals(1, second.changes.size(), 'Only the reports of folders 31 and 32, no folders again');
            System.assertEquals('Report:Folder32/Wins', second.changes[0].key, 'Nothing skipped');
            System.assertEquals(null, second.nextCursor, 'Last run');
            System.assertEquals(3, refused.size(), 'Bad positions and a type without folders are refused');
            System.assert(refused[2].contains('isn\'t a folder type'), 'Folder types only: ' + refused[2]);
        }
    }

    @IsTest
    static void onlyDeveloperOrgsAreRead() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Id stageId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
            List<String> refused = new List<String>();
            try {
                RlyChangePartsController.listTrackedPage(stageId, null, null);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            try {
                RlyChangePartsController.listFieldPage(stageId, 'not a date', null);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            System.assertEquals(2, refused.size(), 'Stage orgs aren\'t sources');
            System.assertEquals(RlyRaiseRoute.STAGE_RETIRED, refused[0], 'Says why');
        }
    }
}
