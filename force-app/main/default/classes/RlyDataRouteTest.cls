/**
 * @description Tests for RlyDataRoute (build 59, D30): data is sent up and copied down along the route, never sideways or
 * the wrong way. Runs as an active System Administrator; the route is inserted by RlyReleaseTestData.route.
 */
@IsTest
private class RlyDataRouteTest {

    @IsTest
    static void dataGoesAlongTheRoute() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            Map<String, RLY_Org__c> byName = new Map<String, RLY_Org__c>();
            for (RLY_Org__c o : RlyDataStore.orgs()) {
                byName.put(o.Name, o);
            }
            Map<Id, Integer> rank = RlyDataRoute.ranks(byName.values());
            System.assertEquals(0, rank.get(byName.get('PROD').Id), 'The hub is at the top');
            System.assertEquals(1, rank.get(byName.get('SIT').Id), 'The stage is below it');
            System.assertEquals(2, rank.get(dev.Id), 'Developer orgs are on the bottom step');
            RlyDataRoute.checkDirection(RlyDataRuns.UP, byName.get('DEV1'), byName.get('SIT'));
            RlyDataRoute.checkDirection(RlyDataRuns.DOWN, byName.get('PROD'), byName.get('SIT'));
            RlyDataRoute.checkDirection(RlyDataRuns.REFILL, byName.get('DEV1'), byName.get('SIT'));
            System.assertEquals(true, refused(RlyDataRuns.DOWN, byName.get('SIT'), byName.get('PROD')).startsWith('Copy down goes'),
                'Copy down never goes up');
            System.assertEquals(true, refused(RlyDataRuns.UP, byName.get('PROD'), byName.get('SIT')).startsWith('Send up goes'),
                'Send up never goes down');
        }
    }

    private static String refused(String direction, RLY_Org__c source, RLY_Org__c target) {
        try {
            RlyDataRoute.checkDirection(direction, source, target);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return '';
    }
}
