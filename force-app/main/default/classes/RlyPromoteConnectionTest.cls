/**
 * @description Tests for build 63.1 (D50): promotions and back promotes start in the active Git connection, so after a
 * provider switch they run in the new repository. Both connections are made in the test setup (GitLab is the newer,
 * active one); every test runs as an admin through System.runAs and makes no callouts.
 */
@IsTest
private class RlyPromoteConnectionTest {

    @TestSetup
    static void setup() {
        RlyMigrationTestData.connections();
    }

    @IsTest
    static void aPromotionStartsInTheActiveConnection() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c promotion = RlyMigrationTestData.release('Queued');
            promotion.Release_Type__c = RlyPromotion.TYPE_PROMOTION;
            Test.startTest();
            RlyPromoteStore.insertPromotion(promotion, new List<RLY_Release_Item__c>(), new Set<Id>());
            Test.stopTest();
            RLY_Release__c saved = [SELECT Git_Connection__c FROM RLY_Release__c WHERE Id = :promotion.Id];
            System.assertEquals(RlyMigrationTestData.gitLabId(), saved.Git_Connection__c, 'The promotion is stamped with the active connection');
            System.assertEquals(RlyMigrationTestData.gitLabId(), RlyGitConnections.connectionIdOf(saved),
                'So it runs in the new repository, not the oldest one');
        }
    }

    @IsTest
    static void aBackPromoteStartsInTheActiveConnectionAndAStampedOneKeepsItsOwn() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c sync = RlyMigrationTestData.release('Queued');
            sync.Release_Type__c = RlyPromotion.TYPE_BACK_PROMOTE;
            RLY_Release__c own = RlyMigrationTestData.release('Queued');
            own.Release_Type__c = RlyPromotion.TYPE_BACK_PROMOTE;
            own.Git_Connection__c = RlyMigrationTestData.gitHubId();
            Test.startTest();
            RlyPromoteStore.insertSyncs(new List<RLY_Release__c>{ sync, own });
            Test.stopTest();
            Map<Id, RLY_Release__c> saved = new Map<Id, RLY_Release__c>([SELECT Git_Connection__c FROM RLY_Release__c
                WHERE Id IN :new List<Id>{ sync.Id, own.Id }]);
            System.assertEquals(RlyMigrationTestData.gitLabId(), saved.get(sync.Id).Git_Connection__c, 'A blank one gets the active connection');
            System.assertEquals(RlyMigrationTestData.gitHubId(), saved.get(own.Id).Git_Connection__c, 'A stamped one keeps its own');
        }
    }
}
