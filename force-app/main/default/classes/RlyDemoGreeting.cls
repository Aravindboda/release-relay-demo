/** A friendly greeting, for the Release Relay end-to-end run (Slack check). */
public with sharing class RlyDemoGreeting {
    /** Greets by name; a blank name gets a general greeting. */
    public static String greet(String name) {
        return String.isBlank(name) ? 'Welcome, friend!' : 'Hi, ' + name.trim() + '!';
    }
}