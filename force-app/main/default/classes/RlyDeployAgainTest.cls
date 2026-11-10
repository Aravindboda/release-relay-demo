/**
 * @description Tests for Deploy again (RlyDeployAgain, build 58.1): an approved release whose deploy failed starts the
 * merge and deploy again and History says so; anything else is refused. Runs as an active System Administrator via
 * System.runAs with the Release Relay admin permission set; records are inserted before Test.startTest and callouts
 * come after it.
 */
@IsTest
private class RlyDeployAgainTest {

    private static RLY_Release__c failedDeploy() {
        RLY_Release__c rel = RlyReleaseTestData.release('Deploy failed', null);
        update new RLY_Release__c(Id = rel.Id, Approval_Status__c = 'Approved', Approved_By__c = UserInfo.getUserId(),
            Approved_On__c = System.now(), Error_Message__c = 'Metadata API request failed: REQUEST_LIMIT_EXCEEDED');
        return RlyReleaseStore.release(rel.Id);
    }

    @IsTest
    static void approvedFailedDeployStartsAgain() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = failedDeploy();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.runMode = 'merge';
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Boolean mayBefore = RlyDeployAgain.mayDeployAgain(rel);
            Test.startTest();
            RlyReleasesController.Detail d = RlyDeployAgain.deployAgain(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseStore.release(rel.Id);
            List<RLY_Release_Event__c> events = [SELECT Detail__c FROM RLY_Release_Event__c
                                                 WHERE Release__c = :rel.Id AND Event_Type__c = :RlyDeployAgain.EVENT];
            System.assert(mayBefore, 'An admin may deploy an approved failed release again');
            System.assertEquals('Deploying', saved.Status__c, 'The deploy runs again');
            System.assertEquals(null, saved.Error_Message__c, 'The old error is cleared');
            System.assertEquals('Approved', saved.Approval_Status__c, 'The approval stays');
            System.assertEquals(false, d.canDeployAgain, 'No second button while it runs');
            System.assertEquals(1, events.size(), 'History says so');
            System.assert(events[0].Detail__c.contains('REQUEST_LIMIT_EXCEEDED'), 'With the error it follows: ' + events[0].Detail__c);
        }
    }

    @IsTest
    static void onlyApprovedFailedDeploysStartAgain() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseStore.release(RlyReleaseTestData.release('Deployed', null).Id);
            String refused;
            Test.startTest();
            try {
                RlyDeployAgain.deployAgain(rel.Id);
            } catch (Exception e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertNotEquals(null, refused, 'A deployed release can\'t be deployed again');
            System.assertEquals(false, RlyDeployAgain.mayDeployAgain(null), 'No release');
            System.assertEquals(false, RlyDeployAgain.mayDeployAgain(rel), 'Not a failed deploy');
        }
    }
}
