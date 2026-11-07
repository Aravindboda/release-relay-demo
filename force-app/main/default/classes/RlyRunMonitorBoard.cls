/**
 * @description The Pipeline Monitor board (RlyRunMonitorController.readBoard): the repository picker, the four tiles,
 * the first page of runs and older pages; the lanes come from RlyRunMonitorLanes and the active branches from
 * RlyRunMonitorBranches, both from the runs of the last 30 days and the runs still going (RlyRunMonitorQueries). Runs
 * are filtered by repository only when the hub has more than one Git connection.
 */
public with sharing class RlyRunMonitorBoard {

    /** @description Runs shown on the first page and on each Load older runs. */
    public static final Integer PAGE_SIZE = 50;
    /** @description The lanes and branches look back this many days. */
    public static final Integer WINDOW_DAYS = 30;

    private static final Integer WINDOW_ROWS = 1000;

    /**
     * @description The board.
     * @param repository the repository picked, or blank for the first connection's
     * @return the board
     */
    public static RlyRunMonitorViews.Board read(String repository) {
        RlyRunMonitorViews.Board b = new RlyRunMonitorViews.Board();
        b.readAt = System.now();
        List<RLY_Git_Connection__c> conns = RlyRunMonitorStore.connections();
        for (RLY_Git_Connection__c c : conns) {
            RlyRunMonitorViews.Repo r = new RlyRunMonitorViews.Repo();
            r.id = c.Id;
            r.repository = c.Repository__c;
            r.provider = c.Provider__c;
            b.repos.add(r);
        }
        b.repository = pick(conns, repository);
        String filter = filterFor(conns, b.repository);
        Datetime today = startOfToday();
        List<RLY_Pipeline_Run__c> active = RlyRunMonitorQueries.active(filter);
        List<RLY_Pipeline_Run__c> recent = RlyRunMonitorQueries.since(filter, System.now().addDays(-WINDOW_DAYS), WINDOW_ROWS);
        List<RLY_Pipeline_Run__c> window = merged(active, recent);
        b.anyActive = !active.isEmpty();
        b.lanes = RlyRunMonitorLanes.build(window, today);
        b.branches = RlyRunMonitorBranches.build(window);
        b.tiles.running = active.size();
        b.tiles.branches = b.branches.size();
        b.tiles.succeededToday = RlyRunMonitorQueries.countFinished(filter, RlyRunMonitorInput.SUCCEEDED, today);
        b.tiles.failedToday = RlyRunMonitorQueries.countFinished(filter, RlyRunMonitorInput.FAILED, today);
        List<RLY_Pipeline_Run__c> done = RlyRunMonitorQueries.finished(filter, null, PAGE_SIZE + 1);
        b.hasMore = done.size() > PAGE_SIZE;
        while (done.size() > PAGE_SIZE) {
            done.remove(done.size() - 1);
        }
        b.runs = RlyRunMonitorRows.rows(active);
        b.runs.addAll(RlyRunMonitorRows.rows(done));
        return b;
    }

    /**
     * @description A page of finished runs older than a cursor (Load older runs).
     * @param repository the repository picked, or blank
     * @param startedBefore the start of the oldest run shown
     * @param idBefore that run's record
     * @return the page
     */
    public static RlyRunMonitorViews.OlderPage older(String repository, Datetime startedBefore, Id idBefore) {
        List<RLY_Git_Connection__c> conns = RlyRunMonitorStore.connections();
        String filter = filterFor(conns, pick(conns, repository));
        RlyRunMonitorQueries.Cursor after = new RlyRunMonitorQueries.Cursor();
        after.started = startedBefore;
        after.recordId = idBefore;
        List<RLY_Pipeline_Run__c> rows = RlyRunMonitorQueries.finished(filter, after, PAGE_SIZE + 1);
        RlyRunMonitorViews.OlderPage p = new RlyRunMonitorViews.OlderPage();
        p.hasMore = rows.size() > PAGE_SIZE;
        while (rows.size() > PAGE_SIZE) {
            rows.remove(rows.size() - 1);
        }
        p.runs = RlyRunMonitorRows.rows(rows);
        return p;
    }

    /**
     * @description Midnight at the start of the viewer's today.
     * @return the moment
     */
    public static Datetime startOfToday() {
        return Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
    }

    // The repository asked for when it is one of the connections, else the first connection's.
    private static String pick(List<RLY_Git_Connection__c> conns, String repository) {
        for (RLY_Git_Connection__c c : conns) {
            if (String.isNotBlank(repository) && c.Repository__c == repository) {
                return repository;
            }
        }
        return conns.isEmpty() ? null : conns[0].Repository__c;
    }

    // Runs are filtered by repository only when the hub has more than one connection (one connection: every run).
    private static String filterFor(List<RLY_Git_Connection__c> conns, String repository) {
        return conns.size() > 1 ? repository : null;
    }

    // The runs still going and the recent ones, newest first, each once.
    private static List<RLY_Pipeline_Run__c> merged(List<RLY_Pipeline_Run__c> active, List<RLY_Pipeline_Run__c> recent) {
        Map<Id, RLY_Pipeline_Run__c> byId = new Map<Id, RLY_Pipeline_Run__c>(active);
        List<RLY_Pipeline_Run__c> out = new List<RLY_Pipeline_Run__c>(active);
        for (RLY_Pipeline_Run__c r : recent) {
            if (!byId.containsKey(r.Id)) {
                out.add(r);
            }
        }
        return out;
    }
}
