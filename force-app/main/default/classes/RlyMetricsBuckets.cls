/**
 * @description The Metrics tab's weeks and months: the buckets of a period (weeks start Monday; months on the 1st; in the
 * person's time zone), which bucket a moment falls in, and medians.
 */
public with sharing class RlyMetricsBuckets {

    private final List<Date> starts = new List<Date>();
    private final Boolean byWeek;

    /**
     * @description The buckets that cover a period.
     * @param f the filter (its period and whether it goes by week)
     */
    public RlyMetricsBuckets(RlyMetricsFilter f) {
        byWeek = f.byWeek();
        Date first = startOf(f.periodStart.date());
        Date last = f.periodEnd.date();
        for (Date d = first; d <= last; d = byWeek ? d.addDays(7) : d.addMonths(1)) {
            starts.add(d);
        }
    }

    /**
     * @description Empty points, one per bucket.
     * @return the points, oldest first
     */
    public List<RlyMetricsViews.Point> points() {
        List<RlyMetricsViews.Point> out = new List<RlyMetricsViews.Point>();
        for (Date d : starts) {
            RlyMetricsViews.Point p = new RlyMetricsViews.Point();
            p.day = String.valueOf(d);
            p.label = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format(byWeek ? 'd MMM' : 'MMM yyyy');
            out.add(p);
        }
        return out;
    }

    /**
     * @description How many buckets.
     * @return the count
     */
    public Integer size() {
        return starts.size();
    }

    /**
     * @description An empty chart, one point per bucket.
     * @param key the tile it belongs to
     * @param label the chart's title
     * @param unit count, hours or percent
     * @return the chart
     */
    public RlyMetricsViews.Series series(String key, String label, String unit) {
        RlyMetricsViews.Series s = new RlyMetricsViews.Series();
        s.key = key;
        s.label = label;
        s.unit = unit;
        s.points = points();
        return s;
    }

    /**
     * @description The bucket a day falls in.
     * @param d the day
     * @return its index, or -1 outside the period
     */
    public Integer indexOf(Date d) {
        if (d == null || starts.isEmpty() || d < starts[0]) {
            return -1;
        }
        Integer i = byWeek ? starts[0].daysBetween(d) / 7 : (d.year() - starts[0].year()) * 12 + d.month() - starts[0].month();
        return i < starts.size() ? i : -1;
    }

    /**
     * @description The bucket a moment falls in (in the person's time zone).
     * @param moment the moment
     * @return its index, or -1
     */
    public Integer indexOf(Datetime moment) {
        return moment == null ? -1 : indexOf(moment.date());
    }

    /**
     * @description The middle value (the mean of the two middle ones for an even count).
     * @param values the values
     * @return the median, or null for none
     */
    public static Decimal median(List<Decimal> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        List<Decimal> sorted = new List<Decimal>(values);
        sorted.sort();
        Integer n = sorted.size();
        Decimal mid = Math.mod(n, 2) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
        return mid.setScale(1, System.RoundingMode.HALF_UP);
    }

    /**
     * @description Hours between two moments.
     * @param fromTime the first
     * @param toTime the second
     * @return the hours, one decimal
     */
    public static Decimal hoursBetween(Datetime fromTime, Datetime toTime) {
        Decimal ms = toTime.getTime() - fromTime.getTime();
        return (ms / 3600000).setScale(1, System.RoundingMode.HALF_UP);
    }

    // The bucket a day starts: Monday of its week, or the 1st of its month.
    private Date startOf(Date d) {
        if (!byWeek) {
            return d.toStartOfMonth();
        }
        // 1 January 1900 was a Monday: days since then, modulo 7, is the day of the week (0 = Monday), whatever the locale.
        Integer dow = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7);
        return d.addDays(-dow);
    }
}
