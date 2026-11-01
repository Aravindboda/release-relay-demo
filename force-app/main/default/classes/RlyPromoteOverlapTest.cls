/**
 * @description Tests for promoting from the stage's state (RlyPromoteOverlap, its use in RlyPromotion and
 * RlyPromoteController, and a promotion that clashes in RlyCheckReader). Route DEV1 -> SIT -> PROD (hub). Three releases
 * wait in SIT: OLDER and NEWER changed the same class (Greeting), OTHER changed nothing they did. Each test runs through
 * System.runAs as an active System Administrator with Release Relay Admin. Records are inserted before Test.startTest.
 */
@IsTest
private class RlyPromoteOverlapTest {

    private static final String SHARED = 'ApexClass:Greeting';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    // [older, other, newer], deployed to SIT 30, 20 and 10 minutes ago; older and newer share Greeting.
    private static List<RLY_Release__c> waitingInSit() {
        RlyReleaseTestData.route();
        RLY_Release__c older = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
        RLY_Release__c other = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('b'));
        RLY_Release__c newer = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('c'));
        update new List<RLY_Release__c>{
            new RLY_Release__c(Id = older.Id, Last_Synced__c = System.now().addMinutes(-30)),
            new RLY_Release__c(Id = other.Id, Last_Synced__c = System.now().addMinutes(-20)),
            new RLY_Release__c(Id = newer.Id, Last_Synced__c = System.now().addMinutes(-10))
        };
        insert new List<RLY_Release_Item__c>{
            new RLY_Release_Item__c(Release__c = older.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'Greeting'),
            new RLY_Release_Item__c(Release__c = newer.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'Greeting', Is_Deletion__c = true)
        };
        return new List<RLY_Release__c>{ older, other, newer };
    }

    private static String request(List<RLY_Release__c> rels) {
        List<Id> ids = new List<Id>();
        for (RLY_Release__c r : rels) {
            ids.add(r.Id);
        }
        return JSON.serialize(new Map<String, Object>{ 'stageId' => orgId('SIT'), 'releaseIds' => ids, 'title' => 'Promote' });
    }

    @IsTest
    static void boardListsEachReleasesComponents() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            RlyPromoteController.PromoteStage s = RlyPromoteController.getPromote().stages[0];
            System.assertEquals(3, s.ready.size(), 'All three wait');
            for (RlyPromoteController.Ready r : s.ready) {
                Boolean shares = r.id == rels[0].Id || r.id == rels[2].Id;
                System.assertEquals(shares, r.components.contains(SHARED), 'Components (deletions included) of ' + r.name + ': ' + r.components);
            }
        }
    }

    @IsTest
    static void olderReleaseOfTheSameComponentGoesToo() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Test.startTest();
            Id promotionId = RlyPromoteController.promote(request(new List<RLY_Release__c>{ rels[2] }));
            Test.stopTest();
            RLY_Release__c p = RlyReleaseTestData.reload(promotionId);
            System.assertEquals(rels[0].Id + ',' + rels[2].Id, p.Carried_Releases__c, 'The older change goes too, oldest first');
            System.assertEquals(promotionId, RlyReleaseTestData.reload(rels[0].Id).Promoted_In__c, 'Marked promoted with the others');
            System.assertEquals(null, RlyReleaseTestData.reload(rels[1].Id).Promoted_In__c, 'The unrelated release stays');
            System.assertEquals(1, RlyPromoteController.getPromote().stages[0].ready.size(), 'Only it is left waiting');
        }
    }

    @IsTest
    static void newerReleaseOfTheSameComponentBlocks() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Map<Id, RLY_Release__c> names = new Map<Id, RLY_Release__c>([SELECT Id, Name FROM RLY_Release__c]);
            String message;
            Test.startTest();
            try {
                RlyPromoteController.promote(request(new List<RLY_Release__c>{ rels[0], rels[1] }));
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(names.get(rels[2].Id).Name + ' changed Greeting after ' + names.get(rels[0].Id).Name
                + ': add it, or wait and promote them together.', message, 'Blocked until the newer one is added');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release__c WHERE Release_Type__c = 'Promotion'], 'Nothing saved');
        }
    }

    @IsTest
    static void outcomeNamesTheBlockerAndCarriesInRounds() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            // other, deployed before older, shares a class with it: picking newer carries older (Greeting), then other
            // (through older's AccountServicea) in a second round.
            insert new RLY_Release_Item__c(Release__c = rels[1].Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountServicea');
            update new RLY_Release__c(Id = rels[1].Id, Last_Synced__c = System.now().addMinutes(-40));
            List<RLY_Release__c> waiting = RlyPromoteStore.readyIn(new Set<Id>{ orgId('SIT') });
            Test.startTest();
            RlyPromoteOverlap.Outcome carried = RlyPromoteOverlap.check(waiting, new Set<Id>{ rels[2].Id });
            RlyPromoteOverlap.Outcome blocked = RlyPromoteOverlap.check(waiting, new Set<Id>{ rels[0].Id });
            Set<Id> going = RlyPromoteOverlap.withCarried(waiting, new Set<Id>{ rels[2].Id });
            Test.stopTest();
            System.assertEquals(null, carried.blocked, 'Nothing newer: not blocked');
            System.assertEquals(new Set<Id>{ rels[0].Id, rels[1].Id }, new Set<Id>(carried.carriedIds), 'Carried over two rounds');
            System.assertEquals(3, going.size(), 'Everything goes');
            System.assertNotEquals(null, blocked.blocked, 'Blocked');
            System.assertEquals(rels[2].Id, blocked.blockerId, 'newer changed Greeting after older: it blocks');
            System.assertEquals(new List<Id>{ rels[1].Id }, blocked.carriedIds, 'other went with older before the block was found');
            System.assert(RlyPromoteOverlap.componentsOf(new Set<Id>()).isEmpty(), 'No releases, no components');
        }
    }

    @IsTest
    static void clashListsTheFilesOnThePromotion() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(new List<RLY_Release__c>{ rels[1] }));
            RLY_Release__c p = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :promotionId];
            update new RLY_Release__c(Id = promotionId, Status__c = 'Workflow running', Pending_Run__c = 'promote',
                Source_Branch__c = 'promote/' + p.Name.toLowerCase(), Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(p);
            scenario.runMode = 'promote';
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            scenario.prState = 'none';
            scenario.results.put('raise', RlyReleaseTestData.result('raise', '"status":"Failed","message":"prod has a change to '
                + 'classes/Greeting.cls that sit doesn\'t have","conflicts":["classes/Greeting.cls"],'
                + '"clash":[{"file":"classes/Greeting.cls","targetBlob":"t","stageBlob":"s"}]'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(promotionId);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(promotionId);
            System.assertEquals('Failed', saved.Status__c, 'Failed');
            System.assert(saved.Error_Message__c.startsWith('prod has a change'), saved.Error_Message__c);
            Map<String, Object> kept = (Map<String, Object>) JSON.deserializeUntyped(saved.Validation_Result__c);
            System.assertEquals(new List<Object>{ 'classes/Greeting.cls' }, kept.get('raiseConflicts'), 'The files, for the page');
        }
    }
}
