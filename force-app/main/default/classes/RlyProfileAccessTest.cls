/**
 * @description Tests for profile access (build 58): the rules (RlyProfileAccessRules), reading an org's profiles and
 * their access (RlyProfileAccessController, RlyProfileAccessReader, RlyProfileAccessRows, RlyProfileAccessLayouts), a
 * release that carries only profile access (raise, the file committed to its branch, its approval contents) and the
 * release page's read. Every test runs as an existing active System Administrator through System.runAs; records
 * are inserted before Test.startTest and callouts come after it.
 */
@IsTest
private class RlyProfileAccessTest {

    private static final String SALES = 'Sales User';
    private static final String CLASS_ID = '01p000000000001AAA';
    private static final String SETTING_ID = '01I000000000001AAA';

    private static RlyProfileAccessRules.Row row(String section, String key, Map<String, String> values) {
        RlyProfileAccessRules.Row r = new RlyProfileAccessRules.Row();
        r.section = section;
        r.key = key;
        r.values = values;
        return r;
    }

    private static RlyProfileAccessRules.ProfileRows profile(String name, List<RlyProfileAccessRules.Row> rows) {
        RlyProfileAccessRules.ProfileRows p = new RlyProfileAccessRules.ProfileRows();
        p.profile = name;
        p.label = name;
        p.rows = rows;
        return p;
    }

    private static String refusal(List<RlyProfileAccessRules.ProfileRows> sent) {
        try {
            RlyProfileAccessRules.checked(sent);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void rulesKeepOnlyValidRowsWithValues() {
        System.runAs(RlyTestData.admin()) {
            List<RlyProfileAccessRules.ProfileRows> sent = new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{
                    row(RlyProfileAccessRules.FIELDS, 'Account.Region__c', new Map<String, String>{ 'readable' => 'true', 'editable' => 'false' }),
                    row(RlyProfileAccessRules.TABS, 'standard-Account', new Map<String, String>{ 'visibility' => 'DefaultOn' }),
                    row(RlyProfileAccessRules.LAYOUTS, 'Order__c.Rush', new Map<String, String>{ 'layout' => 'Order__c-Rush Layout' }),
                    row(RlyProfileAccessRules.OBJECTS, 'Order__c', new Map<String, String>()) }),
                profile('Empty', new List<RlyProfileAccessRules.Row>()) };
            Test.startTest();
            List<RlyProfileAccessRules.ProfileRows> kept = RlyProfileAccessRules.checked(sent);
            String field = RlyProfileAccessRules.toField(kept);
            List<RlyProfileAccessRules.ProfileRows> back = RlyProfileAccessRules.fromField(field);
            Test.stopTest();
            System.assertEquals(1, kept.size(), 'A profile without rows is left out');
            System.assertEquals(3, RlyProfileAccessRules.rowCount(kept), 'A row without values is left out');
            System.assertEquals('false', back[0].rows[0].values.get('editable'), 'Kept as sent');
            System.assertEquals('3 profile access rows', RlyProfileAccessRules.rowWords(3), 'Words');
            System.assertEquals('1 profile access row', RlyProfileAccessRules.rowWords(1), 'One row');
            System.assertEquals(null, RlyProfileAccessRules.toField(new List<RlyProfileAccessRules.ProfileRows>()), 'Nothing to keep');
            System.assertEquals(0, RlyProfileAccessRules.fromField(null).size(), 'Blank field');
            System.assertEquals('tab settings', RlyProfileAccessRules.sectionLabel(RlyProfileAccessRules.TABS), 'Label');
        }
    }

    @IsTest
    static void rulesRefuseWhatThePipelineCantWrite() {
        System.runAs(RlyTestData.admin()) {
            Map<String, String> on = new Map<String, String>{ 'enabled' => 'true' };
            Test.startTest();
            String badProfile = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('../Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.CLASSES, 'OrderService', on) }) });
            String twice = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.CLASSES, 'OrderService', on) }),
                profile('admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.CLASSES, 'OrderService', on) }) });
            String section = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row('loginHours', 'Monday', on) }) });
            String key = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.FIELDS, 'Region__c', on) }) });
            String value = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.CLASSES, 'OrderService',
                    new Map<String, String>{ 'enabled' => 'yes' }) }) });
            String layout = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.LAYOUTS, 'Order__c',
                    new Map<String, String>{ 'layout' => 'Account-Account Layout' }) }) });
            String dupRow = refusal(new List<RlyProfileAccessRules.ProfileRows>{
                profile('Admin', new List<RlyProfileAccessRules.Row>{ row(RlyProfileAccessRules.CLASSES, 'OrderService', on),
                    row(RlyProfileAccessRules.CLASSES, 'orderservice', on) }) });
            List<RlyProfileAccessRules.Row> many = new List<RlyProfileAccessRules.Row>();
            for (Integer i = 0; i <= RlyProfileAccessRules.MAX_ROWS; i++) {
                many.add(row(RlyProfileAccessRules.CLASSES, 'Class' + i, on));
            }
            String tooMany = refusal(new List<RlyProfileAccessRules.ProfileRows>{ profile('Admin', many) });
            Test.stopTest();
            System.assert(badProfile.contains('isn\'t a profile name'), 'Path characters: ' + badProfile);
            System.assert(twice.contains('listed twice'), 'Same profile twice: ' + twice);
            System.assert(section.contains('isn\'t a profile section'), 'Unknown section: ' + section);
            System.assert(key.contains('isn\'t a valid name for field access'), 'Field needs its object: ' + key);
            System.assert(value.contains('isn\'t a valid enabled'), 'true or false only: ' + value);
            System.assert(layout.contains('isn\'t a valid layout'), 'A layout of another object: ' + layout);
            System.assert(dupRow.contains('listed twice under Apex class access'), 'Same row twice: ' + dupRow);
            System.assert(tooMany.contains('up to ' + RlyProfileAccessRules.MAX_ROWS), 'Row limit: ' + tooMany);
        }
    }

    private static String composite(List<String> answers) {
        return '{"compositeResponse":[' + String.join(answers, ',') + ']}';
    }

    private static String ok(String records) {
        return '{"httpStatusCode":200,"body":{"done":true,"records":[' + records + ']}}';
    }

    private static String ofSales(String fields) {
        return '{"Parent":{"Profile":{"Name":"' + SALES + '"}},' + fields + '}';
    }

    private static RlyHttpMock orgMock() {
        String first = composite(new List<String>{
            ok(ofSales('"Field":"Account.Region__c","PermissionsRead":true,"PermissionsEdit":false')),
            ok(''),
            ok(ofSales('"Name":"Order__c","Visibility":"DefaultOn"')),
            '{"httpStatusCode":400,"body":[{"errorCode":"INVALID_FIELD","message":"No such column PermissionsNope"}]}',
            ok('{"Id":"' + CLASS_ID + '","Name":"OrderService"}'),
            ok('{"DurableId":"' + SETTING_ID + '","QualifiedApiName":"Rly_Settings__c"}') });
        String access = composite(new List<String>{ ok(ofSales('"SetupEntityId":"' + CLASS_ID + '"')) });
        String metadata = '<soapenv:Envelope><soapenv:Body><readMetadataResponse><result><records xsi:type="Profile">'
            + '<fullName>' + SALES + '</fullName><layoutAssignments><layout>Order__c-Rush Layout</layout><recordType>Order__c.Rush</recordType>'
            + '</layoutAssignments><recordTypeVisibilities><default>false</default><recordType>Order__c.Rush</recordType><visible>true</visible>'
            + '</recordTypeVisibilities></records></result></readMetadataResponse></soapenv:Body></soapenv:Envelope>';
        String list = '<soapenv:Envelope><soapenv:Body><listMetadataResponse><result><fullName>Admin</fullName><id>00e000000000001AAA</id>'
            + '<type>Profile</type></result><result><fullName>' + SALES + '</fullName><id>00e000000000002AAA</id><type>Profile</type></result>'
            + '<result><fullName>Custom%3A Ops</fullName><id>00e000000000009AAA</id><type>Profile</type></result>'
            + '</listMetadataResponse></soapenv:Body></soapenv:Envelope>';
        return new RlyHttpMock()
            .match('POST', '/composite').ifBodyHas('SetupEntityAccess').reply(200, access)
            .match('POST', '/composite').reply(200, first)
            .match('POST', '/services/Soap/m/').ifBodyHas('readMetadata').reply(200, metadata)
            .match('POST', '/services/Soap/m/').ifBodyHas('listMetadata').reply(200, list)
            .match('GET', 'FROM Profile').reply(200, '{"done":true,"records":[{"Id":"00e000000000001AAA","Name":"System Administrator"},'
                + '{"Id":"00e000000000002AAA","Name":"' + SALES + '"}]}');
    }

    private static List<RlyProfileAccessRules.Row> askedRows() {
        return new List<RlyProfileAccessRules.Row>{
            row(RlyProfileAccessRules.FIELDS, 'Account.Region__c', null), row(RlyProfileAccessRules.OBJECTS, 'Order__c', null),
            row(RlyProfileAccessRules.TABS, 'Order__c', null), row(RlyProfileAccessRules.SYSTEM_PERMISSIONS, 'Nope', null),
            row(RlyProfileAccessRules.CLASSES, 'OrderService', null), row(RlyProfileAccessRules.SETTINGS, 'Rly_Settings__c', null),
            row(RlyProfileAccessRules.RECORD_TYPES, 'Order__c.Rush', null), row(RlyProfileAccessRules.LAYOUTS, 'Order__c.Rush', null) };
    }

    @IsTest
    static void readsTheProfilesAndTheirAccess() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, orgMock());
            RlyProfileAccessReader.Profile sales = new RlyProfileAccessReader.Profile();
            sales.profile = SALES;
            sales.label = SALES;
            Map<String, Object> asked = new Map<String, Object>{ 'orgId' => devId, 'profiles' => new List<Object>{ sales }, 'rows' => askedRows() };
            Test.startTest();
            List<RlyProfileAccessReader.Profile> profiles = RlyProfileAccessController.profiles(devId);
            RlyProfileAccessController.Answer a = RlyProfileAccessController.readAccess(JSON.serialize(asked));
            Test.stopTest();
            System.assertEquals(3, profiles.size(), 'Every profile');
            System.assertEquals('Custom: Ops', profiles[0].label, 'A profile not found by Id is named from its file name');
            System.assertEquals('Admin', profiles[2].profile, 'System Administrator is the Admin file');
            Map<String, Map<String, String>> v = a.source.rows;
            System.assertEquals('true', v.get(SALES + '|fieldPermissions|account.region__c').get('readable'), 'Field read');
            System.assertEquals('false', v.get(SALES + '|fieldPermissions|account.region__c').get('editable'), 'Field edit');
            System.assertEquals('false', v.get(SALES + '|objectPermissions|order__c').get('allowRead'), 'No row: no access');
            System.assertEquals('DefaultOn', v.get(SALES + '|tabVisibilities|order__c').get('visibility'), 'Tab');
            System.assertEquals('true', v.get(SALES + '|classAccesses|orderservice').get('enabled'), 'Class through SetupEntityAccess');
            System.assertEquals('false', v.get(SALES + '|customSettingAccesses|rly_settings__c').get('enabled'), 'Setting found, not granted');
            System.assertEquals('true', v.get(SALES + '|recordTypeVisibilities|order__c.rush').get('visible'), 'Record type from readMetadata');
            System.assertEquals('Order__c-Rush Layout', v.get(SALES + '|layoutAssignments|order__c.rush').get('layout'), 'Layout');
            System.assert(!v.containsKey(SALES + '|userPermissions|nope'), 'A failed query leaves its rows unread');
            System.assert(String.join(a.source.notes, ' ').contains('system permissions'), 'Noted: ' + a.source.notes);
            System.assertEquals('SIT', a.targetName, 'The release\'s target is read too');
            System.assertEquals('DefaultOn', a.target.rows.get(SALES + '|tabVisibilities|order__c').get('visibility'), 'Target values');
        }
    }

    @IsTest
    static void layoutsAndFaultsFromReadMetadata() {
        System.runAs(RlyTestData.admin()) {
            RlyProfileAccessLayouts.Want w = new RlyProfileAccessLayouts.Want();
            w.out = new RlyProfileAccessReader.Values();
            w.profiles.put('admin', 'Admin');
            w.recordTypes.add('account.business');
            w.layouts.add('account');
            String body = '<readMetadataResponse><result><records xsi:type="Profile"><fullName>Admin</fullName><layoutAssignments>'
                + '<layout>Account-Account Layout</layout></layoutAssignments></records><records xsi:type="Profile"><fullName>Other</fullName>'
                + '</records></result></readMetadataResponse>';
            String fault;
            Test.startTest();
            RlyProfileAccessLayouts.readBody(body, w);
            try {
                RlyProfileAccessLayouts.readBody('<faultstring>INVALID_SESSION</faultstring>', w);
            } catch (RlyMetadata.MetadataException e) {
                fault = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals('Account-Account Layout', w.out.rows.get('Admin|layoutAssignments|account').get('layout'), 'Master layout by object');
            System.assertEquals('false', w.out.rows.get('Admin|recordTypeVisibilities|account.business').get('visible'), 'Not listed: not visible');
            System.assertEquals('INVALID_SESSION', fault, 'The org\'s fault');
        }
    }

    @IsTest
    static void accessOnlyReleaseCommitsItsFileAndNeedsApproval() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = devId;
            req.title = 'Region access';
            req.testClasses = new List<String>();
            req.profileAccess = new List<RlyProfileAccessRules.ProfileRows>{ profile(SALES, new List<RlyProfileAccessRules.Row>{
                row(RlyProfileAccessRules.FIELDS, 'Account.Region__c', new Map<String, String>{ 'readable' => 'true', 'editable' => 'true' }),
                row(RlyProfileAccessRules.SYSTEM_PERMISSIONS, 'ApiEnabled', new Map<String, String>{ 'enabled' => 'true' }) }) };
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            RLY_Release__c rel = [SELECT Id, Name, Retrieve_Id__c, Profile_Access_Count__c, Manual_Only__c, Deletion_Count__c, Is_Hotfix__c
                                  FROM RLY_Release__c WHERE Id = :relId];
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.refreshRelease(relId);
            Test.stopTest();
            RLY_Release__c after = [SELECT Status__c, Error_Message__c FROM RLY_Release__c WHERE Id = :relId];
            Map<String, Object> file = (Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('.relay-inbox/' + rel.Name + '-access.json'));
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
                EncodingUtil.base64Decode(String.valueOf(file.get('content'))).toString());
            List<Object> profiles = (List<Object>) sent.get('profiles');
            System.assertEquals(null, rel.Retrieve_Id__c, 'Nothing to retrieve');
            System.assertEquals(2, rel.Profile_Access_Count__c, 'Rows counted');
            System.assertEquals(false, rel.Manual_Only__c, 'Not manual steps only: the pipeline writes the rows');
            System.assertEquals('Workflow running', after.Status__c, 'Pipeline started: ' + after.Error_Message__c);
            System.assertEquals(SALES, ((Map<String, Object>) profiles[0]).get('profile'), 'The file names the profile');
            System.assert(RlyApprovalRules.contentsOf(rel).metadataTypes.contains('Profile'), 'Counts as a profile change');
            System.assertEquals(2, RlyProfileAccessController.forRelease(relId)[0].rows.size(), 'The release page reads its rows');
            System.assert([SELECT Detail__c FROM RLY_Release_Event__c WHERE Release__c = :relId AND Event_Type__c = 'Raised' LIMIT 1].Detail__c
                .contains('2 profile access rows'), 'History says so');
        }
    }
}
