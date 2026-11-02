/**
 * @description Tests for the What's built lock (RlyBuildLock): off by default, admins set and turn off the password,
 * unlock with the right password, wrong tries and the 15-minute lock-out, Lock again, a change by an admin ending earlier
 * unlocks, and the hash helpers. Every test runs through System.runAs: the admin user holds Release Relay Admin, the
 * plain user doesn't.
 */
@IsTest
private class RlyBuildLockTest {

    private static final String PASSWORD = 'relay-lock-31';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    /**
     * @description Whether requireUnlocked() let this user through.
     * @return true when it didn't throw
     */
    private static Boolean passes() {
        try {
            RlyBuildLock.requireUnlocked();
            return true;
        } catch (AuraHandledException e) {
            System.assertEquals(RlyBuildLock.LOCKED_MESSAGE, e.getMessage(), 'Locked message');
            return false;
        }
    }

    @IsTest
    static void offByDefault() {
        System.runAs(RlyTestData.admin()) {
            RlyBuildLock.Status s = RlyBuildLock.status();
            System.assertEquals(false, s.enabled, 'Off until an admin turns it on');
            System.assertEquals(true, s.unlocked, 'Off: open to everyone');
            System.assertEquals(true, s.canEdit, 'Release Relay admin can edit');
            System.assertEquals(false, s.passwordSet, 'No password yet');
            System.assertEquals(0, s.lockedOutUsers, 'Nobody locked out');
            System.assert(passes(), 'Off: requireUnlocked lets everyone through');
            System.assertEquals(RlyBuildLock.RESULT_OK, RlyBuildLock.unlock('anything').result, 'Off: unlock always ok');
            System.assertEquals(true, RlyBuildLock.lockAgain().unlocked, 'Off: Lock again changes nothing');
        }
    }

    @IsTest
    static void setUnlockAndLockAgain() {
        System.runAs(RlyTestData.admin()) {
            RlyBuildLock.Status s = RlyBuildLock.setPassword(true, PASSWORD);
            System.assertEquals(true, s.enabled, 'Lock on');
            System.assertEquals(true, s.passwordSet, 'Hash kept');
            System.assertEquals(false, s.unlocked, 'Admins need the password too');
            System.assertEquals(UserInfo.getName(), s.changedBy, 'Changed by recorded');
            RLY_Lock__c org = RLY_Lock__c.getOrgDefaults();
            System.assertEquals(64, org.Hash__c.length(), 'Hex SHA-256 stored');
            System.assertNotEquals(PASSWORD, org.Hash__c, 'Never the password');
            System.assertEquals(false, passes(), 'Locked until the password is typed');

            s = RlyBuildLock.unlock('wrong-password');
            System.assertEquals(RlyBuildLock.RESULT_WRONG, s.result, 'Wrong password');
            System.assertEquals(4, s.triesLeft, 'One try used');
            s = RlyBuildLock.unlock(PASSWORD);
            System.assertEquals(RlyBuildLock.RESULT_OK, s.result, 'Right password');
            System.assertEquals(true, s.unlocked, 'Unlocked');
            System.assertEquals(5, s.triesLeft, 'Tries reset');
            System.assertNotEquals(null, s.unlockedUntil, 'Unlock ends some time');
            System.assert(passes(), 'Unlocked: requireUnlocked lets this user through');

            s = RlyBuildLock.lockAgain();
            System.assertEquals(false, s.unlocked, 'Locked again');
            System.assertEquals(false, passes(), 'Locked again: requireUnlocked throws');
        }
    }

    @IsTest
    static void lockOutAfterFiveTries() {
        System.runAs(RlyTestData.admin()) {
            RlyBuildLock.setPassword(true, PASSWORD);
            RlyBuildLock.Status s;
            for (Integer i = 0; i < 5; i++) {
                s = RlyBuildLock.unlock('nope-' + i);
            }
            System.assertEquals(RlyBuildLock.RESULT_LOCKED_OUT, s.result, 'Fifth wrong try locks out');
            System.assertEquals(0, s.triesLeft, 'No tries left');
            System.assertNotEquals(null, s.lockedUntil, 'Locked out until a time');
            System.assertEquals(1, s.lockedOutUsers, 'Admins see one user locked out');
            s = RlyBuildLock.unlock(PASSWORD);
            System.assertEquals(RlyBuildLock.RESULT_LOCKED_OUT, s.result, 'No password checked while locked out');
            System.assertEquals(false, s.unlocked, 'Still locked');

            RLY_Lock__c mine = RLY_Lock__c.getValues(UserInfo.getUserId());
            mine.Locked_Until__c = System.now().addMinutes(-1);
            update mine;
            s = RlyBuildLock.status();
            System.assertEquals(null, s.lockedUntil, 'The wait is over');
            s = RlyBuildLock.unlock(PASSWORD);
            System.assertEquals(RlyBuildLock.RESULT_OK, s.result, 'After the wait the right password works');
            System.assertEquals(5, s.triesLeft, 'Tries reset');
        }
    }

    @IsTest
    static void adminRules() {
        System.runAs(RlyTestData.admin()) {
            String message = '';
            try {
                RlyBuildLock.setPassword(true, 'short');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assert(message.contains('8 characters'), 'Fewer than 8 characters refused: ' + message);
            message = '';
            try {
                RlyBuildLock.setPassword(true, '');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assert(message.contains('Set a password'), 'On without any password refused: ' + message);

            RlyBuildLock.setPassword(true, PASSWORD);
            String hash = RLY_Lock__c.getOrgDefaults().Hash__c;
            RlyBuildLock.Status s = RlyBuildLock.setPassword(true, null);
            System.assertEquals(true, s.enabled, 'Still on');
            System.assertEquals(hash, RLY_Lock__c.getOrgDefaults().Hash__c, 'Blank password keeps the current one');

            s = RlyBuildLock.setPassword(false, null);
            System.assertEquals(false, s.enabled, 'Off');
            System.assertEquals(false, s.passwordSet, 'Off clears the hash');
            System.assertEquals(null, RLY_Lock__c.getOrgDefaults().Salt__c, 'Off clears the salt');
            System.assertEquals(true, s.unlocked, 'Off: open');
        }
    }

    @IsTest
    static void onlyAdminsChangeIt() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            String message = '';
            try {
                RlyBuildLock.setPassword(true, PASSWORD);
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assert(message.contains('Only Release Relay admins'), 'Non-admin refused: ' + message);
            RlyBuildLock.Status s = RlyBuildLock.status();
            System.assertEquals(false, s.canEdit, 'Non-admin reads only');
            System.assertEquals(null, s.lockedOutUsers, 'Lock-out count is for admins only');
        }
    }

    @IsTest
    static void changeEndsEarlierUnlocks() {
        System.runAs(RlyTestData.admin()) {
            Datetime now = System.now();
            RLY_Lock__c org = new RLY_Lock__c(Enabled__c = true, Changed_On__c = now);
            RLY_Lock__c mine = new RLY_Lock__c(Unlocked_Until__c = now.addHours(7));
            System.assertEquals(false, new RlyBuildLock.Rules(now).isUnlocked(org, mine), 'Unlocked before the change: locked again');
            mine.Unlocked_Until__c = now.addHours(8);
            System.assertEquals(true, new RlyBuildLock.Rules(now).isUnlocked(org, mine), 'Unlocked after the change');
            System.assertEquals(false, new RlyBuildLock.Rules(now.addHours(9)).isUnlocked(org, mine), '8 hours passed');
            System.assertEquals(false, new RlyBuildLock.Rules(now).isUnlocked(org, null), 'No row: locked');
            org.Enabled__c = false;
            System.assertEquals(true, new RlyBuildLock.Rules(now).isUnlocked(org, null), 'Off: open');
        }
    }

    @IsTest
    static void hashHelpers() {
        System.runAs(RlyTestData.admin()) {
            RlyBuildLock.Rules rules = new RlyBuildLock.Rules(System.now());
            String a = rules.hashOf(PASSWORD, 'c2FsdA==');
            System.assertEquals(a, rules.hashOf(PASSWORD, 'c2FsdA=='), 'Same input, same hash');
            System.assertNotEquals(a, rules.hashOf(PASSWORD, 'b3RoZXI='), 'Another salt, another hash');
            System.assertEquals(64, rules.hashOf('x', null).length(), 'No salt still hashes');
            System.assert(rules.sameText(a, a), 'Equal hashes match');
            System.assert(!rules.sameText(a, a.substring(1) + '0'), 'Different hashes do not');
            System.assert(!rules.sameText(a, 'abc'), 'Different lengths do not');
            System.assert(!rules.sameText(null, a), 'Null does not');
        }
    }
}
