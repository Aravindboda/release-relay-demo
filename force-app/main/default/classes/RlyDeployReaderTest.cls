/**
 * @description Tests for reading an approved release's merge and deploy (RlyDeployReader). Each test runs as an
 * active System Administrator via System.runAs. Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyDeployReaderTest {

    private static final String MERGED = '"status":"Merged","sha":"0123456789abcdef0123456789abcdef01234567"';

    private static RlyFlowScenario deploying(RLY_Release__c rel) {
        RlyOrgSession.testToken = RlyTestData.TOKEN;
        RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
        scenario.runMode = 'merge';
        return scenario;
    }

    @IsTest
    static void deployedAfterMerge() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            RlyFlowScenario scenario = deploying(rel);
            scenario.results.put('merge', RlyReleaseTestData.result('merge', MERGED));
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', '"status":"Deployed","testsRun":3'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deployed', saved.Status__c, 'Deployed: ' + saved.Error_Message__c);
            System.assertEquals('0123456789abcdef0123456789abcdef01234567', saved.Merge_Commit__c, 'Merge commit');
        }
    }

    @IsTest
    static void deployFailureIsShown() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            RlyFlowScenario scenario = deploying(rel);
            scenario.results.put('merge', RlyReleaseTestData.result('merge', MERGED));
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', '"status":"Failed","message":"1 component error(s)"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploy failed', saved.Status__c, 'Deploy failed');
            System.assertEquals('1 component error(s)', saved.Error_Message__c, 'Reason shown');
        }
    }

    @IsTest
    static void mergeFailureIsShown() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            RlyFlowScenario scenario = deploying(rel);
            scenario.results.put('merge', RlyReleaseTestData.result('merge', '"status":"Failed","message":"Conflicts"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Deploy failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Merge failed');
        }
    }

    @IsTest
    static void runFailedBeforeDeployResult() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deploying', 'merge');
            RlyFlowScenario scenario = deploying(rel);
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Deploy failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Run failed');
        }
    }
}
