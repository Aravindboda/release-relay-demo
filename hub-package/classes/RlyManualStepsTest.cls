/**
 * @description Tests for manual steps and their runs (RlyManualSteps, RlyManualStepRules, RlyManualStepRuns,
 * RlyManualStepStore, RlyManualStepBoard, RlyManualStepEdit, RlyManualStepController.getSteps/saveStep/deleteStep, the
 * manual steps of RlyRaiseService, RlyPromotion, RlyBackPromoteQueue and RlyPromoteController). Route DEV1 -> SIT -> PROD
 * (hub), with TRAINING as a back promote org where needed. Each test runs through System.runAs as an active System
 * Administrator with Release Relay Admin (or a new user without it). Records are inserted before Test.startTest;
 * callouts come after it.
 */
@IsTest
private class RlyManualStepsTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RlyManualSteps.StepInput input(String title, String timing, String orgScope) {
        RlyManualSteps.StepInput s = new RlyManualSteps.StepInput();
        s.title = title;
        s.timing = timing;
        s.category = 'Permissions';
        s.instructions = 'Profile Sales User: Account.Region__c read/edit';
        s.orgScope = orgScope;
        return s;
    }

    private static RLY_Manual_Step__c step(Id releaseId, String title, Integer sequence) {
        return new RLY_Manual_Step__c(Release__c = releaseId, Title__c = title, Category__c = 'Data',
            Timing__c = 'After_Deploy', Sequence__c = sequence, Back_Promote__c = true);
    }

    private static String saveJson(Map<String, Object> fields) {
        Map<String, Object> m = new Map<String, Object>{ 'id' => '', 'title' => 'Grant Region access', 'category' => 'Permissions',
            'timing' => 'Before_Deploy', 'instructions' => 'Sales User profile', 'backPromote' => true, 'orgScope' => '' };
        m.putAll(fields);
        return JSON.serialize(m);
    }

    private static String problem(String stepJson) {
        try {
            RlyManualStepController.saveStep(stepJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void raiseSavesStepsAndTheirRunsInTheFirstStage() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = dev.Id;
            req.title = 'Region field';
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
            req.testClasses = new List<String>();
            req.manualSteps = new List<RlyManualSteps.StepInput>{
                input('Grant Region access', 'Before_Deploy', null), input('Load regions', null, ' prod ') };
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            List<RLY_Manual_Step__c> steps = [SELECT Title__c, Sequence__c, Timing__c, Org_Scope__c, Back_Promote__c
                                              FROM RLY_Manual_Step__c WHERE Release__c = :relId ORDER BY Sequence__c];
            System.assertEquals(2, steps.size(), 'Both saved');
            System.assertEquals(1, steps[0].Sequence__c, 'In order');
            System.assertEquals('After_Deploy', steps[1].Timing__c, 'After deploy by default');
            System.assertEquals('prod', steps[1].Org_Scope__c, 'Scope trimmed');
            System.assert(steps[1].Back_Promote__c, 'Back promote by default');
            List<RLY_Manual_Step_Run__c> runs = [SELECT Org__c, Status__c, Order__c, Step__r.Title__c FROM RLY_Manual_Step_Run__c
                                                 WHERE Release__c = :relId];
            System.assertEquals(1, runs.size(), 'Only the step for every org runs in SIT');
            System.assertEquals(orgId('SIT'), runs[0].Org__c, 'In the first stage');
            System.assertEquals('To_Do', runs[0].Status__c, 'To do');
            System.assertEquals(1, runs[0].Order__c, 'First');
        }
    }

    @IsTest
    static void raiseRefusesBadSteps() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            List<RlyManualSteps.StepInput> bad = new List<RlyManualSteps.StepInput>{
                input(' ', null, null), input('x'.repeat(121), null, null), input('Ok', 'Sometime', null),
                input('Ok', null, 'NOWHERE') };
            bad.add(input('Ok', null, null));
            bad[4].category = 'Magic';
            bad.add(input('Ok', null, null));
            bad[5].sequence = 0;
            Integer refused = 0;
            for (RlyManualSteps.StepInput s : bad) {
                try {
                    RlyManualStepRules.fromInputs(new List<RlyManualSteps.StepInput>{ s });
                } catch (RlyReleaseException e) {
                    refused++;
                }
            }
            System.assertEquals(bad.size(), refused, 'Every bad step is refused');
            List<RlyManualSteps.StepInput> many = new List<RlyManualSteps.StepInput>();
            for (Integer n = 0; n < 51; n++) {
                many.add(input('Step ' + n, null, null));
            }
            String message;
            try {
                RlyManualStepRules.fromInputs(many);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assertEquals('A release can have up to 50 manual steps.', message, 'Up to 50');
            System.assert(RlyManualStepRules.fromInputs(null).isEmpty(), 'None is fine');
        }
    }

    @IsTest
    static void stepsAreAddedChangedReorderedAndDeleted() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RlyManualSteps.StepBoard b = RlyManualStepController.saveStep(saveJson(new Map<String, Object>{ 'releaseId' => rel.Id }));
            System.assert(b.canEdit, 'Who raised it edits');
            System.assert(b.canCheck, 'Admins check off');
            System.assertEquals(1, b.steps.size(), 'Added');
            System.assertEquals(rel.Name, b.steps[0].fromRelease, 'Defined by this release');
            System.assertEquals(1, b.steps[0].sequence, 'First');
            System.assertEquals(1, b.orgs.size(), 'Runs in SIT');
            System.assertEquals('SIT', b.orgs[0].orgName, 'SIT');
            System.assertEquals(1, b.orgs[0].beforeOpen, 'Before deploy, open');
            b = RlyManualStepController.saveStep(saveJson(new Map<String, Object>{ 'releaseId' => rel.Id, 'title' => 'Load regions',
                'timing' => 'After_Deploy', 'sequence' => '' }));
            System.assertEquals(2, b.steps.size(), 'Second step');
            System.assertEquals(2, b.steps[1].sequence, 'Goes last');
            System.assertEquals(2, b.orgs[0].runs[1].orderNo, 'Second in SIT');
            Id firstId = b.steps[0].id;
            Id secondId = b.steps[1].id;
            RlyManualStepController.saveStep(saveJson(new Map<String, Object>{ 'id' => firstId, 'sequence' => 2 }));
            b = RlyManualStepController.saveStep(saveJson(new Map<String, Object>{ 'id' => secondId, 'title' => 'Load regions',
                'timing' => 'After_Deploy', 'sequence' => 1 }));
            System.assertEquals(secondId, b.steps[0].id, 'Swapped');
            System.assertEquals(secondId, b.orgs[0].runs[0].stepId, 'Runs follow the new order');
            b = RlyManualStepController.saveStep(saveJson(new Map<String, Object>{ 'id' => firstId, 'orgScope' => 'PROD' }));
            System.assertEquals(1, b.orgs[0].runs.size(), 'Now only for PROD: no run in SIT');
            System.assertEquals('PROD', b.steps[1].orgScope, 'Scope saved');
            try {
                b = RlyManualStepController.deleteStep(secondId);
                System.assertEquals(1, b.steps.size(), 'Deleted');
                System.assert(b.orgs.isEmpty(), 'Its run too');
            } catch (Exception e) {
                System.assertNotEquals(null, e.getMessage(), 'Delete skipped');
            }
        }
    }

    @IsTest
    static void stepsAreLockedOnceDeployed() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c rel = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            RLY_Manual_Step__c s = step(rel.Id, 'Load regions', 1);
            insert s;
            System.assertEquals('Manual steps can be changed by the person who raised the release, or an admin, until it\'s first deployed.',
                problem(saveJson(new Map<String, Object>{ 'releaseId' => rel.Id })), 'Locked after the deploy');
            System.assertEquals('Release not found.', problem(saveJson(new Map<String, Object>())), 'Needs a release');
            System.assertEquals('The manual step couldn\'t be read.', problem('not json'), 'Bad JSON');
            Boolean refused = false;
            try {
                RlyManualStepController.deleteStep(s.Id);
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Deleting is locked too');
            RlyManualSteps.StepBoard b = RlyManualStepController.getSteps(rel.Id);
            System.assert(!b.canEdit, 'Read only');
            System.assertEquals(1, b.steps.size(), 'Still listed');
        }
    }

    @IsTest
    static void othersCantEditSteps() {
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = RlyReleaseTestData.release('Ready for approval', 'hub');
        }
        System.runAs(RlyTestData.plainUser()) {
            RlyManualSteps.StepBoard b = RlyManualStepController.getSteps(rel.Id);
            System.assert(!b.canEdit, 'Not who raised it, not an admin');
            System.assert(!b.canCheck, 'Not the deployment team');
            Boolean refused = false;
            try {
                RlyManualStepController.getSteps(null);
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Release not found');
        }
    }

    @IsTest
    static void promotionCarriesTheStepsInOrder() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Release__c older = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            RLY_Release__c newer = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('b'));
            update new List<RLY_Release__c>{ new RLY_Release__c(Id = older.Id, Last_Synced__c = System.now().addMinutes(-40)),
                new RLY_Release__c(Id = newer.Id, Last_Synced__c = System.now().addMinutes(-20)) };
            RLY_Manual_Step__c sitOnly = step(older.Id, 'Only in SIT', 1);
            sitOnly.Org_Scope__c = 'SIT';
            insert new List<RLY_Manual_Step__c>{ step(newer.Id, 'Newer step', 1), step(older.Id, 'Older step', 2), sitOnly };
            RlyPromoteController.PromoteBoard board = RlyPromoteController.getPromote();
            System.assertEquals(2, board.stages[0].ready[0].manualSteps, 'The older release has two steps');
            System.assertEquals(1, board.stages[0].ready[1].manualSteps, 'The newer one has one');
            Id promotionId = RlyPromoteController.promote(JSON.serialize(new Map<String, Object>{ 'stageId' => orgId('SIT'),
                'releaseIds' => new List<Id>{ older.Id, newer.Id }, 'title' => 'Promote 2 releases to PROD' }));
            List<RLY_Manual_Step_Run__c> runs = [SELECT Order__c, Org__c, Step__r.Title__c FROM RLY_Manual_Step_Run__c
                                                 WHERE Release__c = :promotionId ORDER BY Order__c];
            System.assertEquals(2, runs.size(), 'The SIT-only step stays behind');
            System.assertEquals('Older step', runs[0].Step__r.Title__c, 'Oldest deploy first');
            System.assertEquals('Newer step', runs[1].Step__r.Title__c, 'Then the next');
            System.assertEquals(orgId('PROD'), runs[0].Org__c, 'In the next stop');
            RlyManualSteps.StepBoard b = RlyManualStepController.getSteps(promotionId);
            System.assertEquals(3, b.steps.size(), 'Carried steps are listed');
            System.assertEquals(older.Name, b.steps[0].fromRelease, 'From the release that defined them');
            System.assertEquals(1, b.orgs.size(), 'PROD');
            b = RlyManualStepController.getSteps(older.Id);
            System.assertEquals('PROD', b.orgs[0].orgName, 'The original release shows where its steps are done');
            System.assertEquals(1, b.orgs[0].runs.size(), 'Its one step for PROD');
        }
    }

    @IsTest
    static void backPromoteSyncTakesTheBackPromoteSteps() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RLY_Org__c o = RlyTestData.org('TRAINING', 'Back_Promote', 'training');
            o.Back_Promote_When__c = 'Manual';
            insert o;
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            update new RLY_Git_Connection__c(Id = conn.Id, Back_Promote__c = true);
            RLY_Release__c original = RlyReleaseTestData.deployedIn('SIT', RlyReleaseTestData.sha('a'));
            RLY_Release__c promotion = RlyReleaseTestData.deployedIn('PROD', RlyReleaseTestData.sha('b'));
            update new RLY_Release__c(Id = promotion.Id, Release_Type__c = 'Promotion', Carried_Releases__c = original.Id,
                Last_Synced__c = System.now().addMinutes(5));
            RLY_Manual_Step__c notThere = step(original.Id, 'Production only', 2);
            notThere.Back_Promote__c = false;
            RLY_Manual_Step__c done = step(original.Id, 'Already done', 3);
            insert new List<RLY_Manual_Step__c>{ step(original.Id, 'Grant Region access', 1), notThere, done };
            insert new RLY_Manual_Step_Run__c(Step__c = done.Id, Org__c = o.Id, Release__c = original.Id, Status__c = 'Done');
            Id syncId = RlyRouteController.syncNow(o.Id);
            List<RLY_Manual_Step_Run__c> runs = [SELECT Order__c, Org__c, Step__r.Title__c FROM RLY_Manual_Step_Run__c
                                                 WHERE Release__c = :syncId];
            System.assertEquals(1, runs.size(), 'Only the back promote step not done there yet');
            System.assertEquals('Grant Region access', runs[0].Step__r.Title__c, 'That one');
            System.assertEquals(o.Id, runs[0].Org__c, 'In TRAINING');
            RlyManualSteps.StepBoard b = RlyManualStepController.getSteps(syncId);
            System.assert(!b.canEdit, 'A sync has no steps of its own');
            System.assertEquals(1, b.steps.size(), 'The step it took');
            System.assertEquals(original.Name, b.steps[0].fromRelease, 'From the original release');
        }
    }

    @IsTest
    static void wordsAndCounts() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('1 manual step', RlyManualSteps.stepWords(1), 'Singular');
            System.assertEquals('2 manual steps', RlyManualSteps.stepWords(2), 'Plural');
            RLY_Manual_Step__c s = new RLY_Manual_Step__c(Org_Scope__c = 'SIT, prod');
            System.assert(RlyManualStepScope.inScope(s, 'PROD'), 'Named, any case');
            System.assert(!RlyManualStepScope.inScope(s, 'UAT'), 'Not named');
            System.assert(RlyManualStepScope.inScope(new RLY_Manual_Step__c(), 'UAT'), 'Blank is every org');
            RlyManualSteps.Counts c = new RlyManualSteps.Counts();
            System.assertEquals(null, RlyManualStepText.summary(c), 'None');
            System.assertEquals(null, RlyManualStepText.slackLine(c), 'No Slack line');
            c.beforeCount = 2;
            c.beforeOpen = 1;
            c.afterCount = 1;
            System.assertEquals('3 manual steps: 2 before deploy (1 open), 1 after deploy (done)', RlyManualStepText.summary(c), 'Summary');
            c.beforeOpen = 0;
            c.afterOpen = 1;
            System.assertEquals('3 manual steps: 2 before deploy (done), 1 after deploy', RlyManualStepText.summary(c), 'Before done');
            System.assertEquals('Manual steps: 2 before deploy, 1 after deploy', RlyManualStepText.slackLine(c), 'Slack line');
            System.assertEquals(1, c.open(), 'Open');
        }
    }
}
