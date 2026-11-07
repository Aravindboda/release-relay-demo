/**
 * @description Durations in hours for the Metrics tab (lead time, time to restore, approval wait): their median per week
 * or month and per period (this one and the one before).
 */
public with sharing class RlyMetricsMedians {

    private final RlyMetricsBuckets buckets;
    private final Datetime periodStart;
    private final List<List<Decimal>> perBucket = new List<List<Decimal>>();
    private final List<Decimal> current = new List<Decimal>();
    private final List<Decimal> before = new List<Decimal>();

    /**
     * @description An empty collector.
     * @param buckets the weeks or months
     * @param periodStart where this period starts (earlier durations count for the period before)
     */
    public RlyMetricsMedians(RlyMetricsBuckets buckets, Datetime periodStart) {
        this.buckets = buckets;
        this.periodStart = periodStart;
        for (Integer i = 0; i < buckets.size(); i++) {
            perBucket.add(new List<Decimal>());
        }
    }

    /**
     * @description Adds a duration.
     * @param moment when it ended (picks the period and the bucket)
     * @param hours the duration
     */
    public void add(Datetime moment, Decimal hours) {
        if (hours == null || hours < 0) {
            return;
        }
        if (moment < periodStart) {
            before.add(hours);
            return;
        }
        current.add(hours);
        Integer i = buckets.indexOf(moment);
        if (i >= 0) {
            perBucket[i].add(hours);
        }
    }

    /**
     * @description The tile: this period's median and the period before's.
     * @param key its key
     * @param label its name
     * @return the tile (detail: how many it's made of)
     */
    public RlyMetricsViews.Tile tile(String key, String label) {
        RlyMetricsViews.Tile t = RlyMetricsSeries.tile(key, label, 'hours');
        t.value = RlyMetricsBuckets.median(current);
        t.previous = RlyMetricsBuckets.median(before);
        t.detail = 'median of ' + current.size();
        return t;
    }

    /**
     * @description The chart: the median per bucket.
     * @param key the tile it belongs to
     * @param label its title
     * @return the chart
     */
    public RlyMetricsViews.Series series(String key, String label) {
        RlyMetricsViews.Series s = buckets.series(key, label, 'hours');
        for (Integer i = 0; i < s.points.size(); i++) {
            s.points[i].value = RlyMetricsBuckets.median(perBucket[i]);
            s.points[i].count = perBucket[i].size();
        }
        return s;
    }
}
