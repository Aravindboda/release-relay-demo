@IsTest
private class RlyDemoGreetingTest {
    @IsTest
    static void greetsByName() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('Hi, Ana!', RlyDemoGreeting.greet(' Ana '), 'Greets by name');
            System.assertEquals('Hello there', RlyDemoGreeting.greet(''), 'Blank name');
        }
    }
}