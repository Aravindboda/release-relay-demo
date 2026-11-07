/**
 * @description The Pipeline Monitor's Active branches: every branch of an open release (RlyReleaseQuery's open
 * statuses) and every branch with a run in the last 24 hours or still going. Per branch: its newest run (status dot and
 * the org it ran in), its release's pull request (number and state from the release: open, merged or closed) and its
 * last activity. Running branches first, then failed, then by last activity. Built from pipeline runs and releases
 * only (no Git calls).
 */
public with sharing class RlyRunMonitorBranches {

    /** @description Most branches listed. */
    public static final Integer MAX_BRANCHES = 200;

    private static final Integer RECENT_HOURS = 24;
    private static final Map<String, Integer> STATE_ORDER = new Map<String, Integer>{ 'running' => 0, 'failed' => 1, 'ok' => 2, 'idle' => 3 };

    /** @description One branch while it is built, sortable. */
    private class Entry implements Comparable {
        /** @description The row the page gets. */
        public RlyRunMonitorViews.BranchRow row;

        /**
         * @description Running, failed, then newest activity.
         * @param other another entry
         * @return negative, zero or positive
         */
        public Integer compareTo(Object other) {
            RlyRunMonitorViews.BranchRow o = ((Entry) other).row;
            Integer byState = STATE_ORDER.get(row.state) - STATE_ORDER.get(o.state);
            if (byState != 0) {
                return byState;
            }
            Long a = row.lastActivity == null ? 0L : row.lastActivity.getTime();
            Long b = o.lastActivity == null ? 0L : o.lastActivity.getTime();
            return a == b ? row.branch.compareTo(o.branch) : (a > b ? -1 : 1);
        }
    }

    /** @description The branches gathered from the runs and the open releases. */
    private class Gathered {
        /** @description The newest run per branch. */
        public Map<String, RLY_Pipeline_Run__c> latest = new Map<String, RLY_Pipeline_Run__c>();
        /** @description The newest open release per branch. */
        public Map<String, RLY_Release__c> openByBranch = new Map<String, RLY_Release__c>();
        /** @description The releases of the runs. */
        public Map<Id, RLY_Release__c> releases = new Map<Id, RLY_Release__c>();
    }

    /**
     * @description The active branches.
     * @param window the recent runs, newest first (RlyRunMonitorBoard)
     * @return the branches, running and failed first
     */
    public static List<RlyRunMonitorViews.BranchRow> build(List<RLY_Pipeline_Run__c> window) {
        Gathered g = new Gathered();
        g.openByBranch = openReleases();
        g.latest = latestRuns(window, g.openByBranch.keySet());
        Set<Id> releaseIds = new Set<Id>();
        for (RLY_Pipeline_Run__c r : g.latest.values()) {
            if (r.Release__c != null) {
                releaseIds.add(r.Release__c);
            }
        }
        g.releases = RlyRunMonitorReleases.releasesById(releaseIds);
        Set<String> names = new Set<String>(g.latest.keySet());
        names.addAll(g.openByBranch.keySet());
        List<Entry> entries = new List<Entry>();
        for (String name : names) {
            Entry e = new Entry();
            e.row = row(name, g);
            entries.add(e);
        }
        entries.sort();
        List<RlyRunMonitorViews.BranchRow> out = new List<RlyRunMonitorViews.BranchRow>();
        for (Integer i = 0; i < entries.size() && i < MAX_BRANCHES; i++) {
            out.add(entries[i].row);
        }
        return out;
    }

    // The newest open release per source branch.
    private static Map<String, RLY_Release__c> openReleases() {
        Map<String, RLY_Release__c> out = new Map<String, RLY_Release__c>();
        Set<String> open = RlyReleaseQuery.STATE_STATUSES.get(RlyReleaseQuery.STATE_OPEN);
        for (RLY_Release__c rel : RlyRunMonitorReleases.releasesWithBranch(open, MAX_BRANCHES)) {
            if (!out.containsKey(rel.Source_Branch__c)) {
                out.put(rel.Source_Branch__c, rel);
            }
        }
        return out;
    }

    // The newest run per branch: branches with a run in the last 24 hours or still going, and open releases' branches.
    private static Map<String, RLY_Pipeline_Run__c> latestRuns(List<RLY_Pipeline_Run__c> window, Set<String> openBranches) {
        Datetime recentFrom = System.now().addHours(-RECENT_HOURS);
        Map<String, RLY_Pipeline_Run__c> out = new Map<String, RLY_Pipeline_Run__c>();
        for (RLY_Pipeline_Run__c r : window) {
            if (String.isBlank(r.Branch__c) || out.containsKey(r.Branch__c)) {
                continue;
            }
            Boolean recent = RlyRunMonitorStore.ACTIVE.contains(r.Status__c) || r.Started__c >= recentFrom;
            if (recent || openBranches.contains(r.Branch__c)) {
                out.put(r.Branch__c, r);
            }
        }
        return out;
    }

    private static RlyRunMonitorViews.BranchRow row(String name, Gathered g) {
        RLY_Pipeline_Run__c run = g.latest.get(name);
        Boolean runRelease = run != null && run.Release__c != null && g.releases.containsKey(run.Release__c);
        RLY_Release__c rel = runRelease ? g.releases.get(run.Release__c) : g.openByBranch.get(name);
        RlyRunMonitorViews.BranchRow b = new RlyRunMonitorViews.BranchRow();
        b.branch = name;
        b.state = 'idle';
        if (rel != null) {
            RlyRunMonitorBranchRow.withRelease(b, rel);
        }
        if (run != null) {
            RlyRunMonitorBranchRow.withRun(b, run);
        }
        return b;
    }
}
