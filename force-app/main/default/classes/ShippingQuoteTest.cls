/**
 * @description Tests for ShippingQuote.
 */
@IsTest
private class ShippingQuoteTest {
    @IsTest
    static void quotesByWeight() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(11.00, ShippingQuote.quote(5, 40), 'Base plus 5 lb');
            System.assertEquals(0, ShippingQuote.quote(5, 200), 'Free over 150');
            System.assertEquals(5.00, ShippingQuote.quote(null, null), 'Base only');
        }
    }
}