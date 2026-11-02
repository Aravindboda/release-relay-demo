/**
 * @description Sales tax for an amount at a state rate.
 */
public with sharing class TaxCalculator {
    private static final Map<String, Decimal> RATES = new Map<String, Decimal>{ 'TX' => 6.25, 'CA' => 7.25, 'NY' => 4.00 };

    /**
     * @description The tax on an amount for a US state (0 for a state without a rate).
     * @param amount the amount
     * @param state the two-letter state code
     * @return the tax, rounded to 2 decimals
     */
    public static Decimal tax(Decimal amount, String state) {
        Decimal rate = state == null ? null : RATES.get(state.toUpperCase());
        return rate == null || amount == null ? 0 : (amount * rate / 100).setScale(2, RoundingMode.HALF_UP);
    }
}