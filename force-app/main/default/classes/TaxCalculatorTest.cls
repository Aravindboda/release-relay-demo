/**
 * @description Tests for TaxCalculator.
 */
@IsTest
private class TaxCalculatorTest {
    @IsTest
    static void taxesByState() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(6.25, TaxCalculator.tax(100, 'tx'), 'Texas rate');
            System.assertEquals(0, TaxCalculator.tax(100, 'OR'), 'No rate');
            System.assertEquals(0, TaxCalculator.tax(null, 'CA'), 'No amount');
        }
    }
}