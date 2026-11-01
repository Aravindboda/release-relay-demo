@IsTest
private class RlyDemoHotfixTest {
    @IsTest
    static void roundsToWholePercent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(13, RlyDemoHotfix.rounded(12.5));
            System.assertEquals(0, RlyDemoHotfix.rounded(null));
        }
    }

    @IsTest
    static void capsTheDiscount() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(20, RlyDemoHotfix.capped(27.4, 20), 'Capped');
            System.assertEquals(13, RlyDemoHotfix.capped(12.5, 20), 'Under the cap');
        }
    }
}
