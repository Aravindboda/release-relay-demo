/**
 * @description The words and rules of the Credentials dashboard (build 49): the kinds, the statuses worked out from an
 * expiry date (Expiring at 30 days or less, Critical at 7 or less, Expired), the rows a check builds, and the "how to
 * renew" line per kind. No queries and no callouts.
 */
public with sharing class RlyCredentialRows {

    /** @description Kind: a certificate. */
    public static final String KIND_CERT = 'Certificate';
    /** @description Kind: the Git connection's token. */
    public static final String KIND_GIT = 'Git token';
    /** @description Kind: the Slack app. */
    public static final String KIND_SLACK = 'Slack';
    /** @description Kind: an org's integration user. */
    public static final String KIND_USER = 'Integration user';
    /** @description Kind: the hub's sign-in to an org. */
    public static final String KIND_SIGNIN = 'Org sign-in';

    /** @description Status: fine. */
    public static final String OK = 'OK';
    /** @description Status: 30 days or less. */
    public static final String EXPIRING = 'Expiring';
    /** @description Status: 7 days or less. */
    public static final String CRITICAL = 'Critical';
    /** @description Status: past its expiry. */
    public static final String EXPIRED = 'Expired';
    /** @description Status: the check failed. */
    public static final String FAILED = 'Failed';
    /** @description Status: it can't be read. */
    public static final String UNKNOWN = 'Unknown';

    /** @description Statuses that need someone (the Home tile lists them). */
    public static final Set<String> ATTENTION = new Set<String>{ EXPIRING, CRITICAL, EXPIRED, FAILED };
    /** @description Statuses that post a Slack alert when an item turns to one of them. */
    public static final Set<String> ALERT = new Set<String>{ CRITICAL, EXPIRED, FAILED };

    private static final Integer EXPIRING_DAYS = 30;
    private static final Integer CRITICAL_DAYS = 7;
    private static final Map<String, Integer> RANK = new Map<String, Integer>{ OK => 0, UNKNOWN => 1, EXPIRING => 2, CRITICAL => 3,
        EXPIRED => 4, FAILED => 5 };

    /** @description The error code of an org that has used its daily API calls (build 52). */
    public static final String API_LIMIT_CODE = 'REQUEST_LIMIT_EXCEEDED';

    /** @description The order rows are listed in: worst first. */
    public static final List<String> WORST_FIRST = new List<String>{ FAILED, EXPIRED, CRITICAL, EXPIRING, UNKNOWN, OK };

    @TestVisible
    private static Date todayForTest;

    /**
     * @description Today, as the dashboard counts (tests set it).
     * @return today
     */
    public static Date today() {
        return todayForTest != null ? todayForTest : Date.today();
    }

    /**
     * @description The status an expiry date gives.
     * @param expires the date, or null for no expiry
     * @return OK, Expiring, Critical or Expired
     */
    public static String statusFor(Date expires) {
        if (expires == null) {
            return OK;
        }
        Integer days = today().daysBetween(expires);
        if (days < 0) {
            return EXPIRED;
        }
        if (days <= CRITICAL_DAYS) {
            return CRITICAL;
        }
        return days <= EXPIRING_DAYS ? EXPIRING : OK;
    }

    /**
     * @description The worse of two statuses.
     * @param a one status
     * @param b another
     * @return the worse one
     */
    public static String worse(String a, String b) {
        Integer ra = RANK.containsKey(a) ? RANK.get(a) : 0;
        Integer rb = RANK.containsKey(b) ? RANK.get(b) : 0;
        return rb > ra ? b : a;
    }

    /**
     * @description A row a check found.
     * @param key the row's unique key
     * @param kind its kind
     * @param name what it is, in words
     * @return the row (Unknown until set; the caller sets Org__c)
     */
    public static RLY_Credential_Status__c row(String key, String kind, String name) {
        return new RLY_Credential_Status__c(Key__c = key.left(120), Kind__c = kind, Name = name == null ? key.left(80) : name.left(80),
            Status__c = UNKNOWN, Last_Checked__c = System.now());
    }

    /**
     * @description A row of a registered org.
     * @param key the row's unique key
     * @param kind its kind
     * @param o the org (Name used as the row's name prefix)
     * @return the row, with Org__c
     */
    public static RLY_Credential_Status__c orgRow(String key, String kind, RLY_Org__c o) {
        RLY_Credential_Status__c r = row(key, kind, o.Name);
        r.Org__c = o.Id;
        return r;
    }

    /**
     * @description Sets the row from an expiry date: its status and a message saying how long is left.
     * @param r the row
     * @param expires the date, or null for no expiry
     * @param noExpiryText the message when there is no expiry
     * @return the row
     */
    public static RLY_Credential_Status__c fromExpiry(RLY_Credential_Status__c r, Date expires, String noExpiryText) {
        r.Expires_On__c = expires;
        r.Status__c = statusFor(expires);
        if (expires == null) {
            r.Message__c = noExpiryText;
        } else {
            Integer days = today().daysBetween(expires);
            r.Message__c = days < 0 ? 'Expired ' + (-days) + (days == -1 ? ' day' : ' days') + ' ago.'
                : 'Expires in ' + days + (days == 1 ? ' day.' : ' days.');
        }
        return r;
    }

    /**
     * @description Marks the row with a status and a message.
     * @param r the row
     * @param status the status
     * @param message the message
     * @return the row
     */
    public static RLY_Credential_Status__c mark(RLY_Credential_Status__c r, String status, String message) {
        r.Status__c = status;
        r.Message__c = message == null ? null : message.left(2000);
        return r;
    }

    /**
     * @description Whether an answer or error says the org has used its daily API calls.
     * @param text the answer's body or the error's message
     * @return true when it carries REQUEST_LIMIT_EXCEEDED
     */
    public static Boolean isApiLimit(String text) {
        return text != null && text.containsIgnoreCase(API_LIMIT_CODE);
    }

    /**
     * @description Marks the row Unknown because the org has used its daily API calls: nothing to renew, the next pass
     * checks it again.
     * @param r the row
     * @param orgName the org, in words (The hub for the hub itself)
     * @return the row
     */
    public static RLY_Credential_Status__c apiLimitReached(RLY_Credential_Status__c r, String orgName) {
        return mark(r, UNKNOWN, orgName + ' has used its daily API calls (' + API_LIMIT_CODE + '); checked again on the next pass.');
    }

    /**
     * @description Copies what a check keeps from the saved row: Last OK, and the time it was last OK when it is OK now.
     * @param fresh the row the check built
     * @param saved the saved row, or null
     */
    public static void carry(RLY_Credential_Status__c fresh, RLY_Credential_Status__c saved) {
        Boolean fine = fresh.Status__c == OK || fresh.Status__c == EXPIRING || fresh.Status__c == CRITICAL;
        fresh.Last_OK__c = fine ? fresh.Last_Checked__c : (saved == null ? null : saved.Last_OK__c);
    }

    /**
     * @description Whether the item just turned to a status that alerts (Critical, Expired or Failed).
     * @param fresh the row the check built
     * @param saved the saved row, or null
     * @return true when it alerts now and didn't have that status before
     */
    public static Boolean turnedBad(RLY_Credential_Status__c fresh, RLY_Credential_Status__c saved) {
        return ALERT.contains(fresh.Status__c) && (saved == null || saved.Status__c != fresh.Status__c);
    }
}
