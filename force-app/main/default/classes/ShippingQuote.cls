/**
 * @description A shipping quote from the parcel weight: base fee plus a rate per pound, free over a threshold.
 */
public with sharing class ShippingQuote {
    private static final Decimal BASE = 5.00;
    private static final Decimal PER_POUND = 1.20;
    private static final Decimal FREE_FROM = 150;

    /**
     * @description The shipping cost.
     * @param pounds the parcel weight
     * @param orderTotal the order total
     * @return the cost, 0 when the order total reaches the free-shipping threshold
     */
    public static Decimal quote(Decimal pounds, Decimal orderTotal) {
        if (orderTotal != null && orderTotal >= FREE_FROM) {
            return 0;
        }
        Decimal w = pounds == null || pounds < 0 ? 0 : pounds;
        return (BASE + w * PER_POUND).setScale(2, RoundingMode.HALF_UP);
    }
}