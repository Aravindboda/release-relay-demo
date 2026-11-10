/**
 * @description Tests for Add access picking (RlyProfileAccessNames, RlyProfileAccessNameRules, build 58.1): each kind
 * lists the developer org's components from a mocked org, fields only when they take field access, and an unknown kind
 * is refused. Runs as an active System Administrator via System.runAs; records are inserted before Test.startTest and
 * callouts come after it.
 */
@IsTest
private class RlyProfileAccessNamesTest {

    private static RlyHttpMock orgMock() {
        String sobjects = '{"sobjects":[{"name":"Account","label":"Account","layoutable":true,"customSetting":false},'
            + '{"name":"Rly_Settings__c","label":"Relay settings","layoutable":false,"customSetting":true},'
            + '{"name":"Rly_Route__mdt","label":"Route","layoutable":false,"customSetting":false},'
            + '{"name":"Order_Event__e","label":"Order event","layoutable":true,"customSetting":false}]}';
        String fields = '{"fields":[{"name":"Region__c","label":"Region","permissionable":true},'
            + '{"name":"Name","label":"Account Name","permissionable":false}]}';
        String perms = '{"fields":[{"name":"PermissionsApiEnabled","label":"API Enabled","type":"boolean"},'
            + '{"name":"Name","label":"Name","type":"string"}]}';
        String tabs = '[{"name":"standard-Account","label":"Accounts"},{"name":"bad tab","label":"x"}]';
        return new RlyHttpMock()
            .match('GET', '/sobjects/Account/describe').reply(200, fields)
            .match('GET', '/sobjects/PermissionSet/describe').reply(200, perms)
            .match('GET', '/sobjects').reply(200, sobjects)
            .match('GET', '/tabs').reply(200, tabs)
            .match('GET', 'FROM ApexClass').reply(200, '{"done":true,"records":[{"Name":"OrderService"}]}')
            .match('GET', 'FROM RecordType').reply(200, '{"done":true,"records":[{"SobjectType":"Account","DeveloperName":"Business","Name":"Business"}]}');
    }

    private static List<String> keys(List<RlyProfileAccessNames.Pick> picks) {
        List<String> out = new List<String>();
        for (RlyProfileAccessNames.Pick p : picks) {
            out.add(p.key + (p.opens ? '>' : ''));
        }
        return out;
    }

    @IsTest
    static void eachKindListsTheOrgsComponents() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, orgMock());
            Map<String, List<String>> got = new Map<String, List<String>>();
            Test.startTest();
            got.put('objects', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.FIELDS, null)));
            got.put('fields', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.FIELDS, 'Account')));
            got.put('settings', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.SETTINGS, null)));
            got.put('types', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.METADATA_TYPES, null)));
            got.put('perms', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.SYSTEM_PERMISSIONS, null)));
            got.put('tabs', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.TABS, null)));
            got.put('classes', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.CLASSES, null)));
            got.put('layouts', keys(RlyProfileAccessController.names(devId, RlyProfileAccessRules.LAYOUTS, null)));
            Test.stopTest();
            System.assertEquals(new List<String>{ 'Account>' }, got.get('objects'), 'Objects with layouts open for their fields');
            System.assertEquals(new List<String>{ 'Account.Region__c' }, got.get('fields'), 'Only fields that take field access');
            System.assertEquals(new List<String>{ 'Rly_Settings__c' }, got.get('settings'), 'Custom settings');
            System.assertEquals(new List<String>{ 'Rly_Route__mdt' }, got.get('types'), 'Custom metadata types');
            System.assertEquals(new List<String>{ 'ApiEnabled' }, got.get('perms'), 'System permissions without the prefix');
            System.assertEquals(new List<String>{ 'standard-Account' }, got.get('tabs'), 'Tabs a profile file can name');
            System.assertEquals(new List<String>{ 'OrderService' }, got.get('classes'), 'Apex classes');
            System.assertEquals(new List<String>{ 'Account.Business', 'Account' }, got.get('layouts'), 'Record types, then master layouts');
        }
    }

    @IsTest
    static void unknownKindsAndBadObjectsAreRefused() {
        System.runAs(RlyTestData.admin()) {
            Id devId = RlyReleaseTestData.route().Id;
            List<String> refused = new List<String>();
            Test.startTest();
            for (List<String> ask : new List<List<String>>{ new List<String>{ 'loginHours', null },
                    new List<String>{ RlyProfileAccessRules.FIELDS, 'Account/../x' } }) {
                try {
                    RlyProfileAccessController.names(devId, ask[0], ask[1]);
                } catch (Exception e) {
                    refused.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assertEquals(2, refused.size(), 'Both refused: ' + refused);
        }
    }
}
