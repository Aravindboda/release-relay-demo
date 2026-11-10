/**
 * @description Tests for releases with only manual steps (RlyManualOnly and its paths in RlyRaiseService, RlyRaiseRules,
 * RlyStatusReader, RlyApprovalRuns, RlyApprovalService, RlyAutoApproval, RlyApprovalRules, RlyManualStepCheck,
 * RlyManualStepEdit, RlyPromotion, RlyPromoteStore, RlyReleasePhase, RlySlackCard, RlyEvidenceHtml and the release rows).
 * Route DEV1 -> SIT -> PROD (hub). Each test runs through System.runAs as an active System Administrator with Release
 * Relay Admin. Nothing here makes a callout: a release with only manual steps has no retrieve, branch or pipeline run.
 */
@IsTest
private class RlyManualOnlyTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RlyManualSteps.StepInput step(String title, String timing) {
        RlyManualSteps.StepInput s = new RlyManualSteps.StepInput();
        s.title = title;
        s.instructions = 'Profile Sales User: Account.Region__c read/edit';
        s.category = 'Permissions';
        s.timing = timing;
        s.backPromote = true;
        return s;
    }

    // Raises a release from DEV1 with only these manual steps (route included).
    private static Id raiseSteps(List<RlyManualSteps.StepInput> steps) {
        RLY_Org__c dev = RlyReleaseTestData.route();
        RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
        req.sourceOrgId = dev.Id;
        req.title = 'Region access for Sales';
        req.items = new List<RlyRaiseService.Item>();
        req.testClasses = new List<String>();
        req.manualSteps = steps;
        return RlyReleasesController.raiseRelease(JSON.serialize(req));
    }

    private static String mark(Id runId, String status) {
        return JSON.serialize(new Map<String, Object>{ 'runId' => runId, 'status' => status, 'note' => 'Done by hand', 'releaseId' => '' });
    }

    private static List<RLY_Manual_Step_Run__c> runsOf(Id relId) {
        return [SELECT Id, Status__c, Step__r.Timing__c FROM RLY_Manual_Step_Run__c WHERE Release__c = :relId ORDER BY Order__c];
    }

    private static String detailOf(Id relId, String eventType) {
        List<RLY_Release_Event__c> rows = [SELECT Detail__c FROM RLY_Release_Event__c WHERE Release__c = :relId AND Event_Type__c = :eventType];
        return rows.isEmpty() || rows[0].Detail__c == null ? '' : rows[0].Detail__c;
    }

    private static RLY_Release__c saved(Id relId) {
        return [SELECT Status__c, Manual_Only__c, Retrieve_Id__c, Scan_Status__c, Validation_Status__c, Approval_Status__c,
                       Approved_Via__c, Deploy_Status__c, Pending_Run__c, Source_Branch__c, Component_Count__c, Release_Type__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    @IsTest
    static void raisedWithoutMetadataGoesToApprovalThenDeploysWhenTheStepsAreDone() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_AFTER) });
            RLY_Release__c rel = saved(relId);
            System.assertEquals(true, rel.Manual_Only__c, 'Marked manual steps only');
            System.assertEquals('Submitted', rel.Status__c, 'Queued for its first read');
            System.assertEquals(null, rel.Retrieve_Id__c, 'No retrieve');
            System.assertEquals('Not configured', rel.Scan_Status__c, 'No scan');
            System.assertEquals('Not configured', rel.Validation_Status__c, 'No validation');
            System.assertEquals('Release', rel.Release_Type__c, 'Still a release');
            System.assertEquals(1, runsOf(relId).size(), 'A run in SIT');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(relId);
            System.assertEquals('Manual steps only: no pipeline run. Going to approval.', d.notice, 'Queued notice');

            d = RlyReleasesController.refreshRelease(relId);
            System.assertEquals('Ready for approval', d.release.Status__c, 'At the approval point of SIT');
            System.assertEquals(null, saved(relId).Source_Branch__c, 'No Git branch');

            d = RlyReleasesController.approve(relId, 'Fine');
            System.assertEquals('Deploying', d.release.Status__c, 'Waits for the step after deploy');
            System.assertEquals('Manual steps only: deployed in SIT when the deployment team finishes 1 manual step.', d.notice, 'Notice');
            System.assertEquals(null, saved(relId).Pending_Run__c, 'No pipeline run');
            d = RlyReleasesController.refreshRelease(relId);
            System.assertEquals('Deploying', d.release.Status__c, 'Still open');

            RlyManualStepController.markRun(mark(runsOf(relId)[0].Id, 'Done'));
            Test.stopTest();
            rel = saved(relId);
            System.assertEquals('Deployed', rel.Status__c, 'Deployed when every step is done');
            System.assertEquals('Deployed', rel.Deploy_Status__c, 'Deploy step done');
            System.assert(detailOf(relId, 'Deployed').contains('manual steps only'), 'History says how');
            System.assert(detailOf(relId, 'Raised').contains('manual steps only: 1 manual step'), 'Raised event');
        }
    }

    @IsTest
    static void stepsBeforeDeployHoldItThenTheLastCheckFinishesIt() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_BEFORE),
                step('Load regions', RlyManualSteps.TIMING_AFTER) });
            RlyReleasesController.refreshRelease(relId);
            RlyReleasesController.approve(relId, null);
            RLY_Release__c rel = saved(relId);
            System.assertEquals('Ready for approval', rel.Status__c, 'Approved, waits for the step before deploy');
            System.assertEquals('Approved', rel.Approval_Status__c, 'Approval recorded');
            List<RLY_Manual_Step_Run__c> runs = runsOf(relId);
            RlyManualStepController.markRun(mark(runs[0].Id, 'Done'));
            System.assertEquals('Deploying', saved(relId).Status__c, 'Started: the step after deploy is open');
            RlyManualStepController.markRun(mark(runs[1].Id, 'Not_Needed'));
            Test.stopTest();
            System.assertEquals('Deployed', saved(relId).Status__c, 'Done and Not needed finish it');
        }
    }

    @IsTest
    static void neverRuleApprovesAutomaticallyAndNoStepsInTheOrgDeploysAtOnce() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyManualSteps.StepInput onlyProd = step('Grant Region access', RlyManualSteps.TIMING_AFTER);
            onlyProd.orgScope = 'PROD';
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ onlyProd });
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id, Approval_Rule__c = 'Never');
            RlyReleasesController.refreshRelease(relId);
            Test.stopTest();
            RLY_Release__c rel = saved(relId);
            System.assertEquals('Approved', rel.Approval_Status__c, 'Approved by the rule');
            System.assertEquals('Rule', rel.Approved_Via__c, 'Via the rule');
            System.assertEquals('Deployed', rel.Status__c, 'No step to do in SIT');
        }
    }

    @IsTest
    static void hubNeverNeedsAnApproverAndWords() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c hub = new RLY_Org__c(Name = 'PROD', Role__c = 'Hub', Approval_Rule__c = 'Never');
            RLY_Release__c rel = new RLY_Release__c(Target_Org__r = hub);
            RlyApprovalRules.Contents c = new RlyApprovalRules.Contents();
            c.manualSteps = true;
            System.assertEquals(true, RlyApprovalRules.decideFor(rel, c).needed, 'The hub always needs approval');
            hub.Role__c = 'Stage';
            hub.Approval_Rule__c = 'Selected_Types';
            hub.Approval_Types__c = 'Apex';
            System.assertEquals('Approved automatically: only manual steps', RlyApprovalRules.decideFor(rel, c).reason, 'Words');
            System.assertEquals(false, RlyManualOnly.isManualOnly(null), 'Null is not');
            System.assertEquals(false, RlyManualOnly.allManualOnly(new List<RLY_Release__c>()), 'Nothing carried');
        }
    }

    @IsTest
    static void refusesAnEmptyReleaseAndDeletingTheLastStep() {
        System.runAs(RlyTestData.admin()) {
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_AFTER) });
            RlyRaiseService.RaiseRequest empty = new RlyRaiseService.RaiseRequest();
            empty.title = 'Nothing';
            empty.manualSteps = new List<RlyManualSteps.StepInput>();
            String message;
            try {
                RlyRaiseRules.checkRequest(empty);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assertEquals('Select at least one component.', message, 'Needs a component or a manual step');
            Id stepId = [SELECT Id FROM RLY_Manual_Step__c WHERE Release__c = :relId].Id;
            message = null;
            try {
                RlyManualStepController.deleteStep(stepId);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertEquals('A release with only manual steps needs at least one. Change this step instead.', message, 'Keeps one');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Manual_Step__c WHERE Release__c = :relId], 'Still there');
        }
    }

    @IsTest
    static void promotingOnlyManualStepReleasesIsManualOnly() {
        System.runAs(RlyTestData.admin()) {
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_AFTER) });
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
            update new RLY_Release__c(Id = relId, Status__c = 'Deployed', Approval_Status__c = 'Approved', Deploy_Status__c = 'Deployed');
            Test.startTest();
            RlyPromoteController.PromoteBoard board = RlyPromoteController.getPromote();
            System.assertEquals(1, board.stages[0].ready.size(), 'Ready without a merge commit');
            System.assertEquals(true, board.stages[0].ready[0].manualOnly, 'Marked');
            Id promotionId = RlyPromoteController.promote(JSON.serialize(new Map<String, Object>{
                'stageId' => sitId, 'releaseIds' => new List<Id>{ relId }, 'title' => 'Promote access' }));
            RLY_Release__c p = saved(promotionId);
            System.assertEquals(true, p.Manual_Only__c, 'Only manual steps');
            System.assertEquals('Promotion', p.Release_Type__c, 'A promotion');
            System.assertEquals(1, runsOf(promotionId).size(), 'Its steps carried to PROD');
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(promotionId);
            Test.stopTest();
            System.assertEquals('Ready for approval', d.release.Status__c, 'No promote run: straight to approval');
            System.assertEquals(true, d.carried[0].manualOnly, 'Carried release marked');
        }
    }

    @IsTest
    static void mixedPromotionPicksOnlyTheMergeCommits() {
        System.runAs(RlyTestData.admin()) {
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_AFTER) });
            Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT'].Id;
            update new RLY_Release__c(Id = relId, Status__c = 'Deployed', Approval_Status__c = 'Approved', Deploy_Status__c = 'Deployed');
            RLY_Release__c merged = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            Test.startTest();
            Id promotionId = RlyPromoteController.promote(JSON.serialize(new Map<String, Object>{
                'stageId' => sitId, 'releaseIds' => new List<Id>{ relId, merged.Id }, 'title' => 'Promote both' }));
            Test.stopTest();
            RLY_Release__c p = [SELECT Id, Manual_Only__c, Status__c, Carried_Releases__c FROM RLY_Release__c WHERE Id = :promotionId];
            System.assertEquals(false, p.Manual_Only__c, 'Has metadata');
            System.assertEquals('Submitted', p.Status__c, 'Its promote run starts on the next read');
            System.assertEquals(RlyReleaseTestData.sha('a'), RlyCarried.mergeCommits(p), 'Only the merge commit is picked');
            System.assertEquals(1, runsOf(promotionId).size(), 'The manual steps travel too');
        }
    }

    @IsTest
    static void cardEvidenceAndRowsSkipTheGitLines() {
        System.runAs(RlyTestData.admin()) {
            Id relId = raiseSteps(new List<RlyManualSteps.StepInput>{ step('Grant Region access', RlyManualSteps.TIMING_AFTER) });
            RLY_Release__c rel = RlyReleaseStore.release(relId);
            rel.Status__c = 'Ready for approval';
            String steps = RlySlackCard.stepsLine(rel);
            System.assert(steps.contains(RlyManualOnly.NOT_NEEDED), 'Slack: not needed');
            System.assert(!steps.contains('PR'), 'Slack: no pull request');
            System.assert(RlySlackCardText.aboutLines(rel).contains(RlyManualOnly.PILL), 'Slack: pill line');
            rel.Status__c = 'Deployed';
            rel.Approval_Status__c = 'Approved';
            rel.Deploy_Status__c = 'Deployed';
            System.assert(RlySlackCard.stepsLine(rel).contains('Manual steps done'), 'Slack: done');
            rel.Approval_Status__c = 'Rejected';
            rel.Deploy_Status__c = 'Pending';
            System.assert(RlySlackCard.stepsLine(rel).contains(RlySlackCard.FAILED), 'Slack: rejected');
            RlyEvidenceHtml.Source src = new RlyEvidenceHtml.Source();
            src.rel = rel;
            String html = RlyEvidenceHtml.build(src);
            System.assert(html.contains(RlyManualOnly.NOT_NEEDED), 'Evidence: not needed');
            System.assert(!html.contains('Merge commit'), 'Evidence: no merge commit');
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleases('all');
            System.assertEquals(true, rows[0].manualOnly, 'Row marked');
        }
    }
}
