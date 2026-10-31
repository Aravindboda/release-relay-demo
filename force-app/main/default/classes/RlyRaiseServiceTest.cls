/**
 * @description Tests for raising a release (RlyRaiseService, RlyRaiseRules, RlyTestRule, RlyRetrieve.start and
 * RlyReleasesController.raiseRelease). Every test runs as an existing active System Administrator through System.runAs.
 * Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyRaiseServiceTest {

    private static RlyRaiseService.RaiseRequest request(Id sourceOrgId) {
        RlyRaiseService.RaiseRequest r = new RlyRaiseService.RaiseRequest();
        r.sourceOrgId = sourceOrgId;
        r.title = 'Release';
        r.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
        r.testClasses = new List<String>();
        return r;
    }

    @IsTest
    static void raiseStartsTheRetrieve() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = request(dev.Id);
            req.title = 'Region field';
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexClass', 'AccountService'),
                RlyReleaseTestData.item('ApexClass', 'AccountServiceTest'), RlyReleaseTestData.item('CustomField', 'Account.Region__c'),
                RlyReleaseTestData.item('ReportFolder', 'Sales') };
            req.testClasses = new List<String>{ 'AccountServiceTest' };
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = RlyReleaseTestData.reload(relId);
            System.assertEquals('Retrieving', rel.Status__c, 'Waiting for the retrieve');
            System.assertEquals(RlyFlowScenario.RETRIEVE_ID, rel.Retrieve_Id__c, 'Retrieve id saved');
            System.assertEquals('AccountServiceTest', rel.Test_Classes__c, 'Tests saved');
            System.assertEquals(4, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c = :relId], 'Items saved');
        }
    }

    @IsTest
    static void raiseRefusesBadRequests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
            List<RlyRaiseService.RaiseRequest> bad = new List<RlyRaiseService.RaiseRequest>();
            for (Integer n = 0; n < 7; n++) {
                bad.add(request(dev.Id));
            }
            bad[0].items = new List<RlyRaiseService.Item>();
            bad[1].title = ' ';
            bad[2].items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexTrigger', 'AccountTrigger') };
            bad[3].testClasses = new List<String>{ 'NotSelectedTest' };
            bad[4].items[0].deleted = true;
            bad[5].items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'A,B') };
            bad[6].sourceOrgId = sitId;
            Integer refused = 0;
            for (RlyRaiseService.RaiseRequest r : bad) {
                try {
                    RlyRaiseService.raise(r);
                } catch (RlyReleaseException e) {
                    refused++;
                }
            }
            System.assertEquals(bad.size(), refused, 'Every bad request is refused before any callout');
            Boolean wrapped = false;
            try {
                RlyReleasesController.raiseRelease(JSON.serialize(bad[2]));
            } catch (AuraHandledException e) {
                wrapped = e.getMessage().contains('test class');
            }
            System.assert(wrapped, 'The test rule message reaches the page');
        }
    }
}
