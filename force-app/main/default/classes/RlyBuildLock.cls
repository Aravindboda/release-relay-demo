/**
 * @description What's built lock (build 31): an optional password in front of the What's built tab. Admins turn it on
 * and set the password on the Pipeline tab; everyone (admins too) types it once and stays unlocked for 8 hours, until
 * they lock it again or an admin changes the lock. Only a salted SHA-256 hash (4,096 rounds) is kept in the protected
 * hierarchy custom setting RLY_Lock__c (org default row); the password is never stored or logged. Wrong tries are
 * counted per user on the server: 5 wrong tries lock the user out for 15 minutes. RlyBuildInfo calls requireUnlocked()
 * before it returns anything.
 */
public with sharing class RlyBuildLock {

    private static final Integer MAX_TRIES = 5;
    private static final Integer LOCK_MINUTES = 15;
    private static final Integer UNLOCK_HOURS = 8;
    private static final Integer ROUNDS = 4096;
    private static final Integer MIN_LENGTH = 8;
    private static final Integer SALT_BITS = 128;
    private static final Integer OUT_ROW_CAP = 200;
    private static final String DIGEST = 'SHA-256';
    /** @description What requireUnlocked() throws while the tab is locked for this user. */
    @TestVisible
    private static final String LOCKED_MESSAGE = 'What\'s built is locked.';
    /** @description unlock(): the password was right (or the lock is off). */
    @TestVisible
    private static final String RESULT_OK = 'ok';
    /** @description unlock(): the password was wrong; tries are left. */
    @TestVisible
    private static final String RESULT_WRONG = 'wrong';
    /** @description unlock(): too many wrong tries; wait until lockedUntil. */
    @TestVisible
    private static final String RESULT_LOCKED_OUT = 'lockedOut';

    /** @description What the What's built tab and the Pipeline tab's lock section show. */
    public class Status {
        /** @description The tab needs the password. */
        @AuraEnabled public Boolean enabled = false;
        /** @description This user may read What's built now (the lock is off, or they unlocked it). */
        @AuraEnabled public Boolean unlocked = false;
        /** @description This user may change the lock (a Release Relay admin). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description A password is set (its hash is kept). */
        @AuraEnabled public Boolean passwordSet = false;
        /** @description Wrong tries this user has left before the lock-out. */
        @AuraEnabled public Integer triesLeft;
        /** @description This user is locked out until then (null when not locked out). */
        @AuraEnabled public Datetime lockedUntil;
        /** @description This user's unlock lasts until then (null when not unlocked). */
        @AuraEnabled public Datetime unlockedUntil;
        /** @description When an admin last changed the lock. */
        @AuraEnabled public Datetime changedOn;
        /** @description Who last changed the lock. */
        @AuraEnabled public String changedBy;
        /** @description Admins only: users locked out right now. */
        @AuraEnabled public Integer lockedOutUsers;
        /** @description Admins only: the latest lock-out end among them. */
        @AuraEnabled public Datetime lockedOutUntil;
        /** @description unlock(): ok, wrong or lockedOut; blank for the other calls. */
        @AuraEnabled public String result;
    }

    /**
     * @description The lock as this user sees it.
     * @return the status
     */
    @AuraEnabled(cacheable=false)
    public static Status status() {
        Store store = new Store();
        return statusOf(store, store.orgRow(), store.userRow());
    }

    /**
     * @description Checks the password. Right: unlocked for 8 hours, wrong tries reset. Wrong: one try used; the fifth
     * wrong try locks this user out for 15 minutes. While locked out no password is checked.
     * @param password what the user typed (never stored or logged)
     * @return the status, with result ok, wrong or lockedOut
     */
    @AuraEnabled(cacheable=false)
    public static Status unlock(String password) {
        Store store = new Store();
        RLY_Lock__c org = store.orgRow();
        RLY_Lock__c mine = store.userRow();
        String result = RESULT_OK;
        if (org.Enabled__c == true) {
            result = new Rules(System.now()).tryPassword(org, mine, password);
            store.save(mine);
        }
        Status s = statusOf(store, org, mine);
        s.result = result;
        return s;
    }

    /**
     * @description Ends this user's unlock (the tab asks for the password again).
     * @return the status
     */
    @AuraEnabled(cacheable=false)
    public static Status lockAgain() {
        Store store = new Store();
        RLY_Lock__c mine = store.userRow();
        if (mine.Unlocked_Until__c != null) {
            mine.Unlocked_Until__c = null;
            store.save(mine);
        }
        return statusOf(store, store.orgRow(), mine);
    }

    /**
     * @description Admins only: turns the lock on or off and sets a new password. On with a blank password keeps the
     * current one (when there is one); off clears the hash. Every save ends everyone's current unlock.
     * @param enabled the tab needs the password
     * @param password the new password (at least 8 characters), or blank to keep the current one
     * @return the status
     */
    @AuraEnabled(cacheable=false)
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters') // the lock section sends its toggle as a Boolean (page contract)
    public static Status setPassword(Boolean enabled, String password) {
        if (!RlyOrgController.isAdmin()) {
            throw failure('Only Release Relay admins can change the What\'s built lock.');
        }
        Store store = new Store();
        RLY_Lock__c org = store.orgRow();
        Boolean turnOn = enabled == true;
        if (turnOn) {
            setOn(org, password);
        } else {
            org.Hash__c = null;
            org.Salt__c = null;
        }
        org.Enabled__c = turnOn;
        org.Changed_On__c = System.now();
        org.Changed_By__c = UserInfo.getName();
        org.Changed_By_Id__c = UserInfo.getUserId();
        store.save(org);
        return statusOf(store, org, store.userRow());
    }

    /**
     * @description Turning the lock on: a typed password (at least 8 characters) gets a new salt and hash; a blank one
     * keeps the current hash, if there is one.
     * @param org the org default row (saved by the caller)
     * @param password the new password, or blank
     */
    private static void setOn(RLY_Lock__c org, String password) {
        Boolean typed = String.isNotEmpty(password);
        if (typed && password.length() < MIN_LENGTH) {
            throw failure('Use at least ' + MIN_LENGTH + ' characters.');
        }
        if (!typed && String.isBlank(org.Hash__c)) {
            throw failure('Set a password of at least ' + MIN_LENGTH + ' characters to turn the lock on.');
        }
        if (typed) {
            org.Salt__c = EncodingUtil.base64Encode(Crypto.generateAesKey(SALT_BITS));
            org.Hash__c = new Rules(System.now()).hashOf(password, org.Salt__c);
        }
    }

    /**
     * @description Throws "What's built is locked." when the lock is on and this user hasn't unlocked it. RlyBuildInfo
     * calls it before returning anything.
     */
    public static void requireUnlocked() {
        Store store = new Store();
        if (!new Rules(System.now()).isUnlocked(store.orgRow(), store.userRow())) {
            throw failure(LOCKED_MESSAGE);
        }
    }

    /**
     * @description The status from the two rows; admins also get who is locked out now.
     * @param store where the rows live
     * @param org the org default row
     * @param mine this user's row
     * @return the status
     */
    private static Status statusOf(Store store, RLY_Lock__c org, RLY_Lock__c mine) {
        Datetime now = System.now();
        Status s = new Rules(now).status(org, mine);
        s.canEdit = RlyOrgController.isAdmin();
        if (s.canEdit) {
            List<RLY_Lock__c> out = store.lockedOut(now);
            s.lockedOutUsers = out.size();
            for (RLY_Lock__c r : out) {
                if (s.lockedOutUntil == null || r.Locked_Until__c > s.lockedOutUntil) {
                    s.lockedOutUntil = r.Locked_Until__c;
                }
            }
        }
        return s;
    }

    /**
     * @description An AuraHandledException whose message reaches the page (and tests).
     * @param message the message
     * @return the exception
     */
    private static AuraHandledException failure(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /** @description The lock's rules at one moment: tries, lock-out, unlock window, hashing. No reads or writes. */
    @TestVisible
    private class Rules {

        private final Datetime now;

        /**
         * @description Rules checked against this time.
         * @param now the time
         */
        public Rules(Datetime now) {
            this.now = now;
        }

        /**
         * @description One unlock try against the stored hash; updates this user's row (saved by the caller).
         * @param org the org default row
         * @param mine this user's row
         * @param password what the user typed
         * @return ok, wrong or lockedOut
         */
        public String tryPassword(RLY_Lock__c org, RLY_Lock__c mine, String password) {
            if (lockedOut(mine)) {
                return RESULT_LOCKED_OUT;
            }
            if (mine.Locked_Until__c != null) {
                // the wait is over: a fresh set of tries
                mine.Locked_Until__c = null;
                mine.Failed_Tries__c = 0;
            }
            if (matches(org, password)) {
                mine.Failed_Tries__c = 0;
                mine.Unlocked_Until__c = now.addHours(UNLOCK_HOURS);
                return RESULT_OK;
            }
            mine.Failed_Tries__c = triesUsed(mine) + 1;
            if (mine.Failed_Tries__c >= MAX_TRIES) {
                mine.Locked_Until__c = now.addMinutes(LOCK_MINUTES);
                return RESULT_LOCKED_OUT;
            }
            return RESULT_WRONG;
        }

        /**
         * @description The typed password gives the stored hash.
         * @param org the org default row
         * @param password what the user typed
         * @return true when it matches
         */
        private Boolean matches(RLY_Lock__c org, String password) {
            if (String.isEmpty(password) || String.isBlank(org.Hash__c)) {
                return false;
            }
            return sameText(hashOf(password, org.Salt__c), org.Hash__c);
        }

        /**
         * @description What this user sees of the lock (canEdit and the lock-out count are added by the caller).
         * @param org the org default row
         * @param mine this user's row
         * @return the status
         */
        public Status status(RLY_Lock__c org, RLY_Lock__c mine) {
            Status s = new Status();
            s.enabled = org.Enabled__c == true;
            s.passwordSet = String.isNotBlank(org.Hash__c);
            s.unlocked = isUnlocked(org, mine);
            s.changedOn = org.Changed_On__c;
            s.changedBy = org.Changed_By__c;
            Boolean waiting = lockedOut(mine);
            s.lockedUntil = waiting ? mine.Locked_Until__c : null;
            s.triesLeft = waiting ? 0 : MAX_TRIES - (mine.Locked_Until__c == null ? triesUsed(mine) : 0);
            s.unlockedUntil = s.enabled && s.unlocked ? mine.Unlocked_Until__c : null;
            return s;
        }

        /**
         * @description The user is waiting out a lock-out.
         * @param mine this user's row
         * @return true while locked out
         */
        private Boolean lockedOut(RLY_Lock__c mine) {
            return mine.Locked_Until__c != null && mine.Locked_Until__c > now;
        }

        /**
         * @description The user may read What's built: the lock is off, or they unlocked it after the lock last
         * changed and the 8 hours haven't passed.
         * @param org the org default row
         * @param mine this user's row (may be null)
         * @return true when unlocked
         */
        public Boolean isUnlocked(RLY_Lock__c org, RLY_Lock__c mine) {
            if (org.Enabled__c != true) {
                return true;
            }
            Datetime openUntil = mine == null ? null : mine.Unlocked_Until__c;
            if (openUntil == null || openUntil <= now) {
                return false;
            }
            // a second of slack: stored date-times can lose their milliseconds
            return org.Changed_On__c == null || openUntil.addHours(-UNLOCK_HOURS).addSeconds(1) >= org.Changed_On__c;
        }

        /**
         * @description Wrong tries used so far.
         * @param mine this user's row
         * @return the count (0 when blank)
         */
        private Integer triesUsed(RLY_Lock__c mine) {
            return mine.Failed_Tries__c == null ? 0 : mine.Failed_Tries__c.intValue();
        }

        /**
         * @description Salted SHA-256, the digest fed back with the salt 4,096 times in all.
         * @param password the password
         * @param salt the salt (Base64)
         * @return the hash as 64 hex characters
         */
        public String hashOf(String password, String salt) {
            String saltText = salt == null ? '' : salt;
            Blob d = Crypto.generateDigest(DIGEST, Blob.valueOf(saltText + password));
            for (Integer i = 1; i < ROUNDS; i++) {
                d = Crypto.generateDigest(DIGEST, Blob.valueOf(EncodingUtil.convertToHex(d) + saltText));
            }
            return EncodingUtil.convertToHex(d);
        }

        /**
         * @description Compares two hashes in constant time (every character is looked at, whatever differs first).
         * @param a one hash
         * @param b the other
         * @return true when equal
         */
        public Boolean sameText(String a, String b) {
            if (a == null || b == null || a.length() != b.length()) {
                return false;
            }
            Integer diff = 0;
            for (Integer i = 0; i < a.length(); i++) {
                diff = diff | (a.charAt(i) ^ b.charAt(i));
            }
            return diff == 0;
        }
    }

    /** @description RLY_Lock__c is a protected setting the users can't read or write themselves: system mode. */
    private without sharing class Store {

        /**
         * @description The org default row (a blank one when none is saved yet).
         * @return the row
         */
        public RLY_Lock__c orgRow() {
            RLY_Lock__c row = RLY_Lock__c.getOrgDefaults();
            if (row == null) {
                row = new RLY_Lock__c();
            }
            if (row.Id == null) {
                row.SetupOwnerId = UserInfo.getOrganizationId();
            }
            return row;
        }

        /**
         * @description This user's own row (never merged with the org default; a blank one when none is saved yet).
         * @return the row
         */
        public RLY_Lock__c userRow() {
            RLY_Lock__c row = RLY_Lock__c.getValues(UserInfo.getUserId());
            if (row == null || row.SetupOwnerId != UserInfo.getUserId()) {
                row = new RLY_Lock__c(SetupOwnerId = UserInfo.getUserId());
            }
            return row;
        }

        /**
         * @description User rows locked out right now.
         * @param now the time
         * @return the rows
         */
        public List<RLY_Lock__c> lockedOut(Datetime now) {
            return [SELECT Id, Locked_Until__c FROM RLY_Lock__c WHERE Locked_Until__c > :now
                    WITH SYSTEM_MODE LIMIT :OUT_ROW_CAP];
        }

        /**
         * @description Saves a row.
         * @param row the row
         */
        public void save(RLY_Lock__c row) {
            if (row.Id == null) {
                Database.insert(row, true, AccessLevel.SYSTEM_MODE);
            } else {
                Database.update(row, true, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
