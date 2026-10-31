/** Looks up accounts by name, for the Release Relay end-to-end run (blocking code scan). */
public with sharing class RlyDemoSearch {
    public static List<Account> byName(String name) {
        return Database.query('SELECT Id, Name FROM Account WHERE Name = \'' + name + '\' LIMIT 10');
    }
}