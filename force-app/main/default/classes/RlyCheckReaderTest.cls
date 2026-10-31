/**
 * @description Tests for reading a release's checks (RlyCheckReader: pull request, code scan, validation, decide)
 * and bypassing a blocking scan. Each test runs as an active System Administrator via System.runAs.
 * Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyCheckReaderTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    private static RlyFlowScenario checking(RLY_Release__c rel) {
        RlyOrgSession.testToken = RlyTestData.TOKEN;
        return RlyFlowScenario.forRelease(rel);
    }

    @IsTest
    static void cleanChecksAreReadyForApproval() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":2,"blocking":0,"thresholdLabel":"High"'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed","testLevel":"RunSpecifiedTests","testsRun":3'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Low findings don\'t block: ' + saved.Error_Message__c);
            System.assertEquals(42, saved.PR_Number__c, 'Pull request read');
            System.assertEquals(2, saved.Scan_Violations__c, 'Findings counted');
            System.assert(saved.Run_URL__c.contains('/runs/555'), 'Run linked');
        }
    }

    @IsTest
    static void blockingScanCanBeBypassed() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Failed","total":3,"blocking":1'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Checks failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'A blocking finding stops it');
            Boolean needsReason = false;
            try {
                RlyReleasesController.bypassScan(rel.Id, 'ok');
            } catch (AuraHandledException e) {
                needsReason = true;
            }
            System.assert(needsReason, 'A real reason is required');
            RlyReleasesController.bypassScan(rel.Id, 'False positive: the SOQL is bound and limited.');
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Bypassed', saved.Scan_Status__c, 'Bypassed');
            System.assertEquals('Ready for approval', saved.Status__c, 'Validation passed, so it can be approved');
        }
    }

    @IsTest
    static void failedValidationCantBeBypassed() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Failed","message":"1 test failure(s)"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Checks failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Failed validation stops it');
            Boolean refused = false;
            try {
                RlyApprovalService.acceptScanFindings(rel.Id, 'Trying to skip the validation');
            } catch (RlyReleaseException e) {
                refused = true;
            }
            System.assert(refused, 'Only a failed scan can be bypassed');
        }
    }

    @IsTest
    static void pipelineFailureWithoutPullRequestFails() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.prState = 'none';
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Failed', RlyReleaseTestData.reload(rel.Id).Status__c, 'The raise failed');
        }
    }

    @IsTest
    static void finishedRunWithoutResultsIsAnError() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            // A result from an earlier run is ignored.
            scenario.results.put('scan', '{"status":"Passed","finishedAt":"2020-01-01T00:00:00.000Z"}');
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Error', saved.Scan_Status__c, 'Old result ignored');
            System.assertEquals('Checks failed', saved.Status__c, 'Not stuck');
        }
    }

    @IsTest
    static void conflictFailsTheValidation() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            Map<String, Object> conflict = (Map<String, Object>) JSON.deserializeUntyped(RlyReleaseTestData.conflictResult());
            conflict.put('finishedAt', System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));
            scenario.results.put('validate', JSON.serialize(conflict));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Failed', saved.Validation_Status__c, 'A conflict fails the validation (no Conflict value)');
            System.assertEquals('Checks failed', saved.Status__c, 'And stops the release before approval');
            System.assertEquals(2, RlyConflictResult.filesOf(saved.Validation_Result__c).size(), 'The conflicting files are kept');
        }
    }

    @IsTest
    static void resolveRunWithoutResultsIsAnError() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'resolve');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            RlyFlowScenario scenario = checking(rel);
            scenario.runMode = 'resolve';
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Error', saved.Scan_Status__c, 'No scan result');
            System.assertEquals('Error', saved.Validation_Status__c, 'No validation result');
            System.assertEquals('Checks failed', saved.Status__c, 'Not stuck, and the pull request stays');
        }
    }

    @IsTest
    static void closedPullRequestClosesTheRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RlyFlowScenario scenario = checking(rel);
            scenario.prState = 'closed';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            System.assertEquals('Closed', RlyReleaseTestData.reload(rel.Id).Status__c, 'Closed in GitHub');
        }
    }
}
