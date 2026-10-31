@IsTest
private class RlyDemoGreetingTest {
    @IsTest
    static void greetsByName() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals('Hi, Ana!', RlyDemoGreeting.greet(' Ana '), 'Greets by name');
            System.assertEquals('Welcome, friend', RlyDemoGreeting.greet(''), 'Blank name');
        }
    }
}