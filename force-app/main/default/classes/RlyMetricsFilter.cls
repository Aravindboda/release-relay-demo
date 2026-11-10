/**
 * @description The Metrics tab's filters (RlyMetricsController): the org deploys are counted in (blank: every org), the
 * developer org whose releases count for lead time, approvals and checks (blank: all), and the period: the last 30, 90,
 * 180 or 365 days. The period before it, of the same length, gives each tile its trend. Up to 92 days the charts use
 * weeks (starting Monday), beyond that months, both in the person's time zone.
 */
public with sharing class RlyMetricsFilter {

    /** @description The periods offered, in days. */
    public static final Set<Integer> PERIODS = new Set<Integer>{ 30, 90, 180, 365 };
    /** @description The default period, in days. */
    public static final Integer DEFAULT_DAYS = 90;
    /** @description The longest period that uses weeks. */
    public static final Integer WEEKS_UP_TO = 92;

    /** @description The org deploys are counted in, or null for every org. */
    public Id orgId;
    /** @description The developer org whose releases count for lead time, approvals and checks, or null for all. */
    public Id devOrgId;
    /** @description The period, in days. */
    public Integer days = DEFAULT_DAYS;
    /** @description Start of the period. */
    public Datetime periodStart;
    /** @description End of the period (now). */
    public Datetime periodEnd;
    /** @description Start of the period before (same length). */
    public Datetime previousStart;

    /**
     * @description Reads the page's filters: {orgId, devOrgId, days}; anything unknown or out of range is the default.
     * @param filterJson the filters, or blank
     * @return the filter, with its period worked out from now
     */
    public static RlyMetricsFilter parse(String filterJson) {
        RlyMetricsFilter f = new RlyMetricsFilter();
        Map<String, Object> m = new Map<String, Object>();
        if (String.isNotBlank(filterJson)) {
            try {
                Object o = JSON.deserializeUntyped(filterJson);
                m = o instanceof Map<String, Object> ? (Map<String, Object>) o : m;
            } catch (JSONException e) {
                m = new Map<String, Object>();
            }
        }
        f.orgId = idOf(m.get('orgId'));
        f.devOrgId = idOf(m.get('devOrgId'));
        f.days = daysOf(m.get('days'));
        f.periodEnd = System.now();
        f.periodStart = f.periodEnd.addDays(-f.days);
        f.previousStart = f.periodStart.addDays(-f.days);
        return f;
    }

    /**
     * @description Whether the charts use weeks (else months).
     * @return true up to WEEKS_UP_TO days
     */
    public Boolean byWeek() {
        return days <= WEEKS_UP_TO;
    }

    // One of PERIODS, else the default.
    private static Integer daysOf(Object o) {
        String s = o == null ? '' : String.valueOf(o).trim();
        Integer d = s.isNumeric() && s.length() <= 3 ? Integer.valueOf(s) : null;
        return d != null && PERIODS.contains(d) ? d : DEFAULT_DAYS;
    }

    // An RLY_Org__c Id, or null.
    private static Id idOf(Object o) {
        String s = o == null ? '' : String.valueOf(o).trim();
        if ((s.length() != 15 && s.length() != 18) || !s.isAlphanumeric()) {
            return null;
        }
        try {
            Id value = Id.valueOf(s);
            return value.getSobjectType() == RLY_Org__c.SObjectType ? value : null;
        } catch (StringException e) {
            return null;
        }
    }

    /**
     * @description Whether an event's release counts under the developer org filter.
     * @param e the event, with Release__r.Source_Org__c
     * @return true when every org counts or the release came from the filtered org
     */
    public Boolean counts(RLY_Release_Event__c e) {
        return devOrgId == null || e.Release__r.Source_Org__c == devOrgId;
    }
}
