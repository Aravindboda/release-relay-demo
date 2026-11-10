/**
 * @description The Archive tab's numbers from the summary rows (RLY_Archive_Run__c): totals of every run (SUM), releases
 * archived per calendar month for the last 12 months (GROUP BY CALENDAR_YEAR and CALENDAR_MONTH of Started__c, in the
 * viewer's time zone), and the nightly job's health: nightly runs of the last 30 days per status, the last call stamped
 * on the settings record and the nights missed (nightly on and no call for more than 26 hours). The Home tab's health
 * line shows missed nights to admins. Runs are shared hub records: read in system mode in the private inner without
 * sharing class.
 */
public with sharing class RlyArchiveStats {

    private static final List<String> MONTH_LABELS = new List<String>{ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
        'Oct', 'Nov', 'Dec' };
    private static final Integer MISSED_AFTER_HOURS = 26;
    private static final Integer HEALTH_DAYS = 30;
    private static final Long HOUR_MS = 3600000L;

    /**
     * @description Fills the totals of every run: releases, records, storage freed, how many runs and the first one.
     * @param a the Archive tab
     */
    public static void totals(RlyArchiveViews.Archive a) {
        List<AggregateResult> rows = new Data().totals();
        if (rows.isEmpty()) {
            return;
        }
        AggregateResult t = rows[0];
        a.archivedReleases = whole(t.get('rel'));
        a.archivedRecords = whole(t.get('rec'));
        a.freedKB = whole(t.get('kb'));
        a.runCount = whole(t.get('n'));
        a.firstRun = (Datetime) t.get('f');
    }

    /**
     * @description Releases archived per month, the last 12 calendar months, oldest first (months with none are 0).
     * @return the months
     */
    public static List<RlyArchiveViews.MonthBar> months() {
        Date current = RlyArchiveService.now().date();
        Date first = Date.newInstance(current.year(), current.month(), 1).addMonths(-11);
        Map<String, RlyArchiveViews.MonthBar> byKey = new Map<String, RlyArchiveViews.MonthBar>();
        List<RlyArchiveViews.MonthBar> out = new List<RlyArchiveViews.MonthBar>();
        for (Integer i = 0; i < 12; i++) {
            Date d = first.addMonths(i);
            RlyArchiveViews.MonthBar m = new RlyArchiveViews.MonthBar();
            m.year = d.year();
            m.month = d.month();
            m.label = MONTH_LABELS[d.month() - 1];
            byKey.put(String.valueOf(m.year) + '-' + m.month, m);
            out.add(m);
        }
        Datetime since = Datetime.newInstance(first.year(), first.month(), 1);
        for (AggregateResult r : new Data().perMonth(since)) {
            String key = String.valueOf(whole(r.get('y'))) + '-' + whole(r.get('m'));
            if (byKey.containsKey(key)) {
                byKey.get(key).releases += whole(r.get('rel'));
            }
        }
        return out;
    }

    /**
     * @description The nightly job's health.
     * @param conn the settings record, or null
     * @return the health
     */
    public static RlyArchiveViews.Health health(RLY_Git_Connection__c conn) {
        RlyArchiveViews.Health h = new RlyArchiveViews.Health();
        Datetime since = RlyArchiveService.now().addDays(-HEALTH_DAYS);
        Data data = new Data();
        for (AggregateResult r : data.nightlyPerStatus(since)) {
            Integer n = whole(r.get('n'));
            String status = (String) r.get('s');
            h.runs += n;
            h.succeeded += status == RlyArchiveRuns.SUCCEEDED ? n : 0;
            h.failed += status == RlyArchiveRuns.FAILED ? n : 0;
            h.partial += status == RlyArchiveRuns.PARTIAL ? n : 0;
        }
        h.lastCall = conn == null ? null : conn.Last_Nightly_Call__c;
        h.lastCallResult = conn == null ? null : conn.Last_Nightly_Result__c;
        h.missedNights = missedNights(conn);
        List<RLY_Archive_Run__c> failures = data.lastNightlyFailure(since);
        h.lastFailure = failures.isEmpty() ? null : RlyArchiveRuns.view(failures[0]);
        return h;
    }

    /**
     * @description Nights the scheduled job missed: nightly on and no call for more than 26 hours, counted in whole days
     * since the last call (or since nightly was turned on, before any call).
     * @param conn the settings record, or null
     * @return the nights, or 0
     */
    public static Integer missedNights(RLY_Git_Connection__c conn) {
        if (!RlyArchiveSettings.nightly(conn) || RlyArchiveSettings.days(conn) == null) {
            return 0;
        }
        Datetime base = conn.Last_Nightly_Call__c != null ? conn.Last_Nightly_Call__c : conn.Retention_Changed_On__c;
        if (base == null) {
            return 0;
        }
        Long hours = (RlyArchiveService.now().getTime() - base.getTime()) / HOUR_MS;
        return hours > MISSED_AFTER_HOURS ? Math.max(1, (hours / 24).intValue()) : 0;
    }

    /**
     * @description The Home tab's health item for admins in the production hub when the scheduled job missed a night.
     * @return the item, or null when nothing was missed (or the viewer isn't an admin)
     */
    public static RlyHomeHealth.Item homeItem() {
        if (!RlyOrgController.isAdmin() || !RlyArchiveService.onHub()) {
            return null;
        }
        RLY_Git_Connection__c conn = RlyArchiveSettings.read();
        Integer missed = missedNights(conn);
        if (missed == 0) {
            return null;
        }
        RlyHomeHealth.Item i = RlyHomeHealth.item('archive', 'Nightly archive');
        i.tab = RlyArchiveService.ARCHIVE_TAB;
        i.title = '"Archive every night" is on, but the pipeline\'s scheduled job hasn\'t called for '
            + (missed == 1 ? '1 night' : String.valueOf(missed) + ' nights') + '. Open the Archive tab.';
        return missed == 1 ? RlyHomeHealth.withState(i, 'missed last night', RlyHomeHealth.TONE_WAIT)
            : RlyHomeHealth.withState(i, 'missed the last ' + missed + ' nights', RlyHomeHealth.TONE_BAD);
    }

    private static Integer whole(Object o) {
        return o == null ? 0 : Decimal.valueOf(String.valueOf(o)).intValue();
    }

    /** @description Runs are shared hub records: read in system mode. */
    private without sharing class Data {

        /**
         * @description Totals of every run.
         * @return one row: rel, rec, kb, n and f (the first start)
         */
        public List<AggregateResult> totals() {
            return [SELECT SUM(Releases_Removed__c) rel, SUM(Records_Removed__c) rec, SUM(Storage_Freed_KB__c) kb,
                        COUNT(Id) n, MIN(Started__c) f
                    FROM RLY_Archive_Run__c WHERE Started__c != null WITH SYSTEM_MODE];
        }

        /**
         * @description Releases archived per calendar month of the start (viewer's time zone).
         * @param since the first day of the oldest month
         * @return rows of y, m and rel
         */
        public List<AggregateResult> perMonth(Datetime since) {
            return [SELECT CALENDAR_YEAR(convertTimezone(Started__c)) y, CALENDAR_MONTH(convertTimezone(Started__c)) m,
                        SUM(Releases_Removed__c) rel
                    FROM RLY_Archive_Run__c WHERE Started__c >= :since WITH SYSTEM_MODE
                    GROUP BY CALENDAR_YEAR(convertTimezone(Started__c)), CALENDAR_MONTH(convertTimezone(Started__c))];
        }

        /**
         * @description Nightly runs since a moment, per status.
         * @param since the moment
         * @return rows of s and n
         */
        public List<AggregateResult> nightlyPerStatus(Datetime since) {
            return [SELECT Status__c s, COUNT(Id) n FROM RLY_Archive_Run__c
                    WHERE How__c = :RlyArchiveRuns.NIGHTLY AND Started__c >= :since WITH SYSTEM_MODE GROUP BY Status__c];
        }

        /**
         * @description The newest failed nightly run since a moment.
         * @param since the moment
         * @return the row, or none
         */
        public List<RLY_Archive_Run__c> lastNightlyFailure(Datetime since) {
            return [SELECT Id, Name, Started__c, Finished__c, How__c, Run_By__c, Run_By__r.Name, Retention_Days__c, Cutoff__c,
                        Passes__c, Releases_Removed__c, Records_Removed__c, Storage_Freed_KB__c, Oldest_Removed__c, Newest_Removed__c,
                        Status__c, Message__c, Pipeline_Run_Url__c
                    FROM RLY_Archive_Run__c
                    WHERE How__c = :RlyArchiveRuns.NIGHTLY AND Status__c = :RlyArchiveRuns.FAILED AND Started__c >= :since
                    WITH SYSTEM_MODE ORDER BY Started__c DESC LIMIT 1];
        }
    }
}
