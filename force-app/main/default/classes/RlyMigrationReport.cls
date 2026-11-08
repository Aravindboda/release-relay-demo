/**
 * @description The Migration report (build 46): one page with the current and new connection, the method, the dry run,
 * what moved (each ref with both commits), what didn't move, both checklists, each org's check and accepted differences,
 * the switch, the releases it cancelled (build 54) and who did each step and when. HTML for Blob.toPdf, like the evidence PDF. No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationReport {

    private static final String STYLE = '<style>body{font-family:Arial,Helvetica,sans-serif;font-size:10px;color:#181818}'
        + 'h1{font-size:16px;margin:0 0 4px}h2{font-size:12px;margin:14px 0 4px;border-bottom:1px solid #ccc}'
        + 'table{width:100%;border-collapse:collapse}td,th{border:1px solid #ddd;padding:3px 4px;text-align:left;vertical-align:top}'
        + 'th{background:#f3f3f3}.m{font-family:Courier,monospace}.w{color:#5c5c5c}</style>';

    /**
     * @description The report's HTML.
     * @param m the migration
     * @param v its view
     * @return the HTML
     */
    public static String html(RLY_Migration__c m, RlyMigrationView.View v) {
        List<String> h = new List<String>{ '<html><head>' + STYLE + '</head><body>' };
        String fromLabel = v.current == null ? '' : v.current.providerLabel + ' ' + v.current.repository;
        String toLabel = v.target == null ? '' : v.target.providerLabel + ' ' + v.target.repository;
        h.add('<h1>Migration report ' + RlyEvidenceTables.esc(m.Migration_Id__c) + '</h1>');
        h.add('<p>' + RlyEvidenceTables.esc(fromLabel) + ' → ' + RlyEvidenceTables.esc(toLabel) + '<br/>Method: ' + RlyEvidenceTables.esc(methodLabel(v)) + '<br/>Started '
            + RlyEvidenceTables.esc(String.valueOf(m.CreatedDate)) + ' by ' + RlyEvidenceTables.esc(m.CreatedBy?.Name) + ' · switched ' + RlyEvidenceTables.esc(String.valueOf(m.Switched_On__c))
            + ' · finished ' + RlyEvidenceTables.esc(String.valueOf(System.now())) + ' · status ' + RlyEvidenceTables.esc(m.Status__c) + '</p>');
        h.add(summarySection('Dry run', v.run.dry));
        h.add(summarySection(m.Method__c == RlyMigrationMethods.IMPORTER ? 'Verify' : 'Run', v.run.result));
        h.add(movedSection(v.moved));
        h.add(notMovedSection(v.moved));
        h.add(itemsSection('Do in the new setup', v.setup.newItems));
        h.add(itemsSection('Do in the old setup', v.setup.oldItems));
        h.add(orgsSection(v));
        h.add(gateSection(v.gate));
        h.add(cancelledSection(v));
        h.add(eventsSection(v.log.events));
        h.add('</body></html>');
        return String.join(h, '\n');
    }

    private static String methodLabel(RlyMigrationView.View v) {
        for (RlyMigrationMethods.Method x : v.choose.methods) {
            if (x.key == v.choose.method) {
                return x.label;
            }
        }
        return v.choose.method;
    }

    private static String summarySection(String title, RlyMigrationView.Summary s) {
        if (s == null) {
            return '<h2>' + title + '</h2><p class="w">Not run.</p>';
        }
        return '<h2>' + title + '</h2><table>' + row2('Status', s.status + (s.ready ? ' · ready' : '')) + row2('Counts', s.counts)
            + row2('New repository', s.targetState) + row2('Access', s.access) + row2('Problems', String.join(s.problems, ' '))
            + row2('Message', s.message) + '</table>';
    }

    private static String movedSection(RlyMigrationView.Moved mv) {
        List<String> h = new List<String>{ '<h2>What moved</h2><p>' + RlyEvidenceTables.esc(mv.counts) + ' · ' + RlyEvidenceTables.esc(mv.matched)
            + (mv.fresh ? ' (fresh start: each branch\'s files, one commit, no history)' : '') + '</p>',
            '<table><tr><th>Kind</th><th>Name</th><th>Role</th><th>Current</th><th>New</th><th>Match</th></tr>' };
        for (RlyMigrationView.RefRow r : mv.rows) {
            h.add('<tr><td>' + RlyEvidenceTables.esc(r.kind) + '</td><td class="m">' + RlyEvidenceTables.esc(r.name) + '</td><td>' + RlyEvidenceTables.esc(r.role) + '</td><td class="m">'
                + RlyEvidenceTables.esc(r.source) + '</td><td class="m">' + RlyEvidenceTables.esc(r.target) + '</td><td>' + (r.match ? '✓' : '✗') + '</td></tr>');
        }
        h.add('</table>' + (mv.more > 0 ? '<p class="w">' + mv.more + ' more not listed.</p>' : ''));
        return String.join(h, '');
    }

    private static String notMovedSection(RlyMigrationView.Moved mv) {
        List<String> h = new List<String>{ '<h2>What didn\'t move</h2><table>' };
        for (RlyMigrationRepo.OpenRequest r : mv.requests) {
            h.add(row2('Open ' + r.label, r.title + ' (' + r.branches + ') ' + r.url));
        }
        for (String s : mv.stays) {
            h.add('<tr><td colspan="2">' + RlyEvidenceTables.esc(s) + '</td></tr>');
        }
        h.add('</table>');
        return String.join(h, '');
    }

    private static String itemsSection(String title, List<RlyMigrationChecklist.Item> items) {
        List<String> h = new List<String>{ '<h2>' + title + '</h2><table><tr><th>Item</th><th>Where</th><th>Done</th><th>By</th><th>When</th></tr>' };
        for (RlyMigrationChecklist.Item i : items) {
            h.add('<tr><td>' + RlyEvidenceTables.esc(i.label) + '</td><td>' + RlyEvidenceTables.esc(i.place) + '</td><td>' + (i.done ? 'Done' : 'Not done') + '</td><td>'
                + RlyEvidenceTables.esc(i.who) + '</td><td>' + RlyEvidenceTables.esc(String.valueOf(i.stamp)) + '</td></tr>');
        }
        h.add('</table>');
        return String.join(h, '');
    }

    private static String orgsSection(RlyMigrationView.View v) {
        List<String> h = new List<String>{ '<h2>Orgs against their new branch</h2><table><tr><th>Org</th><th>Branch</th><th>How</th>'
            + '<th>Result</th><th>Details</th></tr>' };
        for (RlyMigrationView.OrgRow o : v.orgs) {
            h.add('<tr><td>' + RlyEvidenceTables.esc(o.name) + '</td><td class="m">' + RlyEvidenceTables.esc(o.branch) + '</td><td>' + RlyEvidenceTables.esc(o.how) + '</td><td>' + RlyEvidenceTables.esc(o.status)
                + '</td><td>' + RlyEvidenceTables.esc(o.detail) + '</td></tr>');
        }
        h.add('</table>' + (String.isBlank(v.gate.acceptReason) ? '' : '<p>Differences accepted: ' + RlyEvidenceTables.esc(v.gate.acceptReason) + '</p>'));
        return String.join(h, '');
    }

    private static String gateSection(RlyMigrationView.Gate g) {
        List<String> h = new List<String>{ '<h2>The switch</h2><p>Switched on: ' + RlyEvidenceTables.esc(String.valueOf(g.switchedOn)) + '</p><table>' };
        for (RlyMigrationView.Condition c : g.conditions) {
            h.add(row2((c.ok ? '✓ ' : '✗ ') + c.label, c.detail));
        }
        h.add('</table>');
        return String.join(h, '');
    }

    // Build 54: the releases Switch now cancelled, with what happened to each pull request.
    private static String cancelledSection(RlyMigrationView.View v) {
        if (v.cancelled == null || v.cancelled.isEmpty()) {
            return '';
        }
        List<String> h = new List<String>{ '<h2>Releases cancelled by the switch</h2><table><tr><th>Release</th><th>Status before</th>'
            + '<th>Pull request</th><th>Note</th></tr>' };
        for (RlyMigrationView.CancelledRelease r : v.cancelled) {
            h.add('<tr><td>' + RlyEvidenceTables.esc(r.name + ' ' + RlySlackCard.text(r.title)) + '</td><td>' + RlyEvidenceTables.esc(r.before)
                + '</td><td>' + RlyEvidenceTables.esc(RlyMigrationCancelText.pullRequestText(r)) + '</td><td>'
                + RlyEvidenceTables.esc(RlyMigrationCancelText.noteText(r)) + '</td></tr>');
        }
        h.add('</table>');
        return String.join(h, '');
    }

    private static String eventsSection(List<RlyMigrationView.Event> events) {
        List<String> h = new List<String>{ '<h2>Who did each step and when</h2><table><tr><th>When</th><th>Who</th><th>Step</th><th>What</th></tr>' };
        for (RlyMigrationView.Event e : events) {
            h.add('<tr><td>' + RlyEvidenceTables.esc(String.valueOf(e.stamp)) + '</td><td>' + RlyEvidenceTables.esc(e.who) + '</td><td>' + RlyEvidenceTables.esc(e.step) + '</td><td>'
                + RlyEvidenceTables.esc(e.what) + '</td></tr>');
        }
        h.add('</table>');
        return String.join(h, '');
    }

    private static String row2(String label, String value) {
        return String.isBlank(value) ? '' : '<tr><th style="width:24%">' + RlyEvidenceTables.esc(label) + '</th><td>' + RlyEvidenceTables.esc(value) + '</td></tr>';
    }
}
