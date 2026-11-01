@IsTest
private class RlyDemoSearchTest {
    @IsTest
    static void findsAccounts() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Account(Name = 'Relay Demo');
            System.assertEquals(1, RlyDemoSearch.byName('Relay Demo').size(), 'Found by name');
        }
    }
}