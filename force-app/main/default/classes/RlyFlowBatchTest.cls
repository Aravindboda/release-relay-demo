/**
 * @description Tests for RlyFlowBatch: a deployed release activates its flows at most PER_READ per read, Flow_Results__c
 * being the cursor per org, and its page shows the progress while flows are left. No callouts: the releases are built in
 * memory. Every test runs as an active System Administrator through System.runAs.
 */
@IsTest
private class RlyFlowBatchTest {

    // A deployed release into SIT that activates n flows (Flow_1 … Flow_n), with these results.
    private static RLY_Release__c deployed(Integer n, String resultsJson) {
        List<Map<String, Object>> actions = new List<Map<String, Object>>();
        for (Integer i = 1; i <= n; i++) {
            actions.add(new Map<String, Object>{ 'name' => 'Flow_' + i, 'choice' => RlyFlowChoices.CHOICE_ACTIVATE });
        }
        Id sitId = Id.valueOf(RlyTestData.fakeId(RLY_Org__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix(), 3));
        return new RLY_Release__c(Status__c = 'Deployed', Target_Org__c = sitId, Target_Org__r = new RLY_Org__c(Id = sitId, Name = 'SIT'),
            Flow_Actions__c = JSON.serialize(actions), Flow_Results__c = resultsJson);
    }

    private static String results(String org, List<String> flows) {
        List<Object> out = new List<Object>();
        for (String f : flows) {
            out.add(new Map<String, Object>{ 'org' => org, 'flow' => f, 'status' => RlyFlowActivation.ACTIVATED, 'version' => 2 });
        }
        return JSON.serialize(out);
    }

    @IsTest
    static void eachReadTakesTheNextFlows() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c fresh = deployed(12, null);
            RLY_Release__c half = deployed(12, results('SIT', new List<String>{ 'Flow_1', 'Flow_2', 'Flow_3' }));
            Test.startTest();
            List<String> first = RlyFlowBatch.nextNames(fresh, 'SIT', RlyFlowActivation.namesFor(fresh));
            List<String> next = RlyFlowBatch.nextNames(half, 'SIT', RlyFlowActivation.namesFor(half));
            List<String> otherOrg = RlyFlowBatch.nextNames(half, 'PROD', RlyFlowActivation.namesFor(half));
            Test.stopTest();
            System.assertEquals(RlyFlowBatch.PER_READ, first.size(), 'At most PER_READ in one read');
            System.assertEquals('Flow_1', first[0], 'In the release\'s order');
            System.assertEquals('Flow_4', next[0], 'Flows with a result are done');
            System.assertEquals(RlyFlowBatch.PER_READ, next.size(), 'The next batch');
            System.assertEquals('Flow_1', otherOrg[0], 'Results count per org');
        }
    }

    @IsTest
    static void thePageKeepsCheckingWhileFlowsAreLeft() {
        System.runAs(RlyTestData.admin()) {
            List<String> eight = new List<String>();
            for (Integer i = 1; i <= 8; i++) {
                eight.add('Flow_' + i);
            }
            RLY_Release__c partly = deployed(30, results('SIT', eight));
            RLY_Release__c finished = deployed(2, results('SIT', new List<String>{ 'Flow_1', 'Flow_2' }));
            RLY_Release__c open = deployed(5, null);
            open.Status__c = 'Deploying';
            RLY_Release__c older = deployed(5, null);
            Test.startTest();
            Boolean olderPending = RlyFlowBatch.hasPending(older);
            Boolean partlyPending = RlyFlowBatch.hasPending(partly);
            String progress = RlyFlowBatch.progress(partly);
            Boolean finishedPending = RlyFlowBatch.hasPending(finished);
            Boolean openPending = RlyFlowBatch.hasPending(open);
            RLY_Release__c same = RlyFlowBatch.continueAfterDeploy(finished, 5);
            Test.stopTest();
            System.assert(partlyPending, '22 flows left');
            System.assertEquals('Activating flows: 8 of 30', progress, 'Progress for the page');
            System.assert(!finishedPending, 'Every flow has a result');
            System.assertEquals(null, RlyFlowBatch.progress(finished), 'No progress once done');
            System.assert(!openPending, 'Only a deployed release activates');
            System.assert(!olderPending, 'A deployed release with nothing activated in its org (before build 37) is left alone');
            System.assert(same === finished, 'Nothing left: the release comes back as it is');
            System.assertEquals(null, RlyFlowBatch.continueAfterDeploy(null, 5), 'No release, nothing to do');
        }
    }

    @IsTest
    static void theNextReadActivatesTheRest() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deployed', null);
            RLY_Release__c built = deployed(10, null);
            List<String> eight = new List<String>();
            for (Integer i = 1; i <= RlyFlowBatch.PER_READ; i++) {
                eight.add('Flow_' + i);
            }
            update new RLY_Release__c(Id = rel.Id, Flow_Actions__c = built.Flow_Actions__c, Flow_Results__c = results('SIT', eight));
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/tooling/query/').reply(200, '{"records":['
                    + '{"Id":"300000000000009","DeveloperName":"Flow_9","ActiveVersion":{"VersionNumber":1},"LatestVersion":{"VersionNumber":2,"Status":"Draft"}},'
                    + '{"Id":"300000000000010","DeveloperName":"Flow_10","ActiveVersion":{"VersionNumber":3},"LatestVersion":{"VersionNumber":3,"Status":"Active"}}]}')
                .match('POST', '/FlowDefinition/300000000000009').reply(204, ''));
            Test.startTest();
            RlySharedRead.refresh(rel.Id, 0);
            Test.stopTest();
            Map<String, String> byFlow = new Map<String, String>();
            for (RlyFlowResults.FlowResult r : RlyFlowResults.forRelease([SELECT Flow_Results__c, Flow_Actions__c, Target_Org__r.Name FROM RLY_Release__c WHERE Id = :rel.Id])) {
                byFlow.put(r.flow, r.status);
            }
            System.assertEquals(10, byFlow.size(), 'Every flow has a result now: ' + byFlow);
            System.assertEquals(RlyFlowActivation.ACTIVATED, byFlow.get('Flow_9'), 'The next batch activated');
            System.assertEquals(RlyFlowActivation.ALREADY_ACTIVE, byFlow.get('Flow_10'), 'Already active');
        }
    }
}
