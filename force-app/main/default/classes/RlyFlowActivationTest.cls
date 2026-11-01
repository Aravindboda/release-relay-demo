/**
 * @description Tests for flow versions and activation: the After deploy choices (RlyFlowChoices, raising with them in
 * RlyRaiseService), reading versions (RlyFlowVersions through RlyChangesController.flowVersions), activating after a
 * deploy (RlyFlowActivation through RlyStatusReader) and the results on the release page (RlyFlowResults). Every test
 * runs as an active System Administrator via System.runAs. Records are inserted before Test.startTest; callouts after.
 */
@IsTest
private class RlyFlowActivationTest {

    private static final String DEPLOYED = '"status":"Deployed","testsRun":3,"deployId":"0Af000000000009"';

    // versions: "active,latest,status", for example "7,8,Draft".
    private static String flowRecord(String name, String versions) {
        List<String> v = versions.split(',');
        Integer active = Integer.valueOf(v[0]);
        Integer latest = Integer.valueOf(v[1]);
        String status = v[2];
        return '{"Id":"3000000000000' + latest + active + '","DeveloperName":"' + name + '","ActiveVersion":'
            + '{"VersionNumber":' + active + '}' + ',"LatestVersion":{"VersionNumber":' + latest
            + ',"Status":"' + status + '"}}';
    }

    private static String definitions() {
        return '{"records":[' + flowRecord('Case_Escalation', '7,8,Draft') + ',' + flowRecord('Lead_Router', '3,3,Active') + ','
            + flowRecord('Quote_Sync', '1,2,Draft') + ']}';
    }

    @IsTest
    static void versionsAreReadFromTheDeveloperOrg() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/tooling/query/').reply(200, definitions()));
            Test.startTest();
            List<RlyFlowVersions.FlowInfo> infos = RlyChangesController.flowVersions(dev.Id,
                new List<String>{ 'Case_Escalation', 'Missing_Flow', 'not a flow!' });
            Test.stopTest();
            System.assertEquals(2, infos.size(), 'A name that can\'t be a flow is left out');
            System.assertEquals(8, infos[0].latest, 'Latest version');
            System.assertEquals(7, infos[0].active, 'Active version');
            System.assertEquals('Draft', infos[0].latestStatus, 'Latest status');
            System.assertEquals(null, infos[1].latest, 'Not in the org');
            System.assertEquals(0, RlyChangesController.flowVersions(dev.Id, null).size(), 'Nothing asked');
        }
    }

    @IsTest
    static void deployActivatesTheChosenFlows() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            update new RLY_Release__c(Id = rel.Id, Flow_Actions__c = RlyFlowChoices.toField(new List<RlyFlowChoices.FlowChoice>{
                RlyFlowChoices.choiceOf('Case_Escalation', RlyFlowChoices.CHOICE_ACTIVATE),
                RlyFlowChoices.choiceOf('Lead_Router', RlyFlowChoices.CHOICE_ACTIVATE),
                RlyFlowChoices.choiceOf('Quote_Sync', RlyFlowChoices.CHOICE_ACTIVATE),
                RlyFlowChoices.choiceOf('Gone_Flow', RlyFlowChoices.CHOICE_ACTIVATE),
                RlyFlowChoices.choiceOf('Kept_Flow', RlyFlowChoices.CHOICE_KEEP) }));
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.runMode = 'merge';
            scenario.results.put('merge', RlyReleaseTestData.result('merge', '"status":"Merged","sha":"' + RlyReleaseTestData.sha('a') + '"'));
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', DEPLOYED));
            RlyHttpMock mock = scenario.build()
                .match('GET', '/tooling/query/').reply(200, definitions())
                .match('POST', '/FlowDefinition/300000000000087').reply(204, '')
                .match('POST', '/FlowDefinition/300000000000021').reply(400, '[{"message":"Not enough flow test coverage","errorCode":"FIELD_INTEGRITY_EXCEPTION"}]');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assert(mock.bodyFor('/FlowDefinition/300000000000087').contains('"activeVersionNumber":8'), 'Latest version activated');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals('Deployed', d.release.Status__c, 'Deployed');
            Map<String, RlyFlowResults.FlowResult> byFlow = new Map<String, RlyFlowResults.FlowResult>();
            for (RlyFlowResults.FlowResult r : d.flows) {
                byFlow.put(r.flow, r);
            }
            System.assertEquals(4, byFlow.size(), 'One result per chosen flow: ' + byFlow.keySet());
            System.assertEquals(RlyFlowActivation.ACTIVATED, byFlow.get('Case_Escalation').status, 'Activated');
            System.assertEquals(RlyFlowActivation.ALREADY_ACTIVE, byFlow.get('Lead_Router').status, 'Already active');
            System.assertEquals(RlyFlowActivation.FAILED, byFlow.get('Quote_Sync').status, 'Refused');
            System.assert(byFlow.get('Quote_Sync').message.contains('coverage'), 'Reason kept: ' + byFlow.get('Quote_Sync').message);
            System.assertEquals(RlyFlowActivation.FAILED, byFlow.get('Gone_Flow').status, 'Missing flow');
            System.assert(RlyFlowResults.line(byFlow.get('Quote_Sync')).contains('SIT failed'), 'Line');
            System.assert(RlyFlowResults.line(byFlow.get('Case_Escalation')).contains('SIT v8 active'), 'Line');
            Integer activations = 0;
            for (RlyReleaseHistory.EventRow e : d.events) {
                activations += e.eventType == 'Flow_Activated' ? 1 : 0;
            }
            System.assertEquals(4, activations, 'History per flow');
        }
    }

    @IsTest
    static void signInFailureFailsEveryFlow() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Org__c sit = RlyReleaseStore.org([SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/tooling/query/').reply(500, 'down'));
            Test.startTest();
            List<RlyFlowActivation.Outcome> outcomes = RlyFlowActivation.activateAll(sit, new List<String>{ 'A_Flow', 'B_Flow' });
            Test.stopTest();
            System.assertEquals(2, outcomes.size(), 'Both reported');
            System.assertEquals(RlyFlowActivation.FAILED, outcomes[1].status, 'Failed');
            String merged = RlyFlowActivation.merged('[{"org":"SIT","flow":"A_Flow","status":"Activated"},"junk"]', outcomes);
            System.assertEquals(2, RlyFlowResults.parse(merged).size(), 'Newest result per org and flow');
            System.assertEquals(0, RlyFlowResults.parse('not json').size(), 'Unreadable is empty');
        }
    }

    @IsTest
    static void raiseKeepsTheChoicesAndAddsSteps() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = dev.Id;
            req.title = 'Escalations';
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Flow', 'Case_Escalation'), RlyReleaseTestData.item('Flow', 'Lead_Router') };
            req.testClasses = new List<String>();
            req.flowChoices = new List<RlyFlowChoices.FlowChoice>{
                RlyFlowChoices.choiceOf('Case_Escalation', RlyFlowChoices.CHOICE_INACTIVE),
                RlyFlowChoices.choiceOf('Lead_Router', RlyFlowChoices.CHOICE_ACTIVATE) };
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = [SELECT Flow_Actions__c FROM RLY_Release__c WHERE Id = :relId];
            System.assertEquals(new List<String>{ 'Lead_Router' }, RlyFlowChoices.toActivate(rel), 'Activate kept');
            List<RLY_Manual_Step__c> steps = [SELECT Title__c, Category__c, Timing__c FROM RLY_Manual_Step__c WHERE Release__c = :relId];
            System.assertEquals(1, steps.size(), 'A step for the flow left inactive');
            System.assertEquals('Activate flow Case_Escalation', steps[0].Title__c, 'Step title');
            System.assertEquals(RlyManualSteps.TIMING_AFTER, steps[0].Timing__c, 'After deploy');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c = :relId AND Event_Type__c = 'Raised'], 'Raised event');
        }
    }

    @IsTest
    static void choicesAreCheckedAndCombined() {
        System.runAs(RlyTestData.admin()) {
            Set<String> flows = new Set<String>{ 'A_Flow', 'B_Flow' };
            List<List<RlyFlowChoices.FlowChoice>> bad = new List<List<RlyFlowChoices.FlowChoice>>{
                new List<RlyFlowChoices.FlowChoice>{ RlyFlowChoices.choiceOf('A_Flow', 'Maybe') },
                new List<RlyFlowChoices.FlowChoice>{ RlyFlowChoices.choiceOf('C_Flow', RlyFlowChoices.CHOICE_KEEP) },
                new List<RlyFlowChoices.FlowChoice>{ RlyFlowChoices.choiceOf('A_Flow', null), RlyFlowChoices.choiceOf('A_Flow', null) } };
            Integer refused = 0;
            for (List<RlyFlowChoices.FlowChoice> b : bad) {
                try {
                    RlyFlowChoices.checked(b, flows);
                } catch (RlyReleaseException e) {
                    refused++;
                }
            }
            System.assertEquals(3, refused, 'Unknown choice, unknown flow, a flow twice');
            System.assertEquals(RlyFlowChoices.CHOICE_KEEP, RlyFlowChoices.checked(new List<RlyFlowChoices.FlowChoice>{
                RlyFlowChoices.choiceOf('B_Flow', ' ') }, flows)[0].choice, 'Blank is Keep');
            System.assertEquals(null, RlyFlowChoices.toField(null), 'Nothing stored');
            RLY_Release__c first = new RLY_Release__c(Flow_Actions__c = '[{"name":"A_Flow","choice":"Keep"},{"name":"B_Flow","choice":"Inactive"}]');
            RLY_Release__c second = new RLY_Release__c(Flow_Actions__c = '[{"name":"A_Flow","choice":"Activate"},{"name":"B_Flow","choice":"Keep"}]');
            RLY_Release__c merged = new RLY_Release__c(Flow_Actions__c = RlyFlowChoices.toField(RlyFlowChoices.union(
                new List<RLY_Release__c>{ first, second, new RLY_Release__c(Flow_Actions__c = 'junk') })));
            System.assertEquals(new List<String>{ 'A_Flow' }, RlyFlowChoices.toActivate(merged), 'Activate wins over Keep');
            System.assertEquals(2, RlyFlowChoices.fromRelease(merged).size(), 'Each flow once');
            System.assertEquals(RlyFlowChoices.CHOICE_ACTIVATE, RlyFlowResults.forRelease(new RLY_Release__c(
                Flow_Results__c = '[{"org":"SIT","flow":"Z_Flow","version":2,"status":"Activated"}]'))[0].choice, 'Default choice');
        }
    }
}
