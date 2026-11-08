/**
 * @description The Metrics tab's approval wait, for releases going to one org (or every org) and, when chosen, raised
 * from one developer org: from the check that made a release ready (its latest validation before the approval) to its
 * approval (median, hours).
 */
public with sharing class RlyMetricsApprovals {

    private final RlyMetricsFilter f;
    private final RlyMetricsBuckets buckets;

    /**
     * @description For one set of filters.
     * @param f the filter
     * @param buckets the weeks or months
     */
    public RlyMetricsApprovals(RlyMetricsFilter f, RlyMetricsBuckets buckets) {
        this.f = f;
        this.buckets = buckets;
    }

    /**
     * @description Adds the approval wait tile and chart.
     * @param m the metrics
     */
    public void addTo(RlyMetricsViews.Metrics m) {
        approvalWait(m);
    }

    private void approvalWait(RlyMetricsViews.Metrics m) {
        List<RLY_Release_Event__c> approvals = RlyMetricsHistory.approvals(f.previousStart, f.periodEnd, f.orgId);
        m.truncated = m.truncated || approvals.size() >= RlyMetricsStore.MAX_EVENTS;
        Set<Id> ids = new Set<Id>();
        for (RLY_Release_Event__c a : approvals) {
            if (f.counts(a)) {
                ids.add(a.Release__c);
            }
        }
        Map<Id, List<Datetime>> checked = new Map<Id, List<Datetime>>();
        for (RLY_Release_Event__c v : RlyMetricsStore.validationsOf(ids, f.periodEnd)) {
            if (!checked.containsKey(v.Release__c)) {
                checked.put(v.Release__c, new List<Datetime>());
            }
            checked.get(v.Release__c).add(v.Occurred_On__c);
        }
        RlyMetricsMedians c = new RlyMetricsMedians(buckets, f.periodStart);
        for (RLY_Release_Event__c a : approvals) {
            Datetime ready = f.counts(a) ? latestBefore(checked.get(a.Release__c), a.Occurred_On__c) : null;
            if (ready != null) {
                c.add(a.Occurred_On__c, RlyMetricsBuckets.hoursBetween(ready, a.Occurred_On__c));
            }
        }
        m.tiles.add(c.tile('approvalWait', 'Approval wait'));
        m.series.add(c.series('approvalWait', 'Approval wait (median)'));
    }

    // The developer org filter: only releases raised from it.

    private static Datetime latestBefore(List<Datetime> moments, Datetime upTo) {
        Datetime best;
        for (Datetime d : moments == null ? new List<Datetime>() : moments) {
            if (d <= upTo && (best == null || d > best)) {
                best = d;
            }
        }
        return best;
    }
}
