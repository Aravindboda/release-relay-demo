/**
 * @description Reads a kept migrate.json (build 46) for the Migration tab and the report: the dry run's or the run's
 * findings in words, its progress, and each ref's row. No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationSummary {

    private static final Map<String, Integer> PHASE_PERCENT = new Map<String, Integer>{ 'checking' => 5, 'cloning' => 15,
        'branches' => 30, 'tags' => 85, 'verifying' => 95, 'done' => 100 };

    /**
     * @description A result's findings.
     * @param r the result, or null
     * @return the summary, or null
     */
    public static RlyMigrationView.Summary of(Map<String, Object> r) {
        if (r == null) {
            return null;
        }
        RlyMigrationView.Summary s = new RlyMigrationView.Summary();
        s.status = RlySyncParse.text(r.get('status'));
        s.ready = r.get('ready') == true;
        s.message = RlySyncParse.text(r.get('message'));
        s.phase = RlySyncParse.text(r.get('phase'));
        for (Object p : r.get('problems') instanceof List<Object> ? (List<Object>) r.get('problems') : new List<Object>()) {
            s.problems.add(String.valueOf(p));
        }
        s.counts = counts(r);
        s.access = access(r.get('access'));
        s.targetState = r.get('targetEmpty') == true ? 'Empty' : (r.get('targetRefCount') == null ? null
            : 'Holds ' + toInt(r.get('targetRefCount'), 0) + ' branch(es) and tag(s)');
        for (Object o : r.get('namedBranches') instanceof List<Object> ? (List<Object>) r.get('namedBranches') : new List<Object>()) {
            Map<String, Object> m = (Map<String, Object>) o;
            RlyMigrationView.Named n = new RlyMigrationView.Named();
            n.name = RlySyncParse.text(m.get('name'));
            n.inSource = m.get('inSource') == true;
            n.inTarget = m.get('inTarget') == true;
            s.named.add(n);
        }
        s.percent = percent(r);
        return s;
    }

    /**
     * @description Branches · tags · commits · size, in words.
     * @param r the result
     * @return the words
     */
    public static String counts(Map<String, Object> r) {
        List<String> parts = new List<String>{ found(r.get('branches')) + ' branch(es)', found(r.get('tags')) + ' tag(s)',
            toInt(r.get('commits'), 0) + ' commit(s)' };
        if (r.get('mainCommits') != null && String.isNotBlank(RlySyncParse.text(r.get('defaultBranch')))) {
            parts.add(toInt(r.get('mainCommits'), 0) + ' on ' + RlySyncParse.text(r.get('defaultBranch')));
        }
        Integer kb = toInt(r.get('sizeKb'), 0);
        if (kb > 0) {
            parts.add(kb >= 1024 ? (kb / 1024) + ' MB' : kb + ' KB');
        }
        return String.join(parts, ' · ');
    }

    /**
     * @description One ref of a result.
     * @param m {ref, kind, name, source, target, match}
     * @return the row
     */
    public static RlyMigrationView.RefRow refRow(Map<String, Object> m) {
        RlyMigrationView.RefRow row = new RlyMigrationView.RefRow();
        row.kind = RlySyncParse.text(m.get('kind'));
        row.name = RlySyncParse.text(m.get('name'));
        row.source = RlySyncParse.text(m.get('source'));
        row.target = RlySyncParse.text(m.get('target'));
        row.match = m.get('match') == true;
        return row;
    }

    /**
     * @description A number from JSON.
     * @param o the value
     * @param fallback when it isn't a number
     * @return the number
     */
    public static Integer toInt(Object o, Integer fallback) {
        if (o instanceof Integer) {
            return (Integer) o;
        }
        if (o instanceof Decimal) {
            return ((Decimal) o).intValue();
        }
        if (o instanceof Long) {
            return ((Long) o).intValue();
        }
        return fallback;
    }

    // Progress: the phase, and within the branches how many are pushed.
    private static Integer percent(Map<String, Object> r) {
        String phase = RlySyncParse.text(r.get('phase'));
        Integer p = PHASE_PERCENT.containsKey(phase) ? PHASE_PERCENT.get(phase) : 0;
        if (phase == 'branches' && r.get('branches') instanceof Map<String, Object>) {
            Map<String, Object> b = (Map<String, Object>) r.get('branches');
            Integer foundCount = toInt(b.get('found'), 0);
            Integer doneCount = toInt(b.get('pushed'), 0) + toInt(b.get('failed'), 0);
            p = foundCount == 0 ? p : 30 + (55 * doneCount) / foundCount;
        }
        return p;
    }

    private static Integer found(Object o) {
        return o instanceof Map<String, Object> ? toInt(((Map<String, Object>) o).get('found'), 0) : 0;
    }

    private static String access(Object o) {
        if (!(o instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> a = (Map<String, Object>) o;
        String out = 'read ' + mark(a.get('read'));
        return a.get('push') == null ? out : out + ' · push ' + mark(a.get('push'));
    }

    private static String mark(Object ok) {
        return ok == true ? '✓' : '✗';
    }
}
