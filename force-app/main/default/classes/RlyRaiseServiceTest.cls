/**
 * @description Tests for raising a release (RlyRaiseService, RlyRaiseRules, RlyTestRule, RlyRetrieve.start and
 * RlyReleasesController.raiseRelease), inactive triggers (RlyTestRule, the production flag of RlyPipelineOptions and the
 * Slack card's "Switches off" line). Every test runs as an existing active System Administrator through System.runAs.
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
    static void inactiveTriggerNeedsNoTestClass() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = request(dev.Id);
            RlyRaiseService.Item trg = RlyReleaseTestData.item('ApexTrigger', 'OrderTrigger');
            trg.inactive = true;
            req.items = new List<RlyRaiseService.Item>{ trg, RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = [SELECT Inactive_Triggers__c, Test_Classes__c FROM RLY_Release__c WHERE Id = :relId];
            System.assertEquals('OrderTrigger', rel.Inactive_Triggers__c, 'The inactive trigger is kept on the release');
            System.assert(String.isBlank(rel.Test_Classes__c), 'No test class needed');
        }
    }

    @IsTest
    static void testRuleKeepsInactiveTriggers() {
        System.runAs(RlyTestData.admin()) {
            RlyRaiseService.Item off = RlyReleaseTestData.item('ApexTrigger', 'OrderTrigger');
            off.inactive = true;
            RlyRaiseService.Item active = RlyReleaseTestData.item('ApexTrigger', 'CaseTrigger');
            RlyRaiseService.Item flaggedClass = RlyReleaseTestData.item('ApexClass', 'OrderService');
            flaggedClass.inactive = true;
            RlyTestRule.checkTests(new List<RlyRaiseService.Item>{ off }, new Map<String, Set<String>>(), new Set<String>());
            String refused;
            try {
                RlyTestRule.checkTests(new List<RlyRaiseService.Item>{ off, flaggedClass }, new Map<String, Set<String>>(), new Set<String>());
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            System.assertEquals('This release has Apex but no test class. Select the test class that covers it.', refused,
                'Only triggers can be inactive');
            System.assertEquals('Old,OrderTrigger', RlyTestRule.inactiveField(new List<RlyRaiseService.Item>{ off, active, off, null }, 'Old, '),
                'Existing names first, each once, active triggers left out');
            System.assertEquals(null, RlyTestRule.inactiveField(new List<RlyRaiseService.Item>{ active }, null), 'None');
            System.assertEquals(null, RlyTestRule.inactiveField(null, ''), 'Nothing sent');
            List<RlyRaiseService.Item> many = new List<RlyRaiseService.Item>();
            for (Integer n = 0; n < 20; n++) {
                RlyRaiseService.Item i = RlyReleaseTestData.item('ApexTrigger', 'AVeryLongTriggerNameNumber' + n);
                i.inactive = true;
                many.add(i);
            }
            String cut = RlyTestRule.inactiveField(many, null);
            System.assert(cut.length() <= 255 && cut.endsWith('AVeryLongTriggerNameNumber8'), 'Cut at a name: ' + cut);
            RLY_Release__c rel = new RLY_Release__c(Inactive_Triggers__c = 'OrderTrigger,CaseTrigger');
            System.assertEquals(new List<String>{ 'OrderTrigger', 'CaseTrigger' }, RlyTestRule.inactiveTriggers(rel), 'Read from the field');
            System.assert(RlyTestRule.inactiveTriggers(new RLY_Release__c()).isEmpty(), 'Read without the field: none');
            System.assert(RlyTestRule.inactiveTriggers(null).isEmpty(), 'No release');
        }
    }

    @IsTest
    static void productionFromTheOrgRecord() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c intoHub = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('e'));
            update new RLY_Release__c(Id = intoHub.Id, Test_Classes__c = null, Inactive_Triggers__c = 'OrderTrigger');
            RLY_Release__c intoSit = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('f'));
            update new RLY_Release__c(Id = intoSit.Id, Test_Classes__c = null, Inactive_Triggers__c = 'OrderTrigger');
            Map<String, Object> hub = RlyPipelineOptions.forMode(RlyReleaseStore.release(intoHub.Id), 'check');
            Map<String, Object> sit = RlyPipelineOptions.forMode(RlyReleaseStore.release(intoSit.Id), 'check');
            System.assertEquals(true, hub.get('production'), 'The hub is production');
            System.assert(!hub.containsKey('tests'), 'Production, only inactive triggers: no tests list, so RunLocalTests');
            System.assertEquals(false, sit.get('production'), 'A stage is not production');
            System.assertEquals(new List<String>(), sit.get('tests'), 'Sandbox: NoTestRun');
            RLY_Release__c prodStage = new RLY_Release__c();
            prodStage.Target_Org__r = new RLY_Org__c(Role__c = 'Stage', Environment__c = 'Production');
            RLY_Release__c sandboxStage = new RLY_Release__c();
            sandboxStage.Target_Org__r = new RLY_Org__c(Role__c = 'Stage', Environment__c = 'Full_Copy');
            System.assert(RlyPipelineOptions.isProduction(prodStage), 'Environment Production counts');
            System.assert(!RlyPipelineOptions.isProduction(sandboxStage), 'A sandbox does not');
            System.assert(!RlyPipelineOptions.isProduction(new RLY_Release__c()), 'No target org read');
            String lines = RlySlackCardText.aboutLines(RlyReleaseStore.release(intoSit.Id));
            System.assert(lines.contains('Switches off: OrderTrigger'), 'The Slack card says it: ' + lines);
        }
    }

    @IsTest
    static void raiseNeedsTheDeveloperBranch() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            update new RLY_Org__c(Id = dev.Id, Branch__c = null);
            RlyRaiseService.RaiseRequest req = request(dev.Id);
            String message;
            try {
                RlyRaiseService.raise(req);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assertEquals('Give DEV1 its own branch on the Pipeline tab (for example dev1) so its releases merge instead of overwrite.',
                message, 'Refused before any callout');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release__c], 'Nothing saved');
        }
    }

    @IsTest
    static void raiseRefusesBadRequests() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            Id hubId = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id;
            List<RlyRaiseService.RaiseRequest> bad = new List<RlyRaiseService.RaiseRequest>();
            for (Integer n = 0; n < 7; n++) {
                bad.add(request(dev.Id));
            }
            bad[0].items = new List<RlyRaiseService.Item>();
            bad[1].title = ' ';
            bad[2].items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('ApexTrigger', 'AccountTrigger') };
            bad[3].testClasses = new List<String>{ 'NotSelectedTest' };
            bad[4].deletions = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
            bad[5].items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'A,B') };
            bad[6].sourceOrgId = hubId;
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
