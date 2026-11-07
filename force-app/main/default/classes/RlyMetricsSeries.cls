/**
 * @description Builds the Metrics tab's tiles and charts: an empty chart per week or month, counts, and tiles with this
 * period's value and the period before's. Durations are RlyMetricsMedians, rates RlyMetricsRate.
 */
public with sharing class RlyMetricsSeries {

    /**
     * @description Adds to a count point.
     * @param p the point
     * @param n how many
     */
    public static void addCount(RlyMetricsViews.Point p, Integer n) {
        p.count += n;
        p.value = p.count;
    }

    /**
     * @description An empty tile.
     * @param key its key
     * @param label its name
     * @param unit count, hours or percent
     * @return the tile
     */
    public static RlyMetricsViews.Tile tile(String key, String label, String unit) {
        RlyMetricsViews.Tile t = new RlyMetricsViews.Tile();
        t.key = key;
        t.label = label;
        t.unit = unit;
        return t;
    }
}
