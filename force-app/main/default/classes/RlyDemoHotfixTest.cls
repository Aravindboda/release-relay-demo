@IsTest
private class RlyDemoHotfixTest {
    @IsTest
    static void roundsToWholePercent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(13, RlyDemoHotfix.rounded(12.5));
            System.assertEquals(0, RlyDemoHotfix.rounded(null));
        }
    }
}