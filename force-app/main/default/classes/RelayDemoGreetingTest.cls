@IsTest
private class RelayDemoGreetingTest {
    @IsTest
    static void greetsByNameOrDefault() {
        User runner = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runner) {
            System.assertEquals('Hello, DEV!', RelayDemoGreeting.greet('DEV'));
            System.assertEquals('Hello, Release Relay!', RelayDemoGreeting.greet(null));
        }
    }
}