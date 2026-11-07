/**
 * @description The four DORA measures for the Metrics tab, from the release history of one org (or every org):
 *   deploys          successful deploys, counted per day by Salesforce, then per week or month
 *   lead time        raised → running in the org: a promotion counts each release it carries from the day that release
 *                    was raised; any other release from its own raise (median, hours)
 *   failure rate     failed deploys + rollbacks + hotfixes deployed, over deploys tried (percent)
 *   time to restore  from a failed deploy or a rollback to the next successful deploy in that org (median, hours)
 * Each tile has this period's value and the period before's. The developer org filter applies to lead time only.
 */
public with sharing class RlyMetricsDora {

    private static final String DEPLOYED = 'Deployed';

    private final RlyMetricsFilter f;
    private final RlyMetricsBuckets buckets;
    private final List<RLY_Release_Event__c> events;

    /**
     * @description Reads the period's (and the period before's) deploys, failed deploys and rollbacks.
     * @param f the filter
     * @param buckets the weeks or months
     */
    public RlyMetricsDora(RlyMetricsFilter f, RlyMetricsBuckets buckets) {
        this.f = f;
        this.buckets = buckets;
        events = RlyMetricsStore.deployEvents(f.previousStart, f.periodEnd, f.orgId);
    }

    /**
     * @description Adds the four tiles and their charts.
     * @param m the metrics
     */
    public void addTo(RlyMetricsViews.Metrics m) {
        m.truncated = m.truncated || events.size() >= RlyMetricsStore.MAX_EVENTS;
        deploys(m);
        leadTime(m);
        failureRate(m);
        restore(m);
    }

    // Deploys: Salesforce's grouped counts per day, so a busy period is still exact.
    private void deploys(RlyMetricsViews.Metrics m) {
        RlyMetricsViews.Series s = buckets.series('deploys', 'Deploys', 'count');
        Integer current = 0;
        Integer before = 0;
        Date firstDay = f.periodStart.date();
        for (AggregateResult r : RlyMetricsHistory.deploysPerDay(f.previousStart, f.periodEnd, f.orgId)) {
            Date d = (Date) r.get('d');
            Integer n = Integer.valueOf(r.get('n'));
            if (d < firstDay) {
                before += n;
                continue;
            }
            current += n;
            Integer i = buckets.indexOf(d);
            if (i >= 0) {
                RlyMetricsSeries.addCount(s.points[i], n);
            }
        }
        RlyMetricsViews.Tile t = RlyMetricsSeries.tile('deploys', 'Deploys', 'count');
        t.value = current;
        t.previous = before;
        t.higherIsBetter = true;
        t.dora = true;
        Decimal perWeek = (Decimal.valueOf(current) * 7 / f.days).setScale(1, System.RoundingMode.HALF_UP);
        t.detail = perWeek + ' a week';
        m.tiles.add(t);
        m.series.add(s);
    }

    // Lead time: each deployed release (or each release a promotion carries) from its raise.
    private void leadTime(RlyMetricsViews.Metrics m) {
        Map<Id, RLY_Release__c> carried = RlyMetricsStore.raised(carriedIds());
        RlyMetricsMedians c = new RlyMetricsMedians(buckets, f.periodStart);
        for (RLY_Release_Event__c e : events) {
            if (e.Event_Type__c != DEPLOYED) {
                continue;
            }
            for (Raised r : raisedOf(e, carried)) {
                if (f.devOrgId == null || r.sourceOrgId == f.devOrgId) {
                    c.add(e.Occurred_On__c, RlyMetricsBuckets.hoursBetween(r.raisedAt, e.Occurred_On__c));
                }
            }
        }
        m.tiles.add(dora(c.tile('leadTime', 'Lead time')));
        m.series.add(c.series('leadTime', 'Lead time (median)'));
    }

    // Failure rate: failed deploys, rollbacks and hotfixes deployed, over deploys tried.
    private void failureRate(RlyMetricsViews.Metrics m) {
        RlyMetricsRate rate = new RlyMetricsRate(buckets, f.periodStart);
        for (RLY_Release_Event__c e : events) {
            if (e.Event_Type__c == DEPLOYED || e.Event_Type__c == 'Deploy_Failed') {
                rate.tried(e.Occurred_On__c);
            }
            if (e.Event_Type__c != DEPLOYED || e.Release__r.Is_Hotfix__c == true) {
                rate.failed(e.Occurred_On__c);
            }
        }
        m.tiles.add(dora(rate.tile('failureRate', 'Change failure rate')));
        m.series.add(rate.series('failureRate', 'Change failure rate'));
    }

    // Time to restore: a failed deploy or a rollback, to the next successful deploy in the same org.
    private void restore(RlyMetricsViews.Metrics m) {
        RlyMetricsMedians c = new RlyMetricsMedians(buckets, f.periodStart);
        Map<Id, Datetime> brokenSince = new Map<Id, Datetime>();
        for (RLY_Release_Event__c e : events) {
            if (e.Event_Type__c != DEPLOYED) {
                if (!brokenSince.containsKey(e.Org__c)) {
                    brokenSince.put(e.Org__c, e.Occurred_On__c);
                }
            } else if (brokenSince.containsKey(e.Org__c)) {
                Datetime since = brokenSince.remove(e.Org__c);
                c.add(e.Occurred_On__c, RlyMetricsBuckets.hoursBetween(since, e.Occurred_On__c));
            }
        }
        m.tiles.add(dora(c.tile('restore', 'Time to restore')));
        m.series.add(c.series('restore', 'Time to restore (median)'));
    }

    private static RlyMetricsViews.Tile dora(RlyMetricsViews.Tile t) {
        t.dora = true;
        return t;
    }

    // The releases promotions carry.
    private Set<Id> carriedIds() {
        Set<Id> ids = new Set<Id>();
        for (RLY_Release_Event__c e : events) {
            ids.addAll(idsIn(e.Release__r.Carried_Releases__c));
        }
        return ids;
    }

    // A deployed release's raise: when and from which org.
    private class Raised {
        private final Datetime raisedAt;
        private final Id sourceOrgId;

        private Raised(Datetime raisedAt, Id sourceOrgId) {
            this.raisedAt = raisedAt;
            this.sourceOrgId = sourceOrgId;
        }
    }

    // A deploy's releases: those a promotion carries, or the release itself.
    private static List<Raised> raisedOf(RLY_Release_Event__c e, Map<Id, RLY_Release__c> carried) {
        List<Raised> out = new List<Raised>();
        for (Id i : idsIn(e.Release__r.Carried_Releases__c)) {
            if (carried.containsKey(i)) {
                out.add(new Raised(carried.get(i).CreatedDate, carried.get(i).Source_Org__c));
            }
        }
        if (out.isEmpty()) {
            out.add(new Raised(e.Release__r.CreatedDate, e.Release__r.Source_Org__c));
        }
        return out;
    }

    private static Set<Id> idsIn(String commaSeparated) {
        Set<Id> ids = new Set<Id>();
        for (String s : String.isBlank(commaSeparated) ? new List<String>() : commaSeparated.split(',')) {
            String v = s.trim();
            if ((v.length() == 15 || v.length() == 18) && v.isAlphanumeric()) {
                ids.add(Id.valueOf(v));
            }
        }
        return ids;
    }
}
