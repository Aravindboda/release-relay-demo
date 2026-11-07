/**
 * @description A rate for the Metrics tab (change failure rate, checks failing): things that went wrong over things
 * tried, per week or month and per period (this one and the one before), in percent.
 */
public with sharing class RlyMetricsRate {

    private final RlyMetricsBuckets buckets;
    private final Datetime periodStart;
    private final List<Integer[]> perBucket = new List<Integer[]>();
    private final Integer[] current = new Integer[]{ 0, 0 };
    private final Integer[] before = new Integer[]{ 0, 0 };

    /**
     * @description An empty rate.
     * @param buckets the weeks or months
     * @param periodStart where this period starts
     */
    public RlyMetricsRate(RlyMetricsBuckets buckets, Datetime periodStart) {
        this.buckets = buckets;
        this.periodStart = periodStart;
        for (Integer i = 0; i < buckets.size(); i++) {
            perBucket.add(new Integer[]{ 0, 0 });
        }
    }

    /**
     * @description Counts something tried.
     * @param moment when
     */
    public void tried(Datetime moment) {
        bump(moment, 0);
    }

    /**
     * @description Counts something that went wrong.
     * @param moment when
     */
    public void failed(Datetime moment) {
        bump(moment, 1);
    }

    /**
     * @description The tile: this period's percent and the period before's.
     * @param key its key
     * @param label its name
     * @return the tile (detail: "2 of 26")
     */
    public RlyMetricsViews.Tile tile(String key, String label) {
        RlyMetricsViews.Tile t = RlyMetricsSeries.tile(key, label, 'percent');
        t.value = percent(current);
        t.previous = percent(before);
        t.detail = current[1] + ' of ' + current[0];
        return t;
    }

    /**
     * @description The chart: the percent per bucket.
     * @param key the tile it belongs to
     * @param label its title
     * @return the chart
     */
    public RlyMetricsViews.Series series(String key, String label) {
        RlyMetricsViews.Series s = buckets.series(key, label, 'percent');
        for (Integer i = 0; i < s.points.size(); i++) {
            s.points[i].value = percent(perBucket[i]);
            s.points[i].count = perBucket[i][0];
        }
        return s;
    }

    // Slot 0 counts things tried, slot 1 things gone wrong.
    private void bump(Datetime moment, Integer slot) {
        if (moment < periodStart) {
            before[slot]++;
            return;
        }
        current[slot]++;
        Integer i = buckets.indexOf(moment);
        if (i >= 0) {
            perBucket[i][slot]++;
        }
    }

    private static Decimal percent(Integer[] counts) {
        return counts[0] == 0 ? null : (Decimal.valueOf(counts[1]) * 100 / counts[0]).setScale(0, System.RoundingMode.HALF_UP);
    }
}
