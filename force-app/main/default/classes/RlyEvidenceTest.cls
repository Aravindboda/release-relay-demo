/**
 * @description Tests for the release history and evidence: events at transitions (RlyReleaseLog, RlyReleaseTransitions,
 * RlyReleaseOutcomes, RlyEvidenceText), the release page's history (RlyReleaseHistory), the evidence PDF saved to the
 * release's Files (RlyEvidenceController.saveEvidence, RlyEvidenceHtml, RlyEvidenceTables) and the Releases CSV
 * (exportCsv). Every test runs as an active System Administrator via System.runAs.
 */
@IsTest
private class RlyEvidenceTest {

    private static final String VALIDATION_JSON = '{"status":"Passed","testsRun":12,"deployId":"0Af000000000001",'
        + '"coverageWarnings":[{"name":"AccountService","message":"Test coverage of 60%"}],"mergedWith":"abc"}';
    private static final String DEPLOY_JSON = '{"status":"Deployed","quick":true,"testsRun":0,"deployId":"0Af000000000002"}';

    // A deployed release with everything the document shows: scan findings, validation, approvals, steps, flows, history.
    private static RLY_Release__c fullRelease() {
        RLY_Release__c rel = RlyReleaseTestData.release('Deployed', 'merge');
        Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
        update new RLY_Release__c(Id = rel.Id, Scan_Status__c = 'Passed', Scan_Violations__c = 1, Scan_Blocking__c = 0,
            Scan_Result__c = '{"violations":[{"severityLabel":"Low","rule":"ApexDoc","file":"classes/A.cls","line":3,"message":"<b>Doc</b>"}]}',
            Validation_Status__c = 'Passed', Validation_Result__c = VALIDATION_JSON, Deploy_Status__c = 'Deployed', Deploy_Result__c = DEPLOY_JSON,
            Approval_Status__c = 'Approved', Approved_By__c = UserInfo.getUserId(), Approved_On__c = System.now(), Approved_Via__c = 'Salesforce',
            Approval_Comment__c = 'Looks good', PR_URL__c = 'https://github.com/acme/release/pull/42', Merge_Commit__c = RlyReleaseTestData.sha('b'),
            Back_Merge_Result__c = '[{"branch":"dev1","status":"Synced"},{"branch":"dev2","status":"Conflict"}]',
            Flow_Actions__c = '[{"name":"Case_Escalation","choice":"Activate"}]',
            Flow_Results__c = '[{"org":"SIT","flow":"Case_Escalation","version":8,"status":"Activated"}]');
        RLY_Manual_Step__c step = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Assign access', Category__c = 'Permissions',
            Timing__c = RlyManualSteps.TIMING_BEFORE);
        insert step;
        insert new RLY_Manual_Step_Run__c(Step__c = step.Id, Release__c = rel.Id, Org__c = targetId, Status__c = RlyManualSteps.STATUS_DONE,
            Done_By__c = UserInfo.getUserId(), Done_On__c = System.now(), Note__c = 'Done in Setup');
        RlyReleaseLog.addFor(rel.Id, 'Comment', 'Raised for the audit').inOrg(targetId)
            .byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(RlyTestData.fakeId('0Af', 2));
        RlyReleaseLog.flush();
        return rel;
    }

    @IsTest
    static void evidenceIsSavedToTheReleaseFiles() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = fullRelease();
            Test.startTest();
            RlyEvidenceController.EvidenceFile f = RlyEvidenceController.saveEvidence(rel.Id);
            Test.stopTest();
            System.assert(f.title.startsWith(rel.Name + ' evidence '), 'Title: ' + f.title);
            System.assertEquals('/sfc/servlet.shepherd/document/download/' + f.contentDocumentId, f.downloadUrl, 'Download address');
            System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :rel.Id AND ContentDocumentId = :f.contentDocumentId],
                'Linked to the release');
        }
    }

    @IsTest
    static void documentHasEverySectionEscaped() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = fullRelease();
            RlyEvidenceHtml.Source src = new RlyEvidenceHtml.Source();
            src.rel = RlyReleaseStore.release(rel.Id);
            src.items = RlyReleaseStore.items(rel.Id);
            src.runs = [SELECT Id, Org__r.Name, Step__r.Title__c, Step__r.Timing__c, Status__c, Done_By__r.Name, Done_On__c, Note__c
                        FROM RLY_Manual_Step_Run__c WHERE Release__c = :rel.Id];
            src.events = RlyReleaseLog.eventsOf(new Set<Id>{ rel.Id });
            String html = RlyEvidenceHtml.build(src);
            for (String part : new List<String>{ 'Components (2)', 'Code scan findings', '&lt;b&gt;Doc&lt;/b&gt;', 'Coverage warning',
                    '12 tests run', 'Looks good', 'Assign access', 'Done in Setup', 'Case_Escalation', 'quick deploy 0Af000000000002',
                    '1 synced, 1 conflict', 'Raised for the audit', 'Always needs approval in SIT' }) {
                System.assert(html.contains(part), 'Has ' + part);
            }
            System.assert(!html.contains('<b>Doc</b>'), 'Escaped');
            System.assertEquals(html.countMatches('<table>'), html.countMatches('<thead>'), 'Every table has a thead');
            System.assert(html.contains('<h2>History, oldest first</h2>'), 'History heading says its order');
            System.assert(html.contains('<div class="rr-sec"><h2>History'), 'History flows over pages');
            System.assert(html.contains('<div class="rr-sec rr-keep"><h2>Approval</h2>'), 'Short sections stay on one page');
            for (String rule : new List<String>{ 'tr,td,th{page-break-inside:avoid}', 'h1,h2,h3{page-break-after:avoid}',
                    'thead{display:table-header-group}', '-fs-table-paginate:paginate', '.rr-keep{page-break-inside:avoid}' }) {
                System.assert(html.contains(rule), 'Print CSS ' + rule);
            }
            List<List<String>> many = new List<List<String>>();
            for (Integer i = 0; i < 16; i++) {
                many.add(new List<String>{ 'Row ' + i, 'x' });
            }
            System.assert(RlyEvidenceTables.section('Long', null, many).startsWith('<div class="rr-sec"><h2>Long</h2>'), 'Long section may break');
            System.assert(RlyEvidenceTables.table(null, many).contains('<thead><tr><th>Item</th><th>Value</th></tr></thead>'), 'Default header');
            System.assertEquals('', RlyEvidenceTables.manualSteps(new List<RLY_Manual_Step_Run__c>()), 'No steps, no section');
            System.assertEquals('', RlyEvidenceTables.esc(null), 'Null is empty');
        }
    }

    @IsTest
    static void csvFollowsTheReleasesFilter() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = fullRelease();
            Test.startTest();
            String csv = RlyEvidenceController.exportCsv('{"state":"deployed","searchText":""}');
            Test.stopTest();
            List<String> lines = csv.split('\r\n');
            System.assertEquals(2, lines.size(), 'Header and the deployed release: ' + csv);
            System.assert(lines[0].startsWith('"REL","Title","Route"'), 'Header');
            System.assert(lines[1].contains('"' + rel.Name + '"') && lines[1].contains('0Af000000000001 0Af000000000002'), 'Row: ' + lines[1]);
            System.assertEquals('"\'=SUM(A1)","say ""hi""",""', RlyEvidenceController.csvLine(new List<String>{ '=SUM(A1)', 'say "hi"', null }),
                'Quoted, formulas defused');
            Boolean refused = false;
            try {
                RlyEvidenceController.exportCsv('{"state":"sometimes"}');
            } catch (AuraHandledException e) {
                refused = true;
            }
            System.assert(refused, 'Unknown filter');
        }
    }

    @IsTest
    static void transitionsBecomeEvents() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'hub');
            RLY_Org__c target = new RLY_Org__c(Name = 'SIT');
            Id me = UserInfo.getUserId();
            RLY_Release__c old = new RLY_Release__c(Id = rel.Id, Status__c = 'Validating', Scan_Status__c = 'Pending', Validation_Status__c = 'Pending',
                Approval_Status__c = 'Pending');
            RLY_Release__c now = new RLY_Release__c(Id = rel.Id, Status__c = 'Deployed', Scan_Status__c = 'Bypassed', Scan_Bypass_Reason__c = 'Known',
                Validation_Status__c = 'Passed', Validation_Result__c = VALIDATION_JSON, Approval_Status__c = 'Approved', Approved_By__c = me,
                Approved_Via__c = 'GitHub', Second_Approved_By__c = me, PR_URL__c = 'https://x/pull/1', PR_Number__c = 1, Target_Branch__c = 'sit',
                Deploy_Result__c = DEPLOY_JSON, Back_Merge_Result__c = '[{"branch":"dev1","status":"Synced"}]', Target_Org__r = target);
            RLY_Release__c rejected = new RLY_Release__c(Id = rel.Id, Status__c = 'Rejected', Approval_Status__c = 'Rejected', Approved_Via__c = 'Slack',
                Approval_Comment__c = 'No', Target_Org__r = target);
            RLY_Release__c failed = new RLY_Release__c(Id = rel.Id, Status__c = 'Deploy failed', Error_Message__c = 'Boom', Target_Org__r = target);
            RLY_Release__c closed = new RLY_Release__c(Id = rel.Id, Status__c = 'Closed', Target_Org__r = target);
            RLY_Release__c stopped = new RLY_Release__c(Id = rel.Id, Status__c = 'Failed', Error_Message__c = 'Run failed', Target_Org__r = target);
            for (RLY_Release__c r : new List<RLY_Release__c>{ now, rejected, failed, closed, stopped }) {
                RlyReleaseTransitions.record(new Map<Id, RLY_Release__c>{ rel.Id => old }, new List<RLY_Release__c>{ r });
            }
            RlyReleaseTransitions.record(new Map<Id, RLY_Release__c>(), new List<RLY_Release__c>{ now });
            RlyReleaseLog.flush();
            Map<String, Integer> kinds = new Map<String, Integer>();
            for (RLY_Release_Event__c e : RlyReleaseLog.eventsOf(new Set<Id>{ rel.Id })) {
                kinds.put(e.Event_Type__c, (kinds.containsKey(e.Event_Type__c) ? kinds.get(e.Event_Type__c) : 0) + 1);
            }
            for (String k : new List<String>{ 'Pull_Request', 'Scan', 'Validation', 'Approved', 'Deployed', 'Merged_Back', 'Rejected',
                    'Deploy_Failed', 'Comment' }) {
                System.assert(kinds.containsKey(k), 'Event ' + k + ' in ' + kinds);
            }
            System.assertEquals(2, kinds.get('Approved'), 'First and second approval');
            System.assertEquals('Git', RlyReleaseTransitions.viaOf('GitHub'), 'A provider is Git');
            System.assertEquals('Salesforce', RlyReleaseTransitions.viaOf(null), 'Default');
            System.assertEquals(0, RlyReleaseLog.pendingCount(), 'All saved');
        }
    }

    @IsTest
    static void resultWordsAndManualStepEvents() {
        System.runAs(RlyTestData.admin()) {
            RlyEvidenceText.Validation v = RlyEvidenceText.validationOf(VALIDATION_JSON);
            System.assertEquals(': 12 tests run, 1 coverage warning, deploy 0Af000000000001', v.suffix(), 'Validation words');
            System.assertEquals(': conflicts with the target branch', RlyEvidenceText.validationOf(RlyReleaseTestData.conflictResult()).suffix(), 'Conflict');
            System.assertEquals('', RlyEvidenceText.validationOf('junk').suffix(), 'Unreadable');
            System.assertEquals(' (full deploy 0Af9, 5 tests run)', RlyEvidenceText.deployOf('{"deployId":"0Af9","testsRun":"5"}').suffix(), 'Full');
            System.assertEquals('', RlyEvidenceText.deployOf('{"testsRun":"x"}').suffix(), 'No deploy id');
            System.assertEquals('nothing to sync', RlyEvidenceText.backMergeCounts(null), 'Nothing');
            System.assertEquals('', RlyEvidenceText.scanCounts(new RLY_Release__c()), 'No scan');
            System.assertEquals(': 1 finding, 0 blocking', RlyEvidenceText.scanCounts(new RLY_Release__c(Scan_Violations__c = 1)), 'One');
            RLY_Release__c rel = RlyReleaseTestData.release('Deployed', 'merge');
            Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
            RLY_Manual_Step__c step = new RLY_Manual_Step__c(Release__c = rel.Id, Title__c = 'Load data', Category__c = 'Data',
                Timing__c = RlyManualSteps.TIMING_AFTER);
            insert step;
            RLY_Manual_Step_Run__c run = new RLY_Manual_Step_Run__c(Step__c = step.Id, Release__c = rel.Id, Org__c = targetId,
                Status__c = RlyManualSteps.STATUS_NOT_NEEDED, Note__c = 'Already there');
            insert run;
            RlyReleaseLog.manualStep([SELECT Id, Step__r.Title__c, Release__c, Org__c, Org__r.Name, Status__c, Note__c
                                      FROM RLY_Manual_Step_Run__c WHERE Id = :run.Id]);
            RlyReleaseLog.flush();
            List<RlyReleaseHistory.EventRow> rows = RlyReleaseHistory.events(rel.Id);
            System.assertEquals(1, rows.size(), 'One event');
            System.assertEquals('Load data in SIT: not needed (Already there)', rows[0].detail, 'Words');
            System.assertEquals('SIT', rows[0].orgName, 'Org');
            RlyReleaseLog.Entry later = RlyReleaseLog.addFor(rel.Id, 'Comment', 'Later note');
            later.row.Occurred_On__c = System.now().addMinutes(5);
            RlyReleaseLog.flush();
            rows = RlyReleaseHistory.events(rel.Id);
            System.assertEquals('Later note', rows[0].detail, 'Newest first on the page');
        }
    }
}
