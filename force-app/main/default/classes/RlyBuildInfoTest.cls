/**
 * @description Tests for the "What's built" tab's live figures (RlyBuildInfo): Release Relay record counts, Apex class
 * sizes, org limits, static resources and async Apex (none). Every test runs through System.runAs as an active System
 * Administrator with Release Relay Developer.
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
}
