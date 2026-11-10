/**
 * @description The Metrics tab (rlyMetrics), read only for every Release Relay user: the filter choices, every number
 * for one set of filters (RlyMetricsDora: deploys, lead time, change failure rate, time to restore; RlyMetricsFlow:
 * approval wait, checks failing) and "why checks fail", read a few releases at a time (RlyMetricsChecks). Everything
 * comes from Release Relay's own history; nothing is written.
 */
public with sharing class RlyMetricsController {

    /**
     * @description The orgs and periods to filter by.
     * @return the options
     */
    @AuraEnabled
    public static RlyMetricsViews.Options options() {
        try {
            RlyMetricsViews.Options o = new RlyMetricsViews.Options();
            for (RLY_Org__c org : RlyMetricsStore.orgs()) {
                RlyMetricsViews.OrgOption x = new RlyMetricsViews.OrgOption();
                x.id = org.Id;
                x.name = org.Name;
                x.role = org.Role__c;
                if (org.Role__c == 'Developer') {
                    o.devOrgs.add(x);
                } else {
                    o.orgs.add(x);
                }
                o.defaultOrgId = org.Role__c == 'Hub' ? org.Id : o.defaultOrgId;
            }
            o.periods = new List<Integer>{ 30, 90, 180, 365 };
            return o;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Every number for one set of filters.
     * @param filterJson {orgId, devOrgId, days}
     * @return the tiles and charts
     */
    @AuraEnabled
    public static RlyMetricsViews.Metrics metrics(String filterJson) {
        try {
            RlyMetricsFilter f = RlyMetricsFilter.parse(filterJson);
            RlyMetricsBuckets buckets = new RlyMetricsBuckets(f);
            RlyMetricsViews.Metrics m = new RlyMetricsViews.Metrics();
            m.days = f.days;
            m.byWeek = f.byWeek();
            m.periodStart = f.periodStart;
            m.periodEnd = f.periodEnd;
            new RlyMetricsDora(f, buckets).addTo(m);
            new RlyMetricsFlow(f, buckets).addTo(m);
            return m;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Why some releases' checks failed (a part of the list metrics returned).
     * @param releaseIds at most 10 releases
     * @return the reasons and conflict files of this part
     */
    @AuraEnabled
    public static RlyMetricsViews.Reasons checkReasons(List<Id> releaseIds) {
        try {
            return RlyMetricsChecks.read(releaseIds);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
