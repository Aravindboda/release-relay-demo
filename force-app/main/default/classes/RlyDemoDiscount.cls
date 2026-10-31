/** Discount rules, for the Release Relay end-to-end run (failing test). */
public with sharing class RlyDemoDiscount {
    public static Decimal apply(Decimal amount) {
        return amount == null ? 0 : amount * 0.9;
    }
}