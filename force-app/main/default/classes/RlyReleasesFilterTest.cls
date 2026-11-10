/**
 * @description Tests the Releases tab's server-side filter (RlyReleasesController.listReleasesFor) and its chip counts
 * (countReleases): raised by, state groups (open, deployed, failed, closed, all), search and hotfixes first. Every
 * test runs as the System Administrator via System.runAs.
 */
@IsTest
private class RlyReleasesFilterTest {

    private static RLY_Release__c rel(String title, String status) {
        RLY_Org__c dev = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1' LIMIT 1];
        RLY_Org__c sit = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1];
        return new RLY_Release__c(Title__c = title, Status__c = status, Mode__c = 'Org changes', Request_Type__c = 'Changes',
            Source_Org__c = dev.Id, Target_Org__c = sit.Id, Org_Label__c = 'DEV1', Target_Branch__c = 'sit',
            Component_Count__c = 1);
    }

    private static RLY_Release__c hotfix(RLY_Release__c r) {
        r.Is_Hotfix__c = true;
        r.Hotfix_Reason__c = 'Production is down';
        return r;
    }

    /**
     * @description Mine: two open (one a hotfix), one deployed, one deploy failed, one rejected. Someone else's: one open.
     * @return the current user (the System Administrator the tests run as)
     */
    private static User setUpReleases() {
        User me = RlyTestData.admin();
        System.runAs(me) {
            RlyReleaseTestData.route();
            insert new List<RLY_Release__c>{
                rel('Region field', 'Validating'), hotfix(rel('Payment fix', 'Checks failed')),
                rel('Account layout', 'Deployed'), rel('Case flow', 'Deploy failed'), rel('Old report', 'Rejected')
            };
        }
        User other = RlyTestData.plainUser();
        System.runAs(other) {
            insert rel('Someone else', 'Ready for approval');
        }
        return me;
    }

    private static String filterJson(Id raisedById, String state, String searchText) {
        return JSON.serialize(new Map<String, Object>{ 'raisedById' => raisedById, 'state' => state, 'searchText' => searchText });
    }

    @IsTest
    static void defaultsToMyOpenReleasesHotfixesFirst() {
        User me = setUpReleases();
        System.runAs(me) {
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleasesFor(filterJson(me.Id, null, null));
            System.assertEquals(2, rows.size(), 'My open releases: Validating and Checks failed');
            System.assertEquals('Payment fix', rows[0].title, 'Hotfix first');
            System.assertEquals(me.Id, rows[0].raisedById, 'Raised by me');
            System.assertEquals(3, RlyReleasesController.listReleasesFor(null).size(), 'Blank filter: everyone, open');
        }
    }

    @IsTest
    static void filtersByStateRaisedByAndSearch() {
        User me = setUpReleases();
        System.runAs(me) {
            System.assertEquals('Account layout', RlyReleasesController.listReleasesFor(filterJson(me.Id, 'deployed', null))[0].title, 'Deployed');
            System.assertEquals('Case flow', RlyReleasesController.listReleasesFor(filterJson(me.Id, 'failed', ' ')).get(0).title, 'Failed');
            System.assertEquals('Old report', RlyReleasesController.listReleasesFor(filterJson(me.Id, 'closed', null))[0].title, 'Closed');
            System.assertEquals(5, RlyReleasesController.listReleasesFor(filterJson(me.Id, 'all', null)).size(), 'All mine');
            System.assertEquals(6, RlyReleasesController.listReleasesFor(filterJson(null, 'all', null)).size(), 'Everyone');
            System.assertEquals(1, RlyReleasesController.listReleasesFor(filterJson(null, 'all', 'payment')).size(), 'Search on title');
            String num = [SELECT Name FROM RLY_Release__c WHERE Title__c = 'Someone else' LIMIT 1].Name;
            System.assertEquals(1, RlyReleasesController.listReleasesFor(filterJson(null, 'open', num)).size(), 'Search on number');
            System.assertEquals(0, RlyReleasesController.listReleasesFor(filterJson(me.Id, 'open', num)).size(), 'Not mine');
        }
    }

    @IsTest
    static void countsEachState() {
        User me = setUpReleases();
        System.runAs(me) {
            Map<String, Integer> mine = RlyReleasesController.countReleases(me.Id);
            System.assertEquals(2, mine.get('open'), 'Open');
            System.assertEquals(1, mine.get('deployed'), 'Deployed');
            System.assertEquals(1, mine.get('failed'), 'Failed');
            System.assertEquals(1, mine.get('closed'), 'Closed');
            System.assertEquals(5, mine.get('all'), 'All');
            System.assertEquals(1, mine.get('checks'), 'Checks failed');
            System.assertEquals(1, RlyReleasesController.listReleasesFor(filterJson(me.Id, 'checks', null)).size(), 'Checks failed list');
            Map<String, Integer> everyone = RlyReleasesController.countReleases('');
            System.assertEquals(3, everyone.get('open'), 'Everyone open');
            System.assertEquals(6, everyone.get('all'), 'Everyone all');
        }
    }

    @IsTest
    static void refusesBadFilters() {
        User me = setUpReleases();
        System.runAs(me) {
            Integer refused = 0;
            String orgId = [SELECT Id FROM RLY_Org__c LIMIT 1].Id;
            try { RlyReleasesController.listReleasesFor(filterJson(me.Id, 'sideways', null)); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.countReleases(orgId); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.countReleases('not an id'); } catch (AuraHandledException e) { refused++; }
            try { RlyReleasesController.listReleasesFor('{not json'); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(4, refused, 'Unknown state, a non-user, a bad Id and bad JSON are refused');
            List<RlyReleasesController.Row> legacy = RlyReleasesController.listReleases('mine');
            System.assertEquals(5, legacy.size(), 'The Approvals tab\'s list still works');
        }
    }
}
