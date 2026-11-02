/**
 * @description Tests for InvoiceTotals.
 */
@IsTest
private class InvoiceTotalsTest {
    @IsTest
    static void addsLinesAndDiscount() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(90.00, InvoiceTotals.total(new List<Decimal>{ 60, 40, null }, 10), 'Ten percent off 100');
            System.assertEquals(100.00, InvoiceTotals.total(new List<Decimal>{ 100 }, -5), 'Negative discount ignored');
        }
    }
}