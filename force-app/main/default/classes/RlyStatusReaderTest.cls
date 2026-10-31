/**
 * @description Tests for moving a release along after the retrieve (RlyStatusReader, RlyRetrieve.check, RlyPipelineRun,
 * the release parts of RlyGitHub, and RlyReleasesController.refreshRelease). Each test runs as an active System
 * Administrator via System.runAs. Records are inserted before Test.startTest, so each test makes one callout
 * sequence followed by its DML.
 */
@IsTest
private class RlyStatusReaderTest {

    @IsTest
    static void retrieveDoneStartsThePipeline() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            String dispatched = mock.bodyFor('/dispatches');
            System.assertEquals('Workflow running', saved.Status__c, 'Pipeline started: ' + saved.Error_Message__c);
            System.assertEquals('feature/' + rel.Name.toLowerCase(), saved.Source_Branch__c, 'Release branch');
            System.assertEquals('hub', saved.Pending_Run__c, 'Hub mode');
            System.assert(dispatched.contains('"mode":"hub"'), 'Hub mode dispatched: ' + dispatched);
            System.assert(dispatched.contains('AccountServiceTest'), 'Tests go in the options');
            System.assert(mock.callLog().contains('PUT callout:RLY_GitHub/repos/acme/release/contents/.relay-inbox/'), 'Zip committed');
            System.assert(d.running, 'Still running');
        }
    }

    @IsTest
    static void retrieveStillRunning() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Pending';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Retrieving', RlyReleaseTestData.reload(rel.Id).Status__c, 'Keeps waiting');
        }
    }

    @IsTest
    static void retrieveProblemsFailTheRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Problems';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Failed', saved.Status__c, 'A missing component fails it');
            System.assert(saved.Error_Message__c.contains('Gone'), 'Names the component: ' + saved.Error_Message__c);
        }
    }

    @IsTest
    static void retrieveErrorFailsTheRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.retrieveState = 'Failed';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Failed', saved.Status__c, 'Retrieve failed');
            System.assert(saved.Error_Message__c.contains('INVALID_CROSS_REFERENCE_KEY'), saved.Error_Message__c);
        }
    }

    @IsTest
    static void unreachableGitKeepsTheStatus() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Provider__c = 'GitLab', Repository__c = 'acme/release');
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Validating', saved.Status__c, 'Unchanged');
            System.assert(saved.Error_Message__c.contains('GitHub'), 'Says what is supported: ' + saved.Error_Message__c);
        }
    }
}
