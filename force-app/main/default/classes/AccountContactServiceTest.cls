@IsTest
private class AccountContactServiceTest {

    /** Runs as the current admin; inserting users in these orgs is slow and unnecessary. */
    private static User admin() {
        return new User(Id = UserInfo.getUserId());
    }

    @IsTest
    static void countsContactsPerAccount() {
        System.runAs(admin()) {
            Account withContacts = new Account(Name = 'Relay Demo One');
            Account empty = new Account(Name = 'Relay Demo Two');
            insert new List<Account>{ withContacts, empty };
            AccountContactService.createPrimaryContact(withContacts.Id, 'Primary');
            AccountContactService.createPrimaryContact(withContacts.Id, 'Second');

            Test.startTest();
            Map<Id, Integer> counts = AccountContactService.countContacts(new Set<Id>{ withContacts.Id, empty.Id });
            Test.stopTest();

            System.assertEquals(2, counts.get(withContacts.Id), 'Two contacts counted');
            System.assertEquals(0, counts.get(empty.Id), 'Account without contacts is 0');
            System.assertEquals(0, AccountContactService.countContacts(null).size(), 'No ids, no counts');
        }
    }

    @IsTest
    static void rejectsMissingValues() {
        System.runAs(admin()) {
            Boolean refused = false;
            try {
                AccountContactService.createPrimaryContact(null, 'Nobody');
            } catch (IllegalArgumentException e) {
                refused = true;
            }
            System.assert(refused, 'An account is required');
        }
    }

    @IsTest
    static void deletedContactIsNotCounted() {
        System.runAs(admin()) {
            Account a = new Account(Name = 'Relay Demo Three');
            insert a;
            Contact c = AccountContactService.createPrimaryContact(a.Id, 'Temp');
            try {
                delete c;
            } catch (DmlException e) {
                System.assert(false, 'Delete failed: ' + e.getMessage());
            }
            System.assertEquals(0, AccountContactService.countContacts(new Set<Id>{ a.Id }).get(a.Id), 'Deleted contact not counted');
        }
    }
}