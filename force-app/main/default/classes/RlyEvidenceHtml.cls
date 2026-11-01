/**
 * @description Builds a release's evidence document as HTML (RlyEvidenceController turns it into a PDF): the release
 * and its route, components and deletions, the pull request, the code scan with its findings, the validation (tests
 * run, coverage warnings, deploy id), approvals (who, when, where, comment, second approver), manual steps per org
 * (done by, when, notes), flow activation, the deploy (quick or full, deploy id), the branches merged back, the latest
 * rollback (org, who, when, why, what was restored and removed) and the full history. Quality gate failures of the scan
 * and the validation (.relay/gates.json) are listed with the checks. A release with only manual steps shows no Git lines (no branch, pull request, checks or merge commit).
 * Every value is HTML-escaped.
 */
public with sharing class RlyEvidenceHtml {

    private static final Integer MAX_FINDINGS = 200;

    /** @description What the document is built from. */
    public class Source {
        /** @description The release (RlyReleaseStore.release). */
        public RLY_Release__c rel;
        /** @description Its components and deletions. */
        public List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        /** @description Its manual step runs, with Step__r.Title__c, Org__r.Name and Done_By__r.Name. */
        public List<RLY_Manual_Step_Run__c> runs = new List<RLY_Manual_Step_Run__c>();
        /** @description Its history, oldest first. */
        public List<RLY_Release_Event__c> events = new List<RLY_Release_Event__c>();
        /** @description When the document is made. */
        public Datetime madeOn = System.now();
    }

    /**
     * @description The whole document.
     * @param src what it's built from
     * @return the HTML
     */
    public static String build(Source src) {
        RLY_Release__c rel = src.rel;
        List<String> parts = new List<String>{
            '<html><head><style>body{font-family:sans-serif;font-size:10pt}table{border-collapse:collapse;width:100%}'
            + 'td,th{border:1px solid #999;padding:3px;text-align:left;vertical-align:top}h2{font-size:12pt;margin-top:14px}</style></head><body>',
            '<h1>' + RlyEvidenceTables.esc(rel.Name + ' ' + RlyEvidenceText.text(rel.Title__c)) + '</h1>',
            '<p>Evidence made ' + RlyEvidenceTables.esc(src.madeOn.format('yyyy-MM-dd HH:mm z')) + ' by ' + RlyEvidenceTables.esc(UserInfo.getName()) + '</p>',
            summary(rel), components(src.items), checks(rel), approvals(rel), RlyEvidenceTables.manualSteps(src.runs),
            RlyEvidenceTables.flows(rel), deploy(rel), RlyEvidenceTables.rollback(RlyRollbackState.rowOf(rel.Id)),
            RlyEvidenceTables.history(src.events), '</body></html>'
        };
        return String.join(parts, '\n');
    }

    private static String summary(RLY_Release__c rel) {
        Boolean manualOnly = RlyManualOnly.isManualOnly(rel);
        String route = RlyEvidenceTables.orgName(rel.Source_Org__r) + ' → ' + RlyEvidenceTables.orgName(rel.Target_Org__r);
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Route', manualOnly ? route : route + ' (' + RlyEvidenceText.text(rel.Target_Branch__c) + ')' },
            new List<String>{ 'Type', RlyPromotion.typeOf(rel) + (manualOnly ? ' · ' + RlyManualOnly.PILL : '')
                + (RlyHotfix.isHotfix(rel) ? ' · hotfix: ' + RlyEvidenceText.text(rel.Hotfix_Reason__c) : '') },
            new List<String>{ 'Raised by', (rel.CreatedBy == null ? '' : rel.CreatedBy.Name) + ', ' + RlyEvidenceTables.stamp(rel.CreatedDate) },
            new List<String>{ 'Status', RlyEvidenceText.text(rel.Status__c) },
            new List<String>{ 'Pull request', manualOnly ? RlyManualOnly.NOT_NEEDED : RlyEvidenceText.text(rel.PR_URL__c) },
            new List<String>{ 'Description', RlyEvidenceText.text(rel.Description__c) }
        };
        return '<h2>Release</h2>' + RlyEvidenceTables.table(null, rows);
    }

    private static String components(List<RLY_Release_Item__c> items) {
        List<List<String>> rows = new List<List<String>>();
        for (RLY_Release_Item__c i : items) {
            rows.add(new List<String>{ i.Is_Deletion__c == true ? 'Delete' : 'Deploy', i.Metadata_Type__c, i.Component_Name__c });
        }
        return '<h2>Components (' + items.size() + ')</h2>' + RlyEvidenceTables.table(new List<String>{ 'Change', 'Type', 'Name' }, rows);
    }

    private static String checks(RLY_Release__c rel) {
        if (RlyManualOnly.isManualOnly(rel)) {
            return '<h2>Checks</h2>' + RlyEvidenceTables.table(null, new List<List<String>>{
                new List<String>{ 'Code scan and validation', RlyManualOnly.NOT_NEEDED } });
        }
        RlyEvidenceText.Validation v = RlyEvidenceText.validationOf(rel.Validation_Result__c);
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Code scan', RlyEvidenceText.text(rel.Scan_Status__c) + RlyEvidenceText.scanCounts(rel)
                + (rel.Scan_Status__c == 'Bypassed' ? ' · findings accepted: ' + RlyEvidenceText.text(rel.Scan_Bypass_Reason__c) : '') },
            new List<String>{ 'Validation in ' + RlyEvidenceTables.orgName(rel.Target_Org__r), RlyEvidenceText.text(rel.Validation_Status__c) + v.suffix() },
            new List<String>{ 'Test classes', RlyEvidenceText.text(rel.Test_Classes__c) }
        };
        for (String w : v.coverageWarnings) {
            rows.add(new List<String>{ 'Coverage warning', w });
        }
        for (String g : RlyEvidenceTables.gateFailures(rel)) {
            rows.add(new List<String>{ 'Quality gate failed', g });
        }
        return '<h2>Checks</h2>' + RlyEvidenceTables.table(null, rows) + findings(rel);
    }

    private static String findings(RLY_Release__c rel) {
        Object listed = RlyEvidenceText.parse(rel.Scan_Result__c).get('violations');
        List<List<String>> rows = new List<List<String>>();
        for (Object o : listed instanceof List<Object> ? (List<Object>) listed : new List<Object>()) {
            Map<String, Object> m = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
            if (rows.size() < MAX_FINDINGS) {
                rows.add(new List<String>{ RlyEvidenceText.str(m.get('severityLabel')), RlyEvidenceText.str(m.get('rule')),
                    RlyEvidenceText.text(RlyEvidenceText.str(m.get('file'))) + (m.get('line') == null ? '' : ':' + m.get('line')),
                    RlyEvidenceText.str(m.get('message')) });
            }
        }
        return rows.isEmpty() ? '' : '<h2>Code scan findings</h2>' + RlyEvidenceTables.table(new List<String>{ 'Severity', 'Rule', 'Where', 'Message' }, rows);
    }

    private static String approvals(RLY_Release__c rel) {
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Approval', RlyEvidenceText.text(rel.Approval_Status__c) + ' via ' + RlyEvidenceText.text(rel.Approved_Via__c) },
            new List<String>{ 'By', rel.Approved_By__r == null ? '' : rel.Approved_By__r.Name },
            new List<String>{ 'On', RlyEvidenceTables.stamp(rel.Approved_On__c) },
            new List<String>{ 'Comment', RlyEvidenceText.text(rel.Approval_Comment__c) },
            new List<String>{ 'Second approver', (rel.Second_Approved_By__r == null ? '' : rel.Second_Approved_By__r.Name + ', ')
                + RlyEvidenceTables.stamp(rel.Second_Approved_On__c) },
            new List<String>{ 'Rule', RlyEvidenceText.text(RlyReleaseHistory.approvalReason(rel)) }
        };
        return '<h2>Approval</h2>' + RlyEvidenceTables.table(null, rows);
    }

    private static String deploy(RLY_Release__c rel) {
        if (RlyManualOnly.isManualOnly(rel)) {
            return '<h2>Deploy</h2>' + RlyEvidenceTables.table(null, new List<List<String>>{
                new List<String>{ 'Deploy to ' + RlyEvidenceTables.orgName(rel.Target_Org__r), RlyEvidenceText.text(rel.Deploy_Status__c)
                    + ' (manual steps only: deployed when its manual steps are done; no merge commit)' } });
        }
        RlyEvidenceText.Deploy d = RlyEvidenceText.deployOf(rel.Deploy_Result__c);
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Deploy to ' + RlyEvidenceTables.orgName(rel.Target_Org__r), RlyEvidenceText.text(rel.Deploy_Status__c) + d.suffix() },
            new List<String>{ 'Merge commit', RlyEvidenceText.text(rel.Merge_Commit__c) }
        };
        if (String.isNotBlank(rel.Back_Merge_Result__c)) {
            rows.add(new List<String>{ 'Branches merged back', RlyEvidenceText.backMergeCounts(rel.Back_Merge_Result__c) });
        }
        return '<h2>Deploy</h2>' + RlyEvidenceTables.table(null, rows);
    }
}
