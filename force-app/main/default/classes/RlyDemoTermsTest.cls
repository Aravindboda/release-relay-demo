@IsTest
private class RlyDemoTermsTest {
    @IsTest
    static void daysByTier() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(60, RlyDemoTerms.days('Gold'), 'Gold');
            System.assertEquals(45, RlyDemoTerms.days('Silver'), 'Silver');
            System.assertEquals(30, RlyDemoTerms.days(null), 'Default');
        }
    }
}
