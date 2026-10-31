@IsTest
private class RlyDemoGreetingTest {
    @IsTest
    static void greetsByName() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('Hello, Ana', RlyDemoGreeting.greet(' Ana '));
            System.assertEquals('Hello there', RlyDemoGreeting.greet(''));
        }
    }
}