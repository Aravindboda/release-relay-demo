/**
 * Release Relay demo: a small class to raise from DEV to SIT.
 */
public with sharing class RelayDemoGreeting {
    public static String greet(String name) {
        return 'Hello, ' + (String.isBlank(name) ? 'Release Relay' : name) + '!';

    }
}