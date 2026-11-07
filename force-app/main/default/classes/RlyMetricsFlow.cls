/**
 * @description The Metrics tab's checks failing, for releases going to one org (or every org) and, when chosen, raised
 * from one developer org (approval wait: RlyMetricsApprovals):
 *   checks failing  validations and code scans that failed, over those run (percent); the failed validations' releases
 *                   are listed (newest first) so the page can read why, a few at a time (RlyMetricsChecks)
 */
public with sharing class RlyMetricsFlow {

    /** @description The most releases "why checks fail" reads. */
    public static final Integer MAX_REASON_RELEASES = 100;

    private final RlyMetricsFilter f;
    private final RlyMetricsBuckets buckets;
    private final List<Id> failedOldestFirst = new List<Id>();
    private RlyMetricsViews.Metrics metrics;

    /**
     * @description For one set of filters.
     * @param f the filter
     * @param buckets the weeks or months
     */
    public RlyMetricsFlow(RlyMetricsFilter f, RlyMetricsBuckets buckets) {
        this.f = f;
        this.buckets = buckets;
    }

    /**
     * @description Adds the approval wait and checks failing tiles and charts.
     * @param m the metrics
     */
    public void addTo(RlyMetricsViews.Metrics m) {
        metrics = m;
        new RlyMetricsApprovals(f, buckets).addTo(m);
        checks(m);
    }

    private void checks(RlyMetricsViews.Metrics m) {
        List<RLY_Release_Event__c> events = RlyMetricsHistory.checks(f.previousStart, f.periodEnd, f.orgId);
        m.truncated = m.truncated || events.size() >= RlyMetricsStore.MAX_EVENTS;
        RlyMetricsRate rate = new RlyMetricsRate(buckets, f.periodStart);
        for (RLY_Release_Event__c e : events) {
            String outcome = counts(e) ? outcomeOf(e) : null;
            if (outcome != null) {
                countCheck(e, outcome, rate);
            }
        }
        keepFailed(m);
        m.tiles.add(rate.tile('checksFailing', 'Checks failing'));
        m.series.add(rate.series('checksFailing', 'Checks failing'));
    }

    // The failed validations' releases, newest first, each once, at most MAX_REASON_RELEASES.
    private void keepFailed(RlyMetricsViews.Metrics m) {
        for (Integer k = failedOldestFirst.size() - 1; k >= 0; k--) {
            Id i = failedOldestFirst[k];
            if (!m.failedReleaseIds.contains(i) && m.failedReleaseIds.size() < MAX_REASON_RELEASES) {
                m.failedReleaseIds.add(i);
            }
        }
    }

    // One check run: tried, and when it failed in this period, a code scan failure or a release to read the reason of.
    private void countCheck(RLY_Release_Event__c e, String outcome, RlyMetricsRate rate) {
        rate.tried(e.Occurred_On__c);
        if (outcome != 'Failed') {
            return;
        }
        rate.failed(e.Occurred_On__c);
        if (e.Occurred_On__c < f.periodStart) {
            return;
        }
        if (e.Event_Type__c == 'Scan') {
            metrics.scanFailures++;
        } else {
            failedOldestFirst.add(e.Release__c);
        }
    }

    /**
     * @description A check event's outcome from its words ("Validation in SIT Failed: …", "Code scan Passed …").
     * @param e the event
     * @return Passed, Failed, or null for anything else (a bypass, a scan that didn't run)
     */
    public static String outcomeOf(RLY_Release_Event__c e) {
        String d = e.Detail__c == null ? '' : e.Detail__c.left(200);
        if (e.Event_Type__c == 'Scan' && d.startsWith('Code scan findings accepted')) {
            return null;
        }
        if (d.contains(' Failed') || d.contains(' Error')) {
            return 'Failed';
        }
        return d.contains(' Passed') ? 'Passed' : null;
    }

    // The developer org filter: only releases raised from it.
    private Boolean counts(RLY_Release_Event__c e) {
        return f.devOrgId == null || e.Release__r.Source_Org__c == f.devOrgId;
    }
}
