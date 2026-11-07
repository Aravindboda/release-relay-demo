/**
 * @description Tests for raising a big release in parts (RlyRaiseParts and its use in RlyStatusReader): the parts are
 * planned the same way every time, a small release keeps one retrieve, and each check of a release in parts commits one
 * part's zip and starts the next part's retrieve until the last part starts the run. DEV1 and GitHub answer through
 * RlyFlowScenario's mock. Each test runs as an active System Administrator via System.runAs.
 */
@IsTest
private class RlyRaisePartsTest {

    // A release of 30 classes (two parts of 25 and 5) and a static resource (a part of its own).
    private static RLY_Release__c bigRelease(String retrieveId) {
        RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
        List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        for (Integer i = 0; i < 28; i++) {
            items.add(new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'Service' + String.valueOf(i).leftPad(2, '0')));
        }
        items.add(new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'StaticResource', Component_Name__c = 'logo'));
        items.add(new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'Gone', Is_Deletion__c = true));
        insert items;
        rel.Retrieve_Id__c = retrieveId;
        update rel;
        return rel;
    }

    @IsTest
    static void planKeepsHeavyTypesAloneAndIsStable() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Set<String>> byType = new Map<String, Set<String>>{
                'StaticResource' => new Set<String>{ 'logo', 'banner' }, 'ApexClass' => new Set<String>() };
            for (Integer i = 30; i > 0; i--) {
                byType.get('ApexClass').add('C' + String.valueOf(i).leftPad(2, '0'));
            }
            Test.startTest();
            List<Map<String, Set<String>>> parts = RlyRaiseParts.plan(byType);
            List<Map<String, Set<String>>> again = RlyRaiseParts.plan(byType);
            List<Map<String, Set<String>>> small = RlyRaiseParts.plan(new Map<String, Set<String>>{ 'ApexClass' => new Set<String>{ 'A', 'B' } });
            Test.stopTest();
            System.assertEquals(4, parts.size(), 'Classes 25 + 5, and each static resource alone');
            System.assertEquals(25, parts[0].get('ApexClass').size(), 'A full part first');
            System.assert(parts[0].get('ApexClass').contains('C01'), 'Names sorted');
            System.assertEquals(new Set<String>{ 'banner' }, parts[1].get('StaticResource'), 'Heavy types alone, sorted');
            System.assertEquals(new Set<String>{ 'logo' }, parts[2].get('StaticResource'), 'One heavy component a part');
            System.assertEquals(5, parts[3].get('ApexClass').size(), 'The rest last');
            System.assertEquals(JSON.serialize(parts), JSON.serialize(again), 'The same parts every time');
            System.assertEquals(1, small.size(), 'A small release is one part');
            System.assert(RlyRaiseParts.isParted('2:09S000000000001AAA'), 'k:id is a release in parts');
            System.assert(!RlyRaiseParts.isParted('09S000000000001AAA'), 'A plain id isn\'t');
        }
    }

    @IsTest
    static void eachCheckCommitsOnePartAndStartsTheNext() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = bigRelease('1:' + RlyFlowScenario.RETRIEVE_ID);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = [SELECT Status__c, Retrieve_Id__c, Error_Message__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals('Retrieving', saved.Status__c, 'More parts to go: ' + saved.Error_Message__c);
            System.assertEquals('2:' + RlyFlowScenario.RETRIEVE_ID, saved.Retrieve_Id__c, 'The next part\'s retrieve started');
            System.assert(mock.callLog().contains('/contents/.relay-inbox/' + rel.Name + '-part-1.zip'), 'Part 1 committed: ' + mock.callLog());
            System.assertEquals(null, mock.bodyFor('/dispatches'), 'No run before the last part');
            System.assertEquals('Part 2 of 3', RlyRaiseParts.progress(saved), 'Progress for the page');
        }
    }

    @IsTest
    static void theLastPartStartsTheRun() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = bigRelease('3:' + RlyFlowScenario.RETRIEVE_ID);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Workflow running', saved.Status__c, 'The run starts: ' + saved.Error_Message__c);
            System.assert(mock.callLog().contains('/contents/.relay-inbox/' + rel.Name + '-part-3.zip'), 'The last part committed');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"hub"'), 'Hub run dispatched');
        }
    }

    @IsTest
    static void aPartThatFailsFailsTheReleaseWithItsNumber() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = bigRelease('2:' + RlyFlowScenario.RETRIEVE_ID);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Failed';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Failed', saved.Status__c, 'Failed');
            System.assert(saved.Error_Message__c.startsWith('Part 2 of 3: '), 'Says which part: ' + saved.Error_Message__c);
        }
    }

    @IsTest
    static void aBigRaiseStartsWithItsFirstPart() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            Id devId = [SELECT Source_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Source_Org__c;
            RLY_Org__c dev = RlyReleaseStore.org(devId);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, RlyFlowScenario.forRelease(rel).build());
            Map<String, Set<String>> big = new Map<String, Set<String>>{ 'StaticResource' => new Set<String>{ 'logo' },
                'ApexClass' => new Set<String>{ 'A' } };
            Test.startTest();
            String parted = RlyRaiseParts.startFirst(dev, big);
            String single = RlyRaiseParts.startFirst(dev, new Map<String, Set<String>>{ 'ApexClass' => new Set<String>{ 'A' } });
            Test.stopTest();
            System.assertEquals('1:' + RlyFlowScenario.RETRIEVE_ID, parted, 'Two parts: the first part\'s retrieve, numbered');
            System.assertEquals(RlyFlowScenario.RETRIEVE_ID, single, 'One part: a plain retrieve, as before');
        }
    }
}
