/**
 * @description Tests for promotions (RlyPromoteController, RlyPromotion, RlyCarried, RlyPromoteStore, RlyReleaseEffects,
 * RlyReleaseLinks, RlySlackCardText and the promotion parts of RlyStatusReader, RlyCheckReader, RlyPipelineRun,
 * RlyPipelineOptions and RlyDeployReader). Route DEV1 -> SIT -> PROD (hub). Each test runs through System.runAs: as an
 * active System Administrator with Release Relay Admin, or as a new user without it. Records are inserted before
 * Test.startTest; callouts come after it.
 */
@IsTest
private class RlyPromoteTest {

    private static final String SHA_A = RlyReleaseTestData.sha('a');
    private static final String SHA_B = RlyReleaseTestData.sha('b');

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    // Two releases deployed to SIT: an older one, and a newer hotfix.
    private static List<RLY_Release__c> waitingInSit() {
        RlyReleaseTestData.route();
        RLY_Release__c older = RlyReleaseTestData.deployedIn('SIT', SHA_A);
        RLY_Release__c hotfix = RlyReleaseTestData.deployedIn('SIT', SHA_B);
        update new RLY_Release__c(Id = hotfix.Id, Is_Hotfix__c = true, Hotfix_Reason__c = 'Duplicate emails',
            Last_Synced__c = System.now().addMinutes(-5));
        return new List<RLY_Release__c>{ older, hotfix };
    }

    private static String request(List<RLY_Release__c> rels, String title) {
        List<Id> ids = new List<Id>();
        for (RLY_Release__c r : rels) {
            ids.add(r.Id);
        }
        return JSON.serialize(new Map<String, Object>{ 'stageId' => orgId('SIT'), 'releaseIds' => ids, 'title' => title });
    }

    private static String refusal(String requestJson) {
        try {
            RlyPromoteController.promote(requestJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void boardListsHotfixesFirst() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            RlyPromoteController.PromoteBoard board = RlyPromoteController.getPromote();
            System.assert(board.canPromote, 'Admins promote');
            System.assertEquals(1, board.stages.size(), 'SIT has a next stop; the hub has none');
            RlyPromoteController.PromoteStage s = board.stages[0];
            System.assertEquals('SIT', s.stageName, 'From SIT');
            System.assertEquals('PROD', s.nextName, 'To the hub');
            System.assertEquals('prod', s.nextBranch, 'Its branch');
            System.assertEquals(2, s.ready.size(), 'Both wait');
            System.assertEquals(rels[1].Id, s.ready[0].id, 'The hotfix first');
            System.assert(s.ready[0].isHotfix, 'Marked');
            System.assertEquals('Duplicate emails', s.ready[0].hotfixReason, 'With its reason');
            System.assertEquals(new List<String>{ 'AccountServiceTest' }, s.ready[1].tests, 'Tests carried');
            System.assertEquals(1, s.ready[1].componentCount, 'Components');
        }
    }

    @IsTest
    static void promoteSavesTheQueuedPromotion() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(rels, ' Promote 2 releases to PROD '));
            RLY_Release__c p = RlyReleaseTestData.reload(promotionId);
            System.assertEquals('Promotion', p.Release_Type__c, 'A promotion');
            System.assertEquals('Submitted', p.Status__c, 'Queued: it starts on its page');
            System.assertEquals(orgId('SIT'), p.Source_Org__c, 'From SIT');
            System.assertEquals(orgId('PROD'), p.Target_Org__c, 'To its next stop');
            System.assertEquals('prod', p.Target_Branch__c, 'Into the next stop\'s branch');
            System.assertEquals(rels[0].Id + ',' + rels[1].Id, p.Carried_Releases__c, 'Oldest deploy first');
            System.assertEquals(true, p.Is_Hotfix__c, 'Carries a hotfix');
            System.assertEquals('Duplicate emails', p.Hotfix_Reason__c, 'Its reason');
            System.assertEquals('AccountServiceTest', p.Test_Classes__c, 'Tests, each once');
            System.assertEquals(2, p.Component_Count__c, 'Components of both');
            System.assertEquals(promotionId, RlyReleaseTestData.reload(rels[0].Id).Promoted_In__c, 'Carried releases point to it');
            System.assert(RlyPromoteController.getPromote().stages[0].ready.isEmpty(), 'Nothing waits any more');
            String again = refusal(request(rels, 'Again'));
            System.assert(again.contains('aren\'t waiting in SIT'), again);

            RlyReleasesController.Detail d = RlyReleasesController.getRelease(promotionId);
            System.assertEquals('Promotion', d.releaseType, 'Type on the page');
            System.assertEquals(2, d.carried.size(), 'Carries both');
            System.assertEquals('Starting the pipeline run.', d.notice, 'Waiting to start');
            System.assert(d.running, 'The page keeps checking');
            RlyReleasesController.Detail carried = RlyReleasesController.getRelease(rels[0].Id);
            System.assertEquals(promotionId, carried.promotedInId, 'Promoted in');
            System.assert(String.isNotBlank(carried.promotedInName), 'With its number');
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleases('all');
            System.assertEquals(2, rows[0].carried.size() + rows[1].carried.size() + rows[2].carried.size(), 'The promotion row lists what it carries');
        }
    }

    @IsTest
    static void promoteRefusesBadRequests() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            System.assertEquals('Pick at least one release to promote.', refusal(request(new List<RLY_Release__c>(), 'X')), 'Nothing picked');
            System.assertEquals('Give the promotion a title (up to 200 characters).', refusal(request(rels, ' ')), 'No title');
            String noStage = refusal(JSON.serialize(new Map<String, Object>{ 'stageId' => orgId('DEV1'), 'releaseIds' => new List<Id>{ rels[0].Id },
                'title' => 'X' }));
            System.assertEquals('Pick a stage to promote from.', noStage, 'Only stages promote');
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Status__c = 'Failed');
            System.assert(refusal(request(rels, 'X')).contains('Git connection'), 'Needs a checked connection');
            update new RLY_Org__c(Id = orgId('PROD'), Branch__c = null);
            System.assert(refusal(request(rels, 'X')).contains('has no branch'), 'Needs the next stop\'s branch');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            System.assert(!RlyPromoteController.getPromote().canPromote, 'Not an approver');
            System.assert(refusal('{}').contains('Only approvers'), 'Refused');
        }
    }

    @IsTest
    static void queuedPromotionStartsOnItsPage() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(rels, 'Promote 2 releases to PROD'));
            RLY_Release__c p = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :promotionId];
            RlyHttpMock mock = RlyFlowScenario.forRelease(p).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(promotionId);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(promotionId);
            String dispatched = mock.bodyFor('/dispatches');
            System.assertEquals('Workflow running', saved.Status__c, 'Started: ' + saved.Error_Message__c);
            System.assertEquals('promote', saved.Pending_Run__c, 'Mode promote');
            System.assertEquals('promote/' + p.Name.toLowerCase(), saved.Source_Branch__c, 'Promote branch');
            System.assert(dispatched.contains('"mode":"promote"'), dispatched);
            System.assert(dispatched.contains(SHA_A + ',' + SHA_B), 'Merge commits, oldest first: ' + dispatched);
            System.assert(dispatched.contains('"target":"prod"'), 'Into the next stop\'s branch');
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('validateMerged'), 'Validated merged');
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('hub'), 'Hub run');
            System.assertEquals('sit', RlyReleaseTestData.dispatchedOptions(mock).get('stageBranch'), 'The next stop gets the stage\'s files');
            System.assert(d.running, 'Still running');
        }
    }

    @IsTest
    static void failedPromoteRunShowsWhyAndFreesTheReleases() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(rels, 'Promote'));
            RLY_Release__c p = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :promotionId];
            update new RLY_Release__c(Id = promotionId, Status__c = 'Workflow running', Pending_Run__c = 'promote',
                Source_Branch__c = 'promote/' + p.Name.toLowerCase(), Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(p);
            scenario.runMode = 'promote';
            scenario.runStatus = 'completed';
            scenario.runConclusion = 'failure';
            scenario.prState = 'none';
            scenario.results.put('raise', RlyReleaseTestData.result('raise', '"status":"Failed","message":"aaaaaaa doesn\'t apply cleanly on prod"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(promotionId);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(promotionId);
            System.assertEquals('Failed', saved.Status__c, 'Failed');
            System.assertEquals('aaaaaaa doesn\'t apply cleanly on prod', saved.Error_Message__c, 'raise.json says why');
            System.assertEquals(null, RlyReleaseTestData.reload(rels[0].Id).Promoted_In__c, 'Free to be promoted again');
            System.assertEquals(2, RlyPromoteController.getPromote().stages[0].ready.size(), 'Waiting again');
        }
    }

    @IsTest
    static void mergeIntoTheHubMergesBackDown() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            insert RlyTestData.org('DEV2', 'Developer', 'dev2');
            Id promotionId = RlyPromoteController.promote(request(rels, 'Promote'));
            update new RLY_Release__c(Id = promotionId, Status__c = 'Ready for approval', PR_Number__c = 42, Source_Branch__c = 'promote/x');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.approve(promotionId, 'Ship it');
            Test.stopTest();
            System.assertEquals(new List<Object>{ 'sit', 'dev1', 'dev2' }, RlyReleaseTestData.dispatchedOptions(mock).get('syncBranches'),
                'Stage branches in route order, then the developer branches');
            System.assertEquals('Deploying', RlyReleaseTestData.reload(promotionId).Status__c, 'Merging');
        }
    }

    @IsTest
    static void backMergeIsShownPerBranch() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(rels, 'Promote'));
            RLY_Release__c p = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :promotionId];
            update new RLY_Release__c(Id = promotionId, Status__c = 'Deploying', Pending_Run__c = 'merge', Deploy_Status__c = 'Deploying',
                Checks_Requested__c = System.now().addMinutes(-1));
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(p);
            scenario.runMode = 'merge';
            scenario.results.put('merge', RlyReleaseTestData.result('merge', '"status":"Merged","sha":"' + RlyReleaseTestData.sha('c')
                + '","sync":[{"branch":"sit","status":"Synced","message":"sit now includes prod."},'
                + '{"branch":"dev1","status":"Conflict","message":"dev1 couldn\'t take prod"}]'));
            scenario.results.put('deploy', RlyReleaseTestData.result('deploy', '"status":"Deployed","testsRun":1'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(promotionId);
            Test.stopTest();
            System.assertEquals('Deployed', d.release.Status__c, 'Deployed: ' + d.release.Error_Message__c);
            System.assertEquals(2, d.backMerge.size(), 'Each branch');
            System.assertEquals('Stage', d.backMerge[0].kind, 'sit is a stage branch');
            System.assertEquals('Developer', d.backMerge[1].kind, 'dev1 is a developer branch');
            System.assertEquals('Conflict', d.backMerge[1].status, 'To review');
            System.assertEquals('Off', d.backPromote, 'Back promote is off by default');
            System.assert(!d.running, 'Nothing more to check');
            System.assertEquals(0, RlyReleaseLinks.backMerge('not json').size(), 'Unreadable results show nothing');
        }
    }

    @IsTest
    static void rejectedPromotionFreesItsReleasesAndSlackSaysWhatItCarries() {
        System.runAs(RlyTestData.admin()) {
            List<RLY_Release__c> rels = waitingInSit();
            Id promotionId = RlyPromoteController.promote(request(rels, 'Promote'));
            update new RLY_Release__c(Id = promotionId, Status__c = 'Ready for approval');
            RLY_Release__c read = RlyReleaseStore.release(promotionId);
            System.assert(RlySlackCardText.title(read).startsWith('Hotfix: '), RlySlackCardText.title(read));
            String about = RlySlackCardText.aboutLines(read);
            System.assert(about.contains('Why: Duplicate emails'), about);
            System.assert(about.contains('Promotes ' + rels[0].Name + ', '), about);
            System.assertEquals('', RlySlackCardText.aboutLines(new RLY_Release__c()), 'Nothing for a plain release');
            RlyApprovalService.rejectRelease(promotionId, 'Not this week');
            System.assertEquals('Rejected', RlyReleaseTestData.reload(promotionId).Status__c, 'Rejected');
            System.assertEquals(null, RlyReleaseTestData.reload(rels[1].Id).Promoted_In__c, 'Free to be promoted again');
            List<RlyReleasesController.Row> approvals = RlyReleasesController.listReleases('approvals');
            System.assert(approvals.isEmpty(), 'Nothing waits');
        }
    }

    @IsTest
    static void approvalsListHotfixesFirst() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c plain = RlyReleaseTestData.release('Ready for approval', 'hub');
            Id devId = orgId('DEV1');
            Id sitId = orgId('SIT');
            RLY_Release__c hotfix = new RLY_Release__c(Title__c = 'Hotfix', Status__c = 'Ready for approval', Source_Org__c = devId,
                Target_Org__c = sitId, Target_Branch__c = 'sit', Is_Hotfix__c = true, Hotfix_Reason__c = 'Urgent');
            insert hotfix;
            List<RlyReleasesController.Row> rows = RlyReleasesController.listReleases('approvals');
            System.assertEquals(2, rows.size(), 'Both wait');
            System.assertEquals(hotfix.Id, rows[0].id, 'The hotfix first, though it is newer');
            System.assertEquals('Urgent', rows[0].hotfixReason, 'With its reason');
            System.assertEquals(plain.Id, rows[1].id, 'Then oldest first');
        }
    }
}
