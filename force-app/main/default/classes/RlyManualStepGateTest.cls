/**
 * @description Tests for the manual steps deploy gate and the deployment team's checks (RlyManualStepGate,
 * RlyManualStepCheck, RlyManualStepController.markRun, the gate in RlyApprovalService, RlyApprovalRuns and
 * RlyBackPromoteRun, the notice in RlyReleasePhase, the release page, list and Slack additions). Route DEV1 -> SIT -> PROD
 * (hub). Each test runs through System.runAs as an active System Administrator with Release Relay Admin (or a new user
 * without it). Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyManualStepGateTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A release into SIT with a Before deploy step and an After deploy step, both to do there.
    private static List<RLY_Manual_Step_Run__c> withSteps(RLY_Release__c rel) {
        RLY_Release__c r = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id];
        RLY_Manual_Step__c beforeStep = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Grant Region access',
            Category__c = 'Permissions', Timing__c = 'Before_Deploy', Sequence__c = 1);
        RLY_Manual_Step__c later = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Load regions',
            Category__c = 'Data', Timing__c = 'After_Deploy', Sequence__c = 2);
        insert new List<RLY_Manual_Step__c>{ beforeStep, later };
        List<RLY_Manual_Step_Run__c> runs = new List<RLY_Manual_Step_Run__c>{
            new RLY_Manual_Step_Run__c(Step__c = beforeStep.Id, Release__c = rel.Id, Org__c = r.Target_Org__c, Status__c = 'To_Do', Order__c = 1),
            new RLY_Manual_Step_Run__c(Step__c = later.Id, Release__c = rel.Id, Org__c = r.Target_Org__c, Status__c = 'To_Do', Order__c = 2) };
        insert runs;
        return runs;
    }

    private static String mark(Id runId, String status, String note) {
        return JSON.serialize(new Map<String, Object>{ 'runId' => runId, 'status' => status, 'note' => note, 'releaseId' => '' });
    }

    private static String refusal(String runJson) {
        try {
            RlyManualStepController.markRun(runJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void approvalWaitsForTheStepsBeforeDeploy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            withSteps(rel);
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.approve(rel.Id, 'Looks good');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Keeps waiting');
            System.assertEquals('Approved', saved.Approval_Status__c, 'The approval is recorded');
            System.assertEquals(UserInfo.getUserId(), saved.Approved_By__c, 'By the approver');
            System.assertEquals(null, mock.bodyFor('/dispatches'), 'No merge yet');
            System.assertEquals('Approved. Deploys when the deployment team finishes 1 manual step before deploy.', d.notice, 'Notice');
            System.assertEquals(2, d.manualOpen, 'Two open');
            System.assertEquals(1, d.manualBeforeOpen, 'One before deploy');
            System.assertEquals('2 manual steps: 1 before deploy (open), 1 after deploy', d.manualSummary, 'Summary');
            String message;
            try {
                RlyApprovalService.approveRelease(rel.Id, null);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assertEquals(d.notice, message, 'Approving again says why it waits');
        }
    }

    @IsTest
    static void lastStepBeforeDeployStartsTheMerge() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Approval_Status__c = 'Approved', Approved_By__c = UserInfo.getUserId(),
                Approved_Via__c = 'Salesforce', Approved_On__c = System.now());
            List<RLY_Manual_Step_Run__c> runs = withSteps(rel);
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyManualSteps.StepBoard b = RlyManualStepController.markRun(mark(runs[0].Id, 'Done', ' Done in Setup '));
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'The deploy starts');
            System.assertEquals('merge', saved.Pending_Run__c, 'Mode merge');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"merge"'), mock.bodyFor('/dispatches'));
            RLY_Manual_Step_Run__c run = [SELECT Status__c, Done_By__c, Done_On__c, Note__c FROM RLY_Manual_Step_Run__c WHERE Id = :runs[0].Id];
            System.assertEquals('Done', run.Status__c, 'Checked off');
            System.assertEquals(UserInfo.getUserId(), run.Done_By__c, 'By me');
            System.assertEquals('Done in Setup', run.Note__c, 'Note trimmed');
            System.assertEquals(0, b.orgs[0].beforeOpen, 'Nothing before deploy left');
            System.assertEquals(1, b.orgs[0].open, 'The after deploy step is open work');
        }
    }

    @IsTest
    static void checksNeedTheDeploymentTeamAndANote() {
        RLY_Release__c rel;
        List<RLY_Manual_Step_Run__c> runs;
        System.runAs(RlyTestData.admin()) {
            rel = RlyReleaseTestData.release('Validating', 'check');
            runs = withSteps(rel);
            System.assertEquals('Say why this manual step isn\'t needed.', refusal(mark(runs[1].Id, 'Not_Needed', ' ')), 'Note required');
            System.assertEquals('Mark the manual step To_Do, Done or Not_Needed.', refusal(mark(runs[1].Id, 'Maybe', null)), 'Known status');
            System.assertEquals('The manual step couldn\'t be read.', refusal('nope'), 'Bad JSON');
            RlyManualStepController.markRun(mark(runs[1].Id, 'Not_Needed', 'Regions already loaded'));
            RlyManualSteps.StepBoard b = RlyManualStepController.markRun(mark(runs[0].Id, 'Done', null));
            System.assertEquals('Validating', RlyReleaseTestData.reload(rel.Id).Status__c, 'Not approved yet: nothing starts');
            b = RlyManualStepController.markRun(mark(runs[0].Id, 'To_Do', null));
            System.assertEquals('To_Do', b.orgs[0].runs[0].status, 'Back to to do');
            System.assertEquals(null, b.orgs[0].runs[0].doneBy, 'Cleared');
            System.assertEquals('Not_Needed', b.orgs[0].runs[1].status, 'Not needed');
            System.assertEquals('Regions already loaded', b.orgs[0].runs[1].note, 'With its note');
        }
        System.runAs(RlyTestData.plainUser()) {
            System.assertEquals('Only the deployment team can check off manual steps.', refusal(mark(runs[0].Id, 'Done', null)),
                'Not the deployment team');
        }
    }

    @IsTest
    static void queuedSyncWaitsForItsSteps() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Org__c o = RlyTestData.org('TRAINING', 'Back_Promote', 'training');
            insert o;
            Id hubId = [SELECT Id FROM RLY_Org__c WHERE Name = 'PROD' LIMIT 1].Id;
            RLY_Release__c source = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('a'));
            RLY_Release__c sync = new RLY_Release__c(Release_Type__c = 'Back_Promote', Mode__c = 'Existing branch', Request_Type__c = 'Changes',
                Title__c = 'Back promote PROD to TRAINING', Status__c = 'Submitted', Source_Org__c = hubId, Target_Org__c = o.Id,
                Org_Label__c = 'PROD', Source_Branch__c = 'prod', Target_Branch__c = 'training', Source_Environment__c = 'prod',
                Target_Environment__c = 'training', Scan_Status__c = 'Not configured', Validation_Status__c = 'Not configured',
                Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending');
            insert sync;
            RLY_Manual_Step__c s = new RLY_Manual_Step__c(Release__c = source.Id, Title__c = 'Grant Region access',
                Timing__c = 'Before_Deploy', Category__c = 'Permissions', Sequence__c = 1, Back_Promote__c = true);
            insert s;
            RLY_Manual_Step_Run__c run = new RLY_Manual_Step_Run__c(Step__c = s.Id, Release__c = sync.Id, Org__c = o.Id, Status__c = 'To_Do');
            insert run;
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            RlyBackPromoteRun.advanceSync(RlyReleaseStore.release(sync.Id), RlyGit.forConnection(RlyReleaseStore.git()));
            System.assertEquals(null, mock.bodyFor('/dispatches'), 'Held while its step is to do');
            System.assertEquals('Deploys when the deployment team finishes 1 manual step before deploy.',
                RlyReleasesController.getRelease(sync.Id).notice, 'Notice');
            Test.startTest();
            RlyManualStepController.markRun(JSON.serialize(new Map<String, Object>{ 'runId' => run.Id, 'status' => 'Done',
                'releaseId' => sync.Id }));
            Test.stopTest();
            System.assertEquals('Deploying', RlyReleaseTestData.reload(sync.Id).Status__c, 'The sync starts');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"sync"'), mock.bodyFor('/dispatches'));
        }
    }

    @IsTest
    static void listsAndSlackShowTheSteps() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Deployed', 'merge');
            update new RLY_Release__c(Id = rel.Id, Deploy_Status__c = 'Deployed', Approval_Status__c = 'Approved');
            List<RLY_Manual_Step_Run__c> runs = withSteps(rel);
            update new RLY_Manual_Step_Run__c(Id = runs[0].Id, Status__c = 'Done');
            RLY_Release__c full = RlyReleaseStore.release(rel.Id);
            System.assert(RlySlackCardText.aboutLines(full).contains('Manual steps: 1 before deploy, 1 after deploy'),
                RlySlackCardText.aboutLines(full));
            System.assert(RlySlackCard.statusLine(full, null).contains('Deployed to SIT · 1 manual step still open in SIT'),
                RlySlackCard.statusLine(full, null));
            System.assert(RlySlackReply.forEvent(full, 'Deployed', null).contains('· 1 manual step still open in SIT'),
                RlySlackReply.forEvent(full, 'Deployed', null));
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleases('all');
            System.assertEquals(1, rows[0].manualOpen, 'One still open');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals('2 manual steps: 1 before deploy (done), 1 after deploy', d.manualSummary, 'Summary');
            System.assertEquals(null, d.notice, 'Nothing waits');
            System.assertEquals('', RlyManualStepText.stillOpen(new RLY_Release__c(), 'SIT'), 'No release, nothing open');
        }
    }
}
