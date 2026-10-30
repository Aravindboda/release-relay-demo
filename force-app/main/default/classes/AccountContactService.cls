/**
 * Account and contact helpers for the Release Relay demo.
 * Runs with sharing; the one elevated query lives in the private Data class.
 */
public with sharing class AccountContactService {

    /** Number of contacts on each account. Accounts with none are returned with 0. */
    public static Map<Id, Integer> countContacts(Set<Id> accountIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (accountIds == null || accountIds.isEmpty()) {
            return counts;
        }
        for (Id accountId : accountIds) {
            counts.put(accountId, 0);
        }
        for (AggregateResult row : new Data().contactCounts(accountIds)) {
            counts.put((Id) row.get('AccountId'), (Integer) row.get('total'));
        }
        return counts;
    }

    /** Creates the first contact for an account, named after the account. */
    public static Contact createPrimaryContact(Id accountId, String lastName) {
        if (accountId == null || String.isBlank(lastName)) {
            throw new IllegalArgumentException('An account and a last name are required.');
        }
        if (!Schema.sObjectType.Contact.isCreateable()) {
            throw new NoAccessException();
        }
        Contact c = new Contact(AccountId = accountId, LastName = lastName.trim().left(80));
        insert c;
        return c;
    }

    /** Counting runs across all contacts so totals are right for every user. */
    private without sharing class Data {
        public List<AggregateResult> contactCounts(Set<Id> accountIds) {
            if (!Schema.sObjectType.Contact.isAccessible()) {
                return new List<AggregateResult>();
            }
            return [SELECT AccountId, COUNT(Id) total FROM Contact
                    WHERE AccountId IN :accountIds GROUP BY AccountId];
        }
    }
}