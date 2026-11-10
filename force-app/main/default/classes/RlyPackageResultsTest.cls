/**
 * @description Tests for build 55's package results (RlyPackageResults): the History line, the raise's kept references
 * read with the validation result (raise.json, mocked) and kept on Validation_Result__c, one History event per run, and
 * nothing for results without packages. Every test runs as RlyTestData.admin(); records are inserted before
 * Test.startTest, callouts come after.
 */
@IsTest
private class RlyPackageResultsTest {

    private static Map<String, Object> parsed(String body) {
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    @IsTest
    static void summaryNamesKeptAndLeftOut() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            String kept = RlyPackageResults.keptText(parsed('{"kept":{"arch":3}}'), 'sit');
            String left = RlyPackageResults.leftOutText(parsed('{"leftOut":{"svk":2},"componentsLeftOut":["Layout:svk__Survey__c-Survey Layout"]}'), 'DEV1');
            String two = RlyPackageResults.leftOutText(parsed('{"leftOut":{"arch":1,"svk":2}}'), 'PROD');
            String none = RlyPackageResults.keptText(parsed('{"kept":{}}'), 'sit');
            String noneLeft = RlyPackageResults.leftOutText(parsed('{"leftOut":{"arch":0},"componentsLeftOut":[]}'), 'SIT');
            Test.stopTest();
            System.assertEquals('Kept 3 (arch) from sit', kept, 'The board\'s kept part');
            System.assertEquals('Left out in DEV1: 2 (svk), 1 component', left, 'The board\'s left out part');
            System.assertEquals('Left out in PROD: 3 (arch 1, svk 2)', two, 'Several packages are counted each');
            System.assertEquals(null, none, 'Nothing kept: no part');
            System.assertEquals(null, noneLeft, 'Nothing left out: no part');
        }
    }

    @IsTest
    static void raiseKeptReferencesAreReadWithTheValidation() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c created = RlyReleaseTestData.release('Validating', 'hub');
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id,
                Packages__c = '[{"ns":"arch","name":"Archiver","version":"2.14"}]', Packages_Checked__c = System.now());
            RLY_Release__c rel = RlyReleaseStore.release(created.Id);
            RlyHttpMock mock = new RlyHttpMock().match('GET', '/raise.json')
                .reply(200, RlyReleaseTestData.result('raise', '"status":"Passed","packages":{"kept":{"arch":3}}'));
            Test.setMock(HttpCalloutMock.class, mock);
            Map<String, Object> val = parsed('{"status":"Passed","packages":{"leftOut":{"arch":2},"componentsLeftOut":["Layout:arch__Job__c-Job Layout"]}}');
            Test.startTest();
            RlyPackageResults.onValidation(rel, RlyGit.forConnection(RlyReleaseStore.git()), val);
            RlyReleaseLog.flush();
            Test.stopTest();
            Map<String, Object> raised = (Map<String, Object>) val.get(RlyPackageResults.RAISE_KEY);
            System.assertNotEquals(null, raised, 'The raise\'s packages are kept on the validation result: ' + val);
            List<RLY_Release_Event__c> events = [SELECT Detail__c, Org__c FROM RLY_Release_Event__c
                WHERE Release__c = :rel.Id AND Event_Type__c = :RlyPackageResults.EVENT];
            System.assertEquals(1, events.size(), 'One History event for the run');
            System.assertEquals('Kept 3 (arch) from sit · Left out in SIT: 2 (arch), 1 component', events[0].Detail__c, 'What happened');
            System.assertEquals(rel.Target_Org__c, events[0].Org__c, 'In the target org');
        }
    }

    @IsTest
    static void checksWithoutPackagesReadNothingMore() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c created = RlyReleaseTestData.release('Validating', 'check');
            RLY_Release__c rel = RlyReleaseStore.release(created.Id);
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Map<String, Object> val = parsed('{"status":"Passed"}');
            Test.startTest();
            RlyPackageResults.onValidation(rel, RlyGit.forConnection(RlyReleaseStore.git()), val);
            RlyPackageResults.onValidation(rel, null, null);
            RlyPackageResults.onDeploy(rel, parsed('{"status":"Deployed"}'));
            RlyReleaseLog.flush();
            Test.stopTest();
            System.assertEquals(0, mock.calls.size(), 'No raise.json read for a check run: ' + mock.callLog());
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c = :rel.Id AND Event_Type__c = :RlyPackageResults.EVENT],
                'Nothing kept or left out: no History event');
        }
    }

    @IsTest
    static void deployLeftOutIsInHistory() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c created = RlyReleaseTestData.release('Deploying', 'merge');
            RLY_Release__c rel = RlyReleaseStore.release(created.Id);
            Test.startTest();
            RlyPackageResults.onDeploy(rel, parsed('{"status":"Deployed","packages":{"leftOut":{"svk":2}}}'));
            RlyReleaseLog.flush();
            Test.stopTest();
            RLY_Release_Event__c e = [SELECT Detail__c FROM RLY_Release_Event__c WHERE Release__c = :rel.Id AND Event_Type__c = :RlyPackageResults.EVENT];
            System.assertEquals('Left out in SIT: 2 (svk)', e.Detail__c, 'The deploy\'s left out references');
        }
    }
}
