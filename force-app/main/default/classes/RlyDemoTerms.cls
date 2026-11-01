/** Payment terms by customer tier, for the Release Relay demo (a new class). */
public with sharing class RlyDemoTerms {
    /**
     * @description Days to pay for a customer tier.
     * @param tier Gold, Silver or anything else
     * @return 60 for Gold, 45 for Silver, else 30
     */
    public static Integer days(String tier) {
        if (tier == 'Gold') {
            return 60;
        }
        return tier == 'Silver' ? 45 : 30;
    }
}
