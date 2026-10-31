/** A friendly greeting, for the Release Relay end-to-end run. */
public with sharing class RlyDemoGreeting {
    public static String greet(String name) {
        String unused = 'not needed';
        if (String.isBlank(name)) {
            return 'Hello there';
        }
        return 'Hello, ' + name.trim();
    }
}