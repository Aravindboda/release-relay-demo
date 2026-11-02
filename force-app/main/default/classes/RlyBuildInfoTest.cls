/**
 * @description Tests for the "What's built" tab's live figures (RlyBuildInfo): Release Relay record counts, Apex class
 * sizes, org limits, static resources, async Apex (none) and the document's counts read from setup objects. Every test
 * runs through System.runAs as an active System Administrator with Release Relay Developer.
 */
@IsTest
private class RlyBuildInfoTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Developer');
    }

    @IsTest
    static void readsCountsAndClasses() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.release('Validating', 'check');
            RlyBuildInfo.BuildInfo info = RlyBuildInfo.read();
            Map<String, RlyBuildInfo.RecordCount> byObject = new Map<String, RlyBuildInfo.RecordCount>();
            for (RlyBuildInfo.RecordCount r : info.records) {
                byObject.put(r.objectName, r);
            }
            System.assertEquals(6, info.records.size(), 'Six objects counted');
            System.assertEquals(1, byObject.get('RLY_Release__c').total, 'One release');
            System.assertEquals(2, byObject.get('RLY_Release_Item__c').total, 'Two items');
            System.assertEquals(3, byObject.get('RLY_Org__c').total, 'Three orgs on the route');
            System.assertEquals(false, byObject.get('RLY_Org__c').capped, 'Not capped');
            System.assertEquals(0, info.asyncJobs, 'No async Apex');
            Long total = 0;
            Boolean selfListed = false;
            for (RlyBuildInfo.ClassSize c : info.classes) {
                total += c.chars;
                selfListed = selfListed || c.name == 'RlyBuildInfo';
            }
            System.assertEquals(total, info.apexChars, 'Total is the sum of the classes');
            System.assert(selfListed && info.apexChars > 0, 'This class is listed with its size');
            System.assertNotEquals(null, info.codeChangedOn, 'Last code change known');
            System.assertNotEquals(null, info.resources, 'Resources read');
        }
    }

    @IsTest
    static void limitsAndCap() {
        System.runAs(RlyTestData.admin()) {
            List<RlyBuildInfo.Usage> found = RlyBuildInfo.usage(OrgLimits.getMap());
            for (RlyBuildInfo.Usage u : found) {
                System.assert(u.name == 'DataStorageMB' || u.name == 'DailyApiRequests', 'Only the limits the tab shows: ' + u.name);
                System.assert(u.maxValue >= 0 && u.used >= 0, 'Used and maximum read');
            }
            System.assertEquals(0, RlyBuildInfo.usage(null).size(), 'No limit map, nothing shown');
            System.assertEquals(true, RlyBuildInfo.recordCount('RLY_Release__c', 'Releases', 7000).capped, 'Cap reached');
            System.assertEquals(false, RlyBuildInfo.recordCount('RLY_Release__c', 'Releases', 6999).capped, 'Below the cap');
        }
    }

    @IsTest
    static void countsFromSetup() {
        System.runAs(RlyTestData.admin()) {
            RlyBuildInfo.Counts c = RlyBuildInfo.counts();
            System.assert(c.apexClasses > 0, 'Release Relay classes counted (this one at least)');
            System.assertNotEquals(null, c.readOn, 'Read time set');
            System.assert(c.permissionSets >= 1 && c.permissionSets == c.permissionSetCounts.size(), 'Permission sets read with their counts');
            Boolean developerFound = false;
            for (RlyBuildInfo.PermissionSetCount p : c.permissionSetCounts) {
                developerFound = developerFound || p.name == 'RLY_Developer';
                System.assert(p.classes >= 0 && p.fields >= 0 && p.objects >= 0 && p.tabs >= 0 && p.customPermissions >= 0, 'Counts not negative');
            }
            System.assert(developerFound, 'RLY_Developer is one of them');
            System.assert(c.customPermissions >= 0 && c.staticResources >= 0 && c.staticResourceBytes >= 0, 'Other counts read');
            System.assert(c.tabs == null || c.tabs >= 0, 'Tabs read or left to the generated figure');
            System.assertNotEquals(null, c.fieldsByObject, 'Documented objects described');
            System.assert(c.fieldsByObject.get('RLY_Release__c') > 0 && c.customFields >= c.fieldsByObject.get('RLY_Release__c'), 'Release fields counted');
        }
    }

    @IsTest
    static void fieldCountsAndGrants() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(null, RlyBuildInfo.customFieldCounts(new List<String>{ 'RLY_Not_An_Object__c' }), 'Unknown object: generated figure');
            System.assertEquals(2, RlyBuildInfo.countCustom('RLY_Org__c', new Set<String>{ 'name', 'role__c', 'branch__c' }), 'Custom fields only');
            System.assertEquals(1, RlyBuildInfo.countCustom('User', new Set<String>{ 'rly_slack_member_id__c', 'other__c', 'email' }), 'On User only RLY_ fields');
            Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Developer' LIMIT 1].Id;
            RlyBuildInfo.PermissionSetCount pc = new RlyBuildInfo.PermissionSetCount();
            Map<Id, RlyBuildInfo.PermissionSetCount> byId = new Map<Id, RlyBuildInfo.PermissionSetCount>{ psId => pc };
            for (String kind : new List<String>{ 'ApexClass', 'CustomPermission', 'Tab', 'Object', 'Field', 'Other' }) {
                RlyBuildInfo.addGrant(byId, psId, kind);
            }
            RlyBuildInfo.addGrant(byId, UserInfo.getUserId(), 'ApexClass');
            System.assertEquals(1, pc.classes, 'One class');
            System.assertEquals(1, pc.customPermissions, 'One custom permission');
            System.assertEquals(1, pc.tabs, 'One tab');
            System.assertEquals(1, pc.objects, 'One object');
            System.assertEquals(1, pc.fields, 'One field; unknown kinds and other parents ignored');
        }
    }
}
