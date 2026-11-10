/**
 * @description Tests for approval rules per org (RlyApprovalRules, RlyApprovalWords, RlyApprovalRuleOrg) and approving
 * by rule when the checks pass (RlyAutoApproval through RlyStatusReader). Every test runs as an active System
 * Administrator via System.runAs. Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyApprovalRulesTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    private static void ruleOnTarget(RLY_Release__c rel, String rule, String types) {
        Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
        update new RLY_Org__c(Id = targetId, Approval_Rule__c = rule, Approval_Types__c = types);
    }

    private static RlyHttpMock passingChecks(RLY_Release__c rel) {
        RlyOrgSession.testToken = RlyTestData.TOKEN;
        RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
        scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
        scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed","testsRun":3,"deployId":"0Af000000000001"'));
        return scenario.build();
    }

    @IsTest
    static void neverRuleApprovesAndStartsTheDeploy() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            ruleOnTarget(rel, RlyApprovalRules.RULE_NEVER, null);
            RlyHttpMock mock = passingChecks(rel);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Deploying', saved.Status__c, 'Deploy started: ' + saved.Error_Message__c);
            System.assertEquals('Rule', saved.Approved_Via__c, 'Approved by rule');
            System.assertEquals(null, saved.Approved_By__c, 'No approver');
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"merge"'), 'Merge dispatched');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assert(d.approvalReason.startsWith('Approved automatically: SIT'), d.approvalReason);
            Set<String> kinds = new Set<String>();
            for (RlyReleaseHistory.EventRow e : d.events) {
                kinds.add(e.eventType);
            }
            System.assert(kinds.contains('Auto_Approved') && kinds.contains('Validation') && kinds.contains('Scan'), 'History: ' + kinds);
        }
    }

    @IsTest
    static void selectedTypesNeedsApprovalForApex() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            ruleOnTarget(rel, RlyApprovalRules.RULE_SELECTED, 'Apex;Flows');
            Test.setMock(HttpCalloutMock.class, passingChecks(rel));
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Waits for an approver');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(rel.Id);
            System.assertEquals('Needs approval: contains an Apex class', d.approvalReason, 'Why');
            System.assert(RlyReleaseHistory.slackLine(RlyReleaseStore.release(rel.Id)).contains('Needs approval'), 'Slack card says why');
        }
    }

    @IsTest
    static void ruleApprovalWaitsForManualSteps() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Workflow running', 'hub');
            ruleOnTarget(rel, RlyApprovalRules.RULE_NEVER, null);
            Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            RLY_Manual_Step__c step = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Assign access', Category__c = 'Permissions',
                Timing__c = RlyManualSteps.TIMING_BEFORE);
            insert step;
            insert new RLY_Manual_Step_Run__c(Step__c = step.Id, Release__c = rel.Id, Org__c = targetId, Status__c = RlyManualSteps.STATUS_TO_DO);
            Test.setMock(HttpCalloutMock.class, passingChecks(rel));
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Ready for approval', saved.Status__c, 'Waits for the manual step');
            System.assertEquals('Approved', saved.Approval_Status__c, 'Approved by rule');
            System.assertEquals('Rule', saved.Approved_Via__c, 'Via the rule');
        }
    }

    @IsTest
    static void decisionsAndWords() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c target = new RLY_Org__c(Name = 'QA', Approval_Rule__c = RlyApprovalRules.RULE_SELECTED,
                Approval_Types__c = 'Hotfix;Deletions;Manual_Steps;Profiles_Permissions');
            RLY_Release__c rel = new RLY_Release__c(Target_Org__r = target);
            RlyApprovalRules.Contents c = new RlyApprovalRules.Contents();
            c.metadataTypes.addAll(new List<String>{ 'Report', 'ListView', 'Layout' });
            RlyApprovalRules.Decision d = RlyApprovalRules.decideFor(rel, c);
            System.assertEquals(false, d.needed, 'Only reports');
            System.assertEquals('Approved automatically: only page layouts, list views and reports', d.reason, 'Words');
            c.hotfix = true;
            c.deletes = true;
            c.manualSteps = true;
            c.metadataTypes.add('Profile');
            d = RlyApprovalRules.decideFor(rel, c);
            System.assertEquals(true, d.needed, 'Needs approval');
            System.assertEquals('Needs approval: is a hotfix and contains a Profile, deletions and manual steps', d.reason, 'Words');
            target.Approval_Rule__c = null;
            System.assertEquals('Always needs approval in QA', RlyApprovalRules.decideFor(rel, c).reason, 'Blank is Always');
            System.assertEquals('Always', RlyApprovalWords.ruleText(target), 'Card line');
            target.Approval_Rule__c = RlyApprovalRules.RULE_SELECTED;
            target.Approval_Types__c = 'Flows;Apex';
            System.assertEquals('Only when the release contains: Apex classes and triggers, Flows', RlyApprovalWords.ruleText(target), 'Card line');
            System.assertEquals(RlyApprovalRules.TYPE_OTHER, RlyApprovalRules.bucketOf('Layout'), 'Layout is Other');
            System.assertEquals(RlyApprovalRules.TYPE_OBJECTS, RlyApprovalRules.bucketOf('ValidationRule'), 'Objects');
            System.assertEquals('', RlyApprovalWords.joined(new List<String>()), 'Nothing');
            System.assertEquals('nothing that needs an approver', RlyApprovalWords.onlyText(new RlyApprovalRules.Contents()), 'Empty');
        }
    }

    @IsTest
    static void orgRuleIsSavedAndChecked() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c saved = new RLY_Org__c(Approval_Rule__c = RlyApprovalRules.RULE_SELECTED, Approval_Types__c = 'Flows');
            RLY_Org__c row = new RLY_Org__c(Role__c = 'Stage');
            RlyApprovalRuleOrg.apply(row, '{"Name":"QA"}', saved);
            System.assertEquals('Flows', row.Approval_Types__c, 'Absent keys keep what is saved');
            RlyApprovalRuleOrg.apply(row, '{"Approval_Rule__c":"Selected_Types","Approval_Types__c":"Other;Apex"}', saved);
            System.assertEquals('Apex;Other', row.Approval_Types__c, 'In the page\'s order');
            RlyApprovalRuleOrg.apply(row, '{"Approval_Rule__c":"Selected_Types","Approval_Types__c":["Hotfix"]}', saved);
            System.assertEquals('Hotfix', row.Approval_Types__c, 'A list works too');
            RlyApprovalRuleOrg.apply(row, '{"Approval_Rule__c":null,"Approval_Types__c":null}', saved);
            System.assertEquals('Always', row.Approval_Rule__c, 'Blank is Always');
            System.assertEquals(null, row.Approval_Types__c, 'No types unless Selected_Types');
            List<String> bad = new List<String>{ '{"Approval_Rule__c":"Never"}', '{"Approval_Rule__c":"Selected_Types","Approval_Types__c":null}',
                '{"Approval_Rule__c":"Sometimes"}', '{"Approval_Rule__c":"Selected_Types","Approval_Types__c":"Nope"}' };
            Integer refused = 0;
            for (String b : bad) {
                try {
                    RlyApprovalRuleOrg.apply(new RLY_Org__c(Role__c = 'Hub'), b, null);
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            System.assertEquals(4, refused, 'Hub can\'t be Never; Selected needs a known type; rule must be known');
            RlyOrgController.PipelineOrgs p = RlyOrgController.getOrgs();
            System.assertEquals(3, p.approvalRuleOptions.size(), 'Rules offered');
            System.assertEquals(8, p.approvalTypeOptions.size(), 'Types offered');
        }
    }
}
