/**
 * @description The evidence document's tables (RlyEvidenceHtml): manual steps per org, flows, the latest rollback,
 * quality gate failures, the history, and the table, escaping and date helpers.
 */
public with sharing class RlyEvidenceTables {

    private static final String TD = '</td><td>';

    /**
     * @description The manual steps section (empty without runs).
     * @param runs the runs
     * @return the HTML
     */
    public static String manualSteps(List<RLY_Manual_Step_Run__c> runs) {
        if (runs.isEmpty()) {
            return '';
        }
        List<List<String>> rows = new List<List<String>>();
        for (RLY_Manual_Step_Run__c r : runs) {
            rows.add(new List<String>{ r.Org__r == null ? '' : r.Org__r.Name, r.Step__r == null ? '' : r.Step__r.Title__c,
                r.Step__r == null ? '' : r.Step__r.Timing__c, r.Status__c,
                (r.Done_By__r == null ? '' : r.Done_By__r.Name + ', ') + stamp(r.Done_On__c), r.Note__c });
        }
        return '<h2>Manual steps</h2>' + table(new List<String>{ 'Org', 'Step', 'Timing', 'Status', 'Done by', 'Note' }, rows);
    }

    /**
     * @description The flows section: each flow's choice and its activation results (empty without flows).
     * @param rel the release
     * @return the HTML
     */
    public static String flows(RLY_Release__c rel) {
        List<List<String>> rows = new List<List<String>>();
        for (RlyFlowChoices.FlowChoice c : RlyFlowChoices.fromRelease(rel)) {
            rows.add(new List<String>{ c.name, 'After deploy: ' + c.choice });
        }
        for (RlyFlowResults.FlowResult r : RlyFlowResults.forRelease(rel)) {
            rows.add(new List<String>{ r.flow, RlyFlowResults.line(r) });
        }
        return rows.isEmpty() ? '' : '<h2>Flows</h2>' + table(new List<String>{ 'Flow', 'Result' }, rows);
    }

    /**
     * @description The rollback section (empty when the release was never rolled back).
     * @param row the rollback fields (RlyRollbackState.rowOf)
     * @return the HTML
     */
    public static String rollbackTable(RLY_Release__c row) {
        String label = RlyRollbackState.label(row);
        if (label == null) {
            return '';
        }
        Map<String, Object> r = RlyRollbackState.result(row);
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Status', label },
            new List<String>{ 'By', RlyRollbackState.byName(row) + ', ' + stamp(row.Rollback_On__c) },
            new List<String>{ 'Why', row.Rollback_Reason__c },
            new List<String>{ 'Snapshot', RlyEvidenceText.str(r.get('snapshot')) },
            new List<String>{ 'Result', RlyRollbackState.counts(row) + ' · ' + RlyEvidenceText.text(RlyEvidenceText.str(r.get('message'))) },
            new List<String>{ 'Deploy id', RlyEvidenceText.str(r.get('deployId')) },
            new List<String>{ 'Tests', RlyEvidenceText.text(RlyEvidenceText.str(r.get('testLevel'))) },
            new List<String>{ 'Git', 'Not changed by a rollback: a follow-up release fixes the branch.' }
        };
        return '<h2>Rollback</h2>' + table(null, rows);
    }

    /**
     * @description The quality gate failures (.relay/gates.json) the code scan and the validation recorded.
     * @param rel the release, with Scan_Result__c and Validation_Result__c
     * @return the failures, scan first
     */
    public static List<String> gateFailures(RLY_Release__c rel) {
        List<String> out = new List<String>();
        for (String body : new List<String>{ rel.Scan_Result__c, rel.Validation_Result__c }) {
            Object gates = RlyEvidenceText.parse(body).get('gates');
            Object failures = gates instanceof Map<String, Object> ? ((Map<String, Object>) gates).get('failures') : null;
            for (Object f : failures instanceof List<Object> ? (List<Object>) failures : new List<Object>()) {
                out.add(String.valueOf(f));
            }
        }
        return out;
    }

    /**
     * @description The history section.
     * @param events the events, oldest first
     * @return the HTML
     */
    public static String history(List<RLY_Release_Event__c> events) {
        List<List<String>> rows = new List<List<String>>();
        for (RLY_Release_Event__c e : events) {
            rows.add(new List<String>{ stamp(e.Occurred_On__c), e.Event_Type__c, e.Org__r == null ? '' : e.Org__r.Name,
                (e.Actor__r == null ? '' : e.Actor__r.Name + ' · ') + RlyEvidenceText.text(e.Via__c), e.Detail__c, e.Reference__c });
        }
        return '<h2>History</h2>' + table(new List<String>{ 'When', 'Event', 'Org', 'Who', 'Detail', 'Reference' }, rows);
    }

    /**
     * @description A table: an optional header row, then the rows; every cell escaped.
     * @param header the header cells, or null
     * @param rows the rows
     * @return the HTML
     */
    public static String table(List<String> header, List<List<String>> rows) {
        List<String> out = new List<String>{ '<table>' };
        if (header != null) {
            out.add('<tr><th>' + String.join(escAll(header), '</th><th>') + '</th></tr>');
        }
        for (List<String> r : rows) {
            out.add('<tr><td>' + String.join(escAll(r), TD) + '</td></tr>');
        }
        out.add('</table>');
        return String.join(out, '');
    }

    private static List<String> escAll(List<String> cells) {
        List<String> out = new List<String>();
        for (String c : cells) {
            out.add(esc(c));
        }
        return out;
    }

    /**
     * @description HTML-escapes a value (null is empty).
     * @param value the value
     * @return the escaped text
     */
    public static String esc(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    /**
     * @description A date and time as yyyy-MM-dd HH:mm (null is empty).
     * @param value the value
     * @return the text
     */
    public static String stamp(Datetime value) {
        return value == null ? '' : value.format('yyyy-MM-dd HH:mm');
    }

    /**
     * @description An org's name (null is empty).
     * @param org the org
     * @return the name
     */
    public static String orgName(RLY_Org__c org) {
        return org == null ? '' : org.Name;
    }
}
