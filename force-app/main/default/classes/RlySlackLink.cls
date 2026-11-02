/**
 * @description Self-link: an unlinked approver who presses Approve or Reject in Slack gets a private "Link my account"
 * button. It opens the Link your Slack account tab (lwc rlySlackLink, ?c__t=token) in Salesforce, where the signed-in
 * user confirms; the link is saved on their own user with Linked by Self. The token is memberId.team.expiry.nonce and
 * an HMAC-SHA256 of that, keyed with a key derived from the hub's Slack signing secret (HMAC of a fixed label), so it
 * needs no new secret and is only made where Slack requests are already verified; rotating the signing secret voids
 * open links. It works for 15 minutes. It carries only the Slack ID: it links to whoever is signed in, so the page names
 * both accounts. A Slack ID already linked to someone else is refused (the unique field enforces it too); once linked,
 * the same link does nothing more, so it is single-use in effect.
 */
public with sharing class RlySlackLink {

    /** @description Minutes a link works. */
    public static final Integer MINUTES = 15;
    /** @description The tab the link opens. */
    public static final String TAB = 'RLY_Slack_Link';
    /** @description Page states. */
    public static final String READY = 'ready';
    /** @description The link is malformed or its signature doesn't match. */
    public static final String INVALID = 'invalid';
    /** @description The link is older than MINUTES. */
    public static final String EXPIRED = 'expired';
    /** @description The Slack ID is linked to another user. */
    public static final String TAKEN = 'taken';
    /** @description The signed-in user isn't an approver. */
    public static final String NOT_APPROVER = 'notApprover';
    /** @description The Slack ID is linked to the signed-in user (already, or just now). */
    public static final String LINKED = 'linked';
    /** @description What an unlinked Slack user who isn't an approver is told. */
    public static final String CANT_APPROVE = 'You can\'t approve releases. Ask a ' + System.Label.RLY_App_Name + ' admin.';

    private static final String KEY_LABEL = 'rly-slack-link-v1';
    private static final Pattern MEMBER = Pattern.compile('^[UW][A-Z0-9]{2,19}$');

    /** @description What the Link page shows. */
    public class LinkView {
        /** @description ready, invalid, expired, taken, notApprover or linked. */
        @AuraEnabled public String state;
        /** @description The sentence for the state (not for ready). */
        @AuraEnabled public String message;
        /** @description The Slack member ID in the link. */
        @AuraEnabled public String memberId;
        /** @description When the link stops working. */
        @AuraEnabled public Datetime expiresAt;
        /** @description The Slack account's name, when Slack says. */
        @AuraEnabled public String slackName;
        /** @description The Slack account's email, when Slack says. */
        @AuraEnabled public String slackEmail;
        /** @description The signed-in user's name. */
        @AuraEnabled public String meName;
        /** @description Approver or Admin. */
        @AuraEnabled public String meAccess;
        /** @description The signed-in user's Federation ID, or email when there is none. */
        @AuraEnabled public String meLogin;
        /** @description Slack's email is the user's Federation ID or email. */
        @AuraEnabled public Boolean emailMatches = false;
        /** @description The Slack ID the user is linked to now, when it is another one (linking replaces it). */
        @AuraEnabled public String replaces;
    }

    // A checked token.
    private class Claim {
        public String memberId;
        public Datetime expiresAt;
    }

    /**
     * @description A new link token for a Slack user.
     * @param memberId the Slack member ID
     * @param teamId the Slack workspace ID, or null
     * @param secret the hub's signing secret
     * @return the token
     */
    public static String token(String memberId, String teamId, String secret) {
        Long expires = System.now().addMinutes(MINUTES).getTime() / 1000;
        String nonce = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(12);
        String body = memberId.toUpperCase() + '.' + (String.isBlank(teamId) ? '-' : teamId) + '.' + expires + '.' + nonce;
        return body + '.' + mac(body, secret);
    }

    /**
     * @description The URL of the Link page for a token.
     * @param token the token
     * @param releaseId the release whose button was pressed, or null
     * @return the URL
     */
    public static String url(String token, Id releaseId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/' + TAB + '?c__t=' + EncodingUtil.urlEncode(token, 'UTF-8')
            + (releaseId == null ? '' : '&c__release=' + releaseId);
    }

    @TestVisible
    private static String mac(String body, String secret) {
        Blob key = Crypto.generateMac('hmacSHA256', Blob.valueOf(KEY_LABEL), Blob.valueOf(secret));
        return EncodingUtil.convertToHex(Crypto.generateMac('hmacSHA256', Blob.valueOf(body), key));
    }

    // The claim, when the token is well formed and signed with the hub's secret (expired or not); otherwise null.
    private static Claim check(String token) {
        RLY_Notification__c s = RlySlack.settings();
        String secret = s == null ? null : s.Signing_Secret__c;
        List<String> parts = String.isBlank(token) ? new List<String>() : token.trim().split('\\.');
        if (String.isBlank(secret) || parts.size() != 5 || !MEMBER.matcher(parts[0]).matches() || !parts[2].isNumeric()) {
            return null;
        }
        String body = String.join(new List<String>{ parts[0], parts[1], parts[2], parts[3] }, '.');
        if (!mac(body, secret).equals(parts[4].toLowerCase())) {
            return null;
        }
        Claim c = new Claim();
        c.memberId = parts[0];
        c.expiresAt = Datetime.newInstance(Long.valueOf(parts[2]) * 1000);
        return c;
    }

    /**
     * @description What the Link page shows for a token (asks Slack who the account is; nothing is saved).
     * @param token the token from the link
     * @return the view
     */
    @AuraEnabled
    public static LinkView readLink(String token) {
        LinkView v = view(token);
        if (v.state == READY || v.state == LINKED) {
            try {
                RlySlackPeople.Person p = RlySlackPeople.byId(v.memberId);
                v.slackName = p == null ? null : p.name;
                v.slackEmail = p == null ? null : p.email;
                v.emailMatches = p != null && String.isNotBlank(p.email) && p.email.equalsIgnoreCase(v.meLogin);
            } catch (Exception e) {
                v.slackName = null;
            }
        }
        return v;
    }

    /**
     * @description Links the Slack account in the token to the signed-in user (Linked by Self).
     * @param token the token from the link
     * @return the view, state linked
     */
    @AuraEnabled
    public static LinkView confirmLink(String token) {
        LinkView v = view(token);
        if (v.state != READY) {
            throw RlySlackController.auraError(v.message);
        }
        RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(UserInfo.getUserId(), v.memberId, RlySlackDirectory.BY_SELF));
        v.state = LINKED;
        v.replaces = null;
        v.message = 'Linked. Go back to Slack and press Approve again.';
        return v;
    }

    // The state for the signed-in user, without calling Slack.
    private static LinkView view(String token) {
        LinkView v = new LinkView();
        Claim c = check(token);
        if (c == null) {
            return state(v, INVALID, 'This link isn\'t valid. Press Approve in Slack again for a new one.');
        }
        v.memberId = c.memberId;
        v.expiresAt = c.expiresAt;
        if (c.expiresAt < System.now()) {
            return state(v, EXPIRED, 'This link has expired. Press Approve in Slack again for a new one.');
        }
        RlySlackDirectory.Access access = RlySlackDirectory.accessOf(UserInfo.getUserId());
        if (access == null) {
            return state(v, NOT_APPROVER, CANT_APPROVE);
        }
        v.meAccess = access.admin ? 'Admin' : 'Approver';
        return forMe(v, c);
    }

    // An approver: whether the Slack ID is free, theirs already, or someone else's.
    private static LinkView forMe(LinkView v, Claim c) {
        User me = me();
        v.meName = UserInfo.getName();
        v.meLogin = String.isBlank(me.FederationIdentifier) ? me.Email : me.FederationIdentifier;
        User holder = RlySlackDirectory.linkedUser(c.memberId);
        if (holder != null && holder.Id == me.Id) {
            return state(v, LINKED, 'You\'re already linked to ' + c.memberId + '. Approve and Reject in Slack count as you.');
        }
        if (holder != null) {
            return state(v, TAKEN, c.memberId + ' is linked to someone else. Ask a ' + System.Label.RLY_App_Name + ' admin.');
        }
        v.replaces = String.isBlank(me.RLY_Slack_Member_Id__c) ? null : me.RLY_Slack_Member_Id__c;
        return state(v, READY, null);
    }

    private static LinkView state(LinkView v, String state, String message) {
        v.state = state;
        v.message = message;
        return v;
    }

    private static User me() {
        for (User u : RlySlackDirectory.approvers()) {
            if (u.Id == UserInfo.getUserId()) {
                return u;
            }
        }
        return new User(Id = UserInfo.getUserId(), LastName = UserInfo.getLastName(), Email = UserInfo.getUserEmail());
    }
}
