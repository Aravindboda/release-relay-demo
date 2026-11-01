/**
 * @description Keeps each registered org's access token between transactions, so the hub doesn't sign in to an org
 * (a JWT exchange) on every page read. The token lives in Platform Cache, org cache partition local.RlyTokens, for
 * TTL_SECONDS (well under the session timeout), under a key made from the org record's Id, My Domain and username.
 * When the partition is missing, has no capacity, or refuses a value, nothing is kept and RlyOrgSession signs in once
 * per transaction as before. Within a transaction each org's token is also held in memory. A token taken from the cache
 * that an org refuses as expired (refused) is dropped once, so RlyOrgSession signs in again and retries one time.
 * The token is only ever held here: never in a record, a log or an error message.
 */
public with sharing class RlyTokenCache {

    /** @description The org cache partition the tokens live in. */
    public static final String PARTITION = 'local.RlyTokens';
    /** @description How long a token is kept: 15 minutes. */
    public static final Integer TTL_SECONDS = 900;

    private static final String KEY_PREFIX = 'tok';
    private static final Integer KEY_HASH_CHARS = 40;
    private static final String SESSION_ERROR = 'INVALID_SESSION_ID';

    // One token per org for this transaction, by My Domain and username.
    private static final Map<String, String> HELD = new Map<String, String>();
    // The orgs whose held token came from the cache (only such a token is dropped when refused).
    private static final Set<String> REUSED = new Set<String>();

    // The store in force; resolved on first use (tests set their own).
    @TestVisible private static Store active;

    /** @description Where tokens are kept: get, keep and drop by key. */
    public interface Store {
        /**
         * @description The token kept under a key.
         * @param key the cache key
         * @return the token, or null
         */
        String fetch(String key);
        /**
         * @description Keeps a token under a key for TTL_SECONDS.
         * @param key the cache key
         * @param token the token
         */
        void keep(String key, String token);
        /**
         * @description Forgets the token under a key.
         * @param key the cache key
         */
        void drop(String key);
    }

    /** @description The org cache partition; every failure (no partition, no capacity) reads as nothing kept. */
    public class OrgStore implements Store {
        private Cache.OrgPartition part;

        /**
         * @description A store on a partition; a partition that doesn't exist keeps nothing.
         * @param partitionName for example local.RlyTokens
         */
        public OrgStore(String partitionName) {
            try {
                part = Cache.Org.getPartition(partitionName);
            } catch (Exception e) {
                part = null;
            }
        }

        /**
         * @description The token kept under a key.
         * @param key the cache key
         * @return the token, or null
         */
        public String fetch(String key) {
            try {
                return part == null ? null : (String) part.get(key);
            } catch (Exception e) {
                return null;
            }
        }

        /**
         * @description Keeps a token under a key for TTL_SECONDS (nothing when the partition has no room).
         * @param key the cache key
         * @param token the token
         */
        public void keep(String key, String token) {
            try {
                if (part != null) {
                    part.put(key, token, TTL_SECONDS);
                }
            } catch (Exception e) {
                part = null;
            }
        }

        /**
         * @description Forgets the token under a key.
         * @param key the cache key
         */
        public void drop(String key) {
            try {
                if (part != null) {
                    part.remove(key);
                }
            } catch (Exception e) {
                part = null;
            }
        }
    }

    /** @description A store in memory, for this transaction only (the tests' stand-in for the org cache). */
    public class MemoryStore implements Store {
        private Map<String, String> kept = new Map<String, String>();

        /**
         * @description The token kept under a key.
         * @param key the cache key
         * @return the token, or null
         */
        public String fetch(String key) {
            return kept.get(key);
        }

        /**
         * @description Keeps a token under a key.
         * @param key the cache key
         * @param token the token
         */
        public void keep(String key, String token) {
            kept.put(key, token);
        }

        /**
         * @description Forgets the token under a key.
         * @param key the cache key
         */
        public void drop(String key) {
            kept.remove(key);
        }
    }

    /**
     * @description The cache key of an org's token: the org record's Id with a hash of its My Domain and username
     * (cache keys are letters and digits, at most 50).
     * @param org the registered org
     * @return the key, or null for an org that isn't saved (its token isn't kept)
     */
    public static String keyOf(RLY_Org__c org) {
        if (org == null || org.Id == null || String.isBlank(org.Username__c)) {
            return null;
        }
        String seed = org.Id + '|' + RlyOrgSession.baseUrl(org) + '|' + org.Username__c.trim();
        return KEY_PREFIX + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).left(KEY_HASH_CHARS);
    }

    /**
     * @description The org's kept token.
     * @param org the registered org
     * @return the token, or null when none is kept
     */
    public static String fetch(RLY_Org__c org) {
        String key = keyOf(org);
        return key == null ? null : store().fetch(key);
    }

    /**
     * @description Keeps the org's token for TTL_SECONDS.
     * @param org the registered org
     * @param token the token
     */
    public static void keep(RLY_Org__c org, String token) {
        String key = keyOf(org);
        if (key != null && String.isNotBlank(token)) {
            store().keep(key, token);
        }
    }

    /**
     * @description Forgets the org's token (it was refused: expired or revoked).
     * @param org the registered org
     */
    public static void evict(RLY_Org__c org) {
        String key = keyOf(org);
        if (key != null) {
            store().drop(key);
        }
    }

    /**
     * @description The org's token for this transaction: the one held already, else the one kept in the cache.
     * @param org the registered org
     * @return the token, or null when the hub must sign in
     */
    public static String current(RLY_Org__c org) {
        String slot = heldKey(org);
        if (HELD.containsKey(slot)) {
            return HELD.get(slot);
        }
        String kept = fetch(org);
        if (String.isBlank(kept)) {
            return null;
        }
        REUSED.add(slot);
        HELD.put(slot, kept);
        return kept;
    }

    /**
     * @description Holds a new token for this transaction and keeps it in the cache.
     * @param org the registered org
     * @param token the token from the sign-in
     */
    public static void remember(RLY_Org__c org, String token) {
        HELD.put(heldKey(org), token);
        keep(org, token);
    }

    /**
     * @description Whether the org refused a token taken from the cache as expired (HTTP 401, or INVALID_SESSION_ID).
     * The first time it does, the token is dropped (held and kept) so the caller signs in again and retries once.
     * @param org the registered org
     * @param res the org's answer
     * @return true when the caller should sign in again and retry
     */
    public static Boolean refused(RLY_Org__c org, HttpResponse res) {
        Integer status = res.getStatusCode();
        Boolean expired = status == 401 || (status == 500 && String.valueOf(res.getBody()).contains(SESSION_ERROR));
        String slot = heldKey(org);
        if (!expired || !REUSED.remove(slot)) {
            return false;
        }
        HELD.remove(slot);
        evict(org);
        return true;
    }

    private static String heldKey(RLY_Org__c org) {
        return RlyOrgSession.baseUrl(org) + '|' + org.Username__c;
    }

    // The org cache partition; in tests a store in memory unless the test sets one, so tests never share tokens.
    private static Store store() {
        if (active == null) {
            active = Test.isRunningTest() ? (Store) new MemoryStore() : (Store) new OrgStore(PARTITION);
        }
        return active;
    }
}
