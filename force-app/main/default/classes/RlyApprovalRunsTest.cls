/**
 * @description Tests for the runs an approval starts and how results are matched to runs (RlyApprovalRuns,
 * RlyApprover, RlyPipelineRun tokens, RlyReleasePhase, the new Detail fields, the approval options and the org's
 * approval and Slack fields). Each test runs as an active System Administrator holding Release Relay Admin and
 * Approver via System.runAs. Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyApprovalRunsTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Approver');
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Release__c readyValidatedWith(String sha) {
        RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Passed', Validation_Status__c = 'Passed',
            Validation_Result__c = '{"status":"Passed","mergedWith":"' + sha + '"}');
        return rel;
    }

    @IsTest
    static void approveRechecksWhenTheTargetMoved() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyValidatedWith('old111');
            RlyHttpMock mock = new RlyFlowScenario().build()
                .match('GET', '/repos/acme/release/branches/sit').reply(200, '{"commit":{"sha":"new222"}}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.approve(rel.Id, 'Ship it');
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Validating', saved.Status__c, 'Checks again, no merge');
            System.assertEquals(RlyPipelineRun.RECHECK, saved.Pending_Run__c, 'Re-check');
            System.assertEquals('Pending', saved.Approval_Status__c, 'Not approved yet');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"check"'), mock.bodyFor('/dispatches'));
            System.assertEquals(saved.Check_Token__c, RlyReleaseTestData.dispatchedOptions(mock).get('attempt'), 'Token sent as attempt');
            System.assertEquals('SIT changed after the checks passed, so they are running again.', d.notice, 'Notice');
            System.assertEquals('Release Relay ' + d.release.Name + ' (check)', RlyPipelineRun.runTitle(d.release), 'Run title');
        }
    }

    @IsTest
    static void approveMergesWhenTheTargetDidntMove() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = readyValidatedWith('same333');
            RlyHttpMock mock = new RlyFlowScenario().build()
                .match('GET', '/repos/acme/release/branches/sit').reply(200, '{"commit":{"sha":"same333"}}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.approve(rel.Id, null);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'Merging');
            System.assertEquals(RlyApprover.VIA_RELAY, saved.Approved_Via__c, 'Approved in Release Relay');
            System.assertNotEquals(null, saved.Check_Token__c, 'Merge run token');
            System.assertEquals(null, d.notice, 'No notice');
            System.assertEquals('Deploying', d.phase, 'Phase is the status');
            System.assertEquals('GitHub', d.gitProvider, 'Provider name');
            System.assertEquals(new List<String>{ 'AccountServiceTest' }, d.tests, 'Tests');
            System.assertEquals('Salesforce', d.approvedIn, 'Default approval');
        }
    }

    @IsTest
    static void gitReviewIsAnExtraWait() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            update new RLY_Org__c(Id = targetId, Approve_In_Salesforce__c = true, Require_Git_Review__c = true);
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.runMode = 'check';
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Still approved by a person first: ' + saved.Error_Message__c);
            System.assertEquals('Salesforce, then GitHub reviewers', d.approvedIn, 'Where and what comes after');
            System.assert(d.approveHere, 'Approved in Salesforce');
            RLY_Release__c deploying = new RLY_Release__c(Status__c = 'Deploying', Deploy_Status__c = 'Deploying',
                Target_Org__r = new RLY_Org__c(Name = 'Target', Require_Git_Review__c = true));
            System.assertEquals('Waiting for GitHub reviewers before deploying.', RlyReleasePhase.notice(deploying), 'Notice while it waits');
            System.assert(RlySlackCard.waitingInGit(deploying), 'The Slack card says so too');
        }
    }

    @IsTest
    static void slackOnlyOrgsAreNotApprovedInSalesforce() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'hub');
            RlyReleaseTestData.targetSlack(rel, 'Slack');
            RlyReleaseTestData.slackOn('Ready for approval');
            Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            update new RLY_Org__c(Id = targetId, Approval_In__c = null, Approve_In_Salesforce__c = false, Approve_In_Slack__c = true);
            Test.setMock(HttpCalloutMock.class, RlyReleaseTestData.withSlack(new RlyHttpMock()));
            Test.startTest();
            String refused;
            try {
                RlyApprovalService.approveRelease(rel.Id, null);
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assert(refused != null && refused.contains('Slack card'), 'Refused in Salesforce: ' + refused);
            RLY_Org__c both = new RLY_Org__c(Approve_In_Salesforce__c = true, Approve_In_Slack__c = true);
            System.assertEquals('Salesforce or Slack', RlyApprover.approvalIn(both), 'Either is enough');
            System.assert(RlyApprover.inSalesforce(new RLY_Org__c(Approve_In_Salesforce__c = false, Approve_In_Slack__c = false)),
                'Never nowhere: Salesforce stays');
            System.assert(RlyApprover.inSlack(new RLY_Org__c(Approval_In__c = 'Slack')), 'Older rows still read');
            System.assert(RlyApprover.gitReview(new RLY_Org__c(Approval_In__c = 'Git')), 'Older Git rows: reviewers after approval');
        }
    }

    @IsTest
    static void resultsMatchTheRunToken() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'resolve');
            update new RLY_Release__c(Id = rel.Id, Check_Token__c = 'tok1');
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            String earlier = System.now().addSeconds(-30).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/scan.json').reply(200, '{"status":"Passed","attempt":"tok1","finishedAt":"' + earlier + '"}')
                .match('GET', '/validate.json').reply(200, '{"status":"Conflict","attempt":"tok0","finishedAt":"' + earlier + '"}')
                .match('GET', '/deploy.json').reply(200, '{"status":"Deployed","finishedAt":"' + earlier + '"}')
                .match('GET', '/merge.json').reply(200, '{"status":"Merged","finishedAt":"2020-01-01T00:00:00.000Z"}'));
            RlyGit git = RlyGit.forConnection(RlyReleaseStore.git());
            Test.startTest();
            Map<String, Object> scan = RlyPipelineRun.result(git, read, 'scan');
            Map<String, Object> validate = RlyPipelineRun.result(git, read, 'validate');
            Map<String, Object> deploy = RlyPipelineRun.result(git, read, 'deploy');
            Map<String, Object> merged = RlyPipelineRun.result(git, read, 'merge');
            Test.stopTest();
            System.assertNotEquals(null, scan, 'Same token: this run');
            System.assertEquals(null, validate, 'The previous run\'s conflict is ignored');
            System.assertNotEquals(null, deploy, 'No attempt: the time rule (within two minutes)');
            System.assertEquals(null, merged, 'No attempt and long before: ignored');
            System.assertEquals('Resolving conflicts', RlyReleasePhase.phase(read), 'Phase while resolving');
            System.assertEquals(32, RlyPipelineRun.newToken().length(), 'Token');
        }
    }

    @IsTest
    static void approvalOptionsFollowTheConnections() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyReleaseTestData.slackOn(null);
            List<String> labels = new List<String>();
            for (RlyOrgController.ApprovalOption o : RlyOrgController.getOrgs().approvalOptions) {
                labels.add(o.value + '=' + o.label);
            }
            System.assertEquals(new List<String>{ 'Salesforce=In Salesforce', 'Slack=In Slack', 'Git=In GitHub' }, labels, 'Every option');
            System.assertEquals('GitHub', RlyReleaseStart.build().provider, 'New Release shows the provider');
        }
    }

    @IsTest
    static void orgApprovalAndSlackFields() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> input = new Map<String, Object>{ 'Name' => 'QA', 'Role__c' => 'Stage',
                'My_Domain__c' => 'https://qa.my.salesforce.com', 'Login_Type__c' => 'Sandbox', 'Username__c' => 'relay@qa.demo',
                'Consumer_Key__c' => RlyTestData.CONSUMER_KEY, 'Certificate__c' => 'release_relay', 'Branch__c' => 'qa',
                'Approval_In__c' => 'Elsewhere', 'Slack_Post__c' => false };
            Integer refused = 0;
            try { RlyOrgController.saveOrg(JSON.serialize(input)); } catch (AuraHandledException e) { refused++; }
            input.put('Approval_In__c', 'Salesforce');
            input.put('Slack_Channel__c', 'not a channel');
            try { RlyOrgController.saveOrg(JSON.serialize(input)); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(2, refused, 'Known values; channel format');
            input.put('Approval_In__c', 'Slack');
            input.put('Slack_Channel__c', ' #qa-releases ');
            input.put('Slack_Post__c', true);
            Id orgId = RlyOrgController.saveOrg(JSON.serialize(input));
            input.put('Id', orgId);
            input.remove('Consumer_Key__c');
            input.put('Approval_In__c', null);
            RlyOrgController.saveOrg(JSON.serialize(input));
            RLY_Org__c saved = [SELECT Approval_In__c, Approve_In_Salesforce__c, Approve_In_Slack__c, Slack_Channel__c, Slack_Post__c,
                                       Consumer_Key__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assertEquals(null, saved.Approval_In__c, 'Toggles replace the old field');
            System.assert(saved.Approve_In_Salesforce__c && !saved.Approve_In_Slack__c, 'Blank is Salesforce');
            input.put('Approve_In_Salesforce__c', false);
            input.put('Approve_In_Slack__c', false);
            input.put('Require_Git_Review__c', true);
            RlyOrgController.saveOrg(JSON.serialize(input));
            RLY_Org__c toggled = [SELECT Approve_In_Salesforce__c, Require_Git_Review__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assert(toggled.Approve_In_Salesforce__c, 'At least one stays on');
            System.assert(toggled.Require_Git_Review__c, 'Git reviewers required');
            System.assertEquals('#qa-releases', saved.Slack_Channel__c, 'Channel trimmed');
            System.assert(saved.Slack_Post__c, 'Posts');
            System.assertEquals(RlyTestData.CONSUMER_KEY, saved.Consumer_Key__c, 'Saved key kept');
        }
    }

    @IsTest
    static void approversAndLinks() {
        System.runAs(RlyTestData.admin()) {
            RlyApprover a = RlyApprover.currentUser('ok');
            System.assertEquals(UserInfo.getUserId(), a.userId, 'Current user');
            System.assertEquals('Bitbucket', RlyApprover.gitProvider('Bitbucket').via, 'Provider');
            System.assertEquals('Salesforce', RlyApprover.approvalIn(null), 'No org');
            System.assertEquals(null, RlyApprovalRuns.mergedWith('not json'), 'Unreadable result');
            System.assertEquals(null, RlyApprovalRuns.mergedWith(null), 'No result');
            RLY_Release__c rel = new RLY_Release__c(Slack_Channel_Id__c = 'C1', Slack_Ts__c = '1.2', Status__c = 'Closed');
            System.assert(RlyReleasePhase.slackUrl(rel).contains('channel=C1&message_ts=1.2'), RlyReleasePhase.slackUrl(rel));
            System.assertEquals('C1', RlyReleasePhase.slackChannel(rel), 'Channel id when the org has no name');
            System.assertEquals(null, RlyReleasePhase.slackChannel(new RLY_Release__c()), 'No card');
            System.assertEquals(null, RlyReleasePhase.slackUrl(new RLY_Release__c()), 'No card link');
        }
    }
}
