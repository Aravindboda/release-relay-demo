public with sharing class RlyDemoHotfix {
    /**
     * @description Rounds a discount to a whole percent.
     * @param pct the discount
     * @return the rounded discount, 0 when there is none
     */
    public static Decimal rounded(Decimal pct) {
        return pct == null ? 0 : pct.setScale(0, System.RoundingMode.HALF_UP);
    }

    /**
     * @description Rounds a discount and keeps it at or under a maximum.
     * @param pct the discount
     * @param maxPct the highest discount allowed
     * @return the rounded discount, never above the maximum
     */
    public static Decimal capped(Decimal pct, Decimal maxPct) {
        Decimal r = rounded(pct);
        return maxPct != null && r > maxPct ? maxPct : r;
    }
}
