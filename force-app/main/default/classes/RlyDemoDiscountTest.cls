@IsTest
private class RlyDemoDiscountTest {
    @IsTest
    static void tenPercentOff() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(80, RlyDemoDiscount.apply(100), 'Expects 20% off, but the rule gives 10%');
        }
    }
}