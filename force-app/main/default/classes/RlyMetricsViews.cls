/**
 * @description What the Metrics tab shows (RlyMetricsController): tiles with this period's value and the period
 * before's, chart series of points per week or month, horizontal bars (why checks fail, files that conflict most) and the
 * filter choices.
 */
public with sharing class RlyMetricsViews {

    /** @description One tile. */
    public class Tile {
        /** @description deploys, leadTime, failureRate, restore, approvalWait or checksFailing. */
        @AuraEnabled public String key;
        /** @description The tile's name. */
        @AuraEnabled public String label;
        /** @description This period's value, or null when there's nothing to measure. */
        @AuraEnabled public Decimal value;
        /** @description The period before's value, or null. */
        @AuraEnabled public Decimal previous;
        /** @description count, hours or percent. */
        @AuraEnabled public String unit;
        /** @description true when a higher value is better (deploys); false when lower is better. */
        @AuraEnabled public Boolean higherIsBetter = false;
        /** @description A short note, for example "2 of 26". */
        @AuraEnabled public String detail;
        /** @description A DORA measure. */
        @AuraEnabled public Boolean dora = false;
    }

    /** @description One point of a chart: a week or a month. */
    public class Point {
        /** @description The bucket's label (10 Aug, or Sep 2026). */
        @AuraEnabled public String label;
        /** @description The bucket's first day (yyyy-MM-dd). */
        @AuraEnabled public String day;
        /** @description The value, or null when nothing happened. */
        @AuraEnabled public Decimal value;
        /** @description How many things the value is made of. */
        @AuraEnabled public Integer count = 0;
    }

    /** @description One chart. */
    public class Series {
        /** @description The tile it belongs to. */
        @AuraEnabled public String key;
        /** @description The chart's title. */
        @AuraEnabled public String label;
        /** @description count, hours or percent. */
        @AuraEnabled public String unit;
        /** @description The points, oldest first. */
        @AuraEnabled public List<Point> points = new List<Point>();
    }

    /** @description One horizontal bar. */
    public class Bar {
        /** @description What it counts. */
        @AuraEnabled public String label;
        /** @description How many. */
        @AuraEnabled public Integer value = 0;
    }

    /** @description An org to filter by. */
    public class OrgOption {
        /** @description The org. */
        @AuraEnabled public Id id;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Developer, Stage or Hub. */
        @AuraEnabled public String role;
    }

    /** @description The filter choices. */
    public class Options {
        /** @description Orgs releases go to (stages and the hub). */
        @AuraEnabled public List<OrgOption> orgs = new List<OrgOption>();
        /** @description Developer orgs. */
        @AuraEnabled public List<OrgOption> devOrgs = new List<OrgOption>();
        /** @description The org shown first (the hub, which is production). */
        @AuraEnabled public Id defaultOrgId;
        /** @description The periods offered, in days. */
        @AuraEnabled public List<Integer> periods = new List<Integer>();
    }

    /** @description Every number for one set of filters. */
    public class Metrics {
        /** @description The period, in days. */
        @AuraEnabled public Integer days;
        /** @description Charts by week (else by month). */
        @AuraEnabled public Boolean byWeek;
        /** @description Start of the period. */
        @AuraEnabled public Datetime periodStart;
        /** @description End of the period. */
        @AuraEnabled public Datetime periodEnd;
        /** @description The tiles. */
        @AuraEnabled public List<Tile> tiles = new List<Tile>();
        /** @description The charts. */
        @AuraEnabled public List<Series> series = new List<Series>();
        /** @description Checks that failed for the code scan in the period. */
        @AuraEnabled public Integer scanFailures = 0;
        /** @description Releases whose validation failed in the period (newest first), read in parts for the reasons. */
        @AuraEnabled public List<Id> failedReleaseIds = new List<Id>();
        /** @description A read hit its cap (a very busy period): the numbers cover the first events only. */
        @AuraEnabled public Boolean truncated = false;
    }

    /** @description One part of "why checks fail". */
    public class Reasons {
        /** @description Failed validations by reason. */
        @AuraEnabled public List<Bar> reasons = new List<Bar>();
        /** @description Files in conflicts, with how often. */
        @AuraEnabled public List<Bar> files = new List<Bar>();
        /** @description Where the next part starts, or null when done. */
        @AuraEnabled public Integer nextOffset;
    }
}
