public with sharing class RlyDemoHotfix {
    /**
     * @description Rounds a discount to a whole percent.
     * @param pct the discount
     * @return the rounded discount, 0 when there is none
     */
    public static Decimal rounded(Decimal pct) {
        return pct == null ? 0 : pct.setScale(0, System.RoundingMode.HALF_UP);
    }
}