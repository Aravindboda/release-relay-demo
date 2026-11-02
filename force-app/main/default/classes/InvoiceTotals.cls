/**
 * @description Adds up invoice lines: subtotal, discount and total, rounded to cents.
 */
public with sharing class InvoiceTotals {
    /**
     * @description The invoice total after a percentage discount.
     * @param amounts the line amounts
     * @param discountPercent the discount, 0 to 100
     * @return the total, rounded to 2 decimals
     */
    public static Decimal total(List<Decimal> amounts, Decimal discountPercent) {
        Decimal subtotal = 0;
        for (Decimal a : amounts) {
            subtotal += a == null ? 0 : a;
        }
        Decimal pct = discountPercent == null ? 0 : Math.min(Math.max(discountPercent, 0), 100);
        return (subtotal * (100 - pct) / 100).setScale(2, RoundingMode.HALF_UP);
    }
}