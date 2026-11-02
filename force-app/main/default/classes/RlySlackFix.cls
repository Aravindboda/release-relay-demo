/**
 * @description An admin's fixes for one approver on the Approvers window: Set ID by hand (Slack is asked who it is with
 * users.info before it is saved), move (take the Slack ID from the other user), pick (the approver of two sharing an
 * email), use (what matching finds now, over a Self or Admin link) and keep (drop the note). Lookups first, saves last.
 * The admin check is the caller's (RlySlackApprovers).
 */
public with sharing class RlySlackFix {

    /** @description Row fix: move the link from the other user here. */
    public static final String MOVE = 'move';
    /** @description Row fix: link this one of the approvers who share an email. */
    public static final String PICK = 'pick';
    /** @description Row fix: take what matching finds now over a Self or Admin link. */
    public static final String USE = 'use';
    /** @description Row fix: keep the Self or Admin link and drop the note. */
    public static final String KEEP = 'keep';
    /** @description Every fix. */
    public static final Set<String> FIXES = new Set<String>{ MOVE, PICK, USE, KEEP };

    /**
     * @description Applies a row fix.
     * @param userId the approver
     * @param fix move, pick, use or keep
     * @return what was done
     */
    public static String fix(Id userId, String fix) {
        User u = approver(userId);
        if (fix == KEEP) {
            RlySlackDirectory.saveOne(new User(Id = u.Id, RLY_Slack_Match_Note__c = null));
            return 'Kept ' + u.RLY_Slack_Member_Id__c + ' for ' + u.Name + '.';
        }
        String how = fix == PICK ? RlySlackDirectory.BY_EMAIL : RlySlackMatch.matchBy();
        RlySlackPeople.Person p = find(u, how);
        User holder = RlySlackDirectory.linkedUser(p.memberId);
        Boolean elsewhere = holder != null && holder.Id != u.Id;
        if (elsewhere && fix != MOVE) {
            throw RlySlackController.auraError(p.memberId + ' is already linked to ' + holder.Name + '. Unlink it there first.');
        }
        if (elsewhere) {
            User cleared = RlySlackDirectory.linkRow(holder.Id, null, null);
            cleared.RLY_Slack_Match_Note__c = ('Link moved to ' + u.Name).left(255);
            RlySlackDirectory.saveOne(cleared);
        }
        RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(u.Id, p.memberId, fix == USE ? how : RlySlackDirectory.BY_ADMIN));
        return 'Linked ' + u.Name + ' to ' + p.memberId + (elsewhere ? ' (moved from ' + holder.Name + ').' : '.');
    }

    // The Slack account for the approver's Federation ID (or email); refused when there is nothing to look up or no account.
    private static RlySlackPeople.Person find(User u, String how) {
        String key = RlySlackLookup.keyOf(u, how);
        if (how == RlySlackMatch.MANUAL || String.isBlank(key) || !key.contains('@')) {
            throw RlySlackController.auraError('Nothing to look up for ' + u.Name + ': set the ID by hand.');
        }
        RlySlackPeople.Person p;
        try {
            p = RlySlackPeople.byEmail(key);
        } catch (Exception e) {
            throw RlySlackController.auraError(RlySlackLookup.problemText(e));
        }
        if (p == null) {
            throw RlySlackController.auraError('Slack has no account with ' + key + '.');
        }
        return p;
    }

    /**
     * @description Set ID by hand: an ID Slack doesn't know is refused; one another active user holds is refused; one a
     * deactivated user holds moves. When Slack can't be asked, the ID is saved and the message says it wasn't confirmed.
     * @param userId the approver
     * @param memberId the Slack member ID typed
     * @return what Slack said and what was saved
     */
    public static String setByHand(Id userId, String memberId) {
        if (String.isBlank(memberId)) {
            throw RlySlackController.auraError('Member IDs start with U or W.');
        }
        String value = RlySlackRules.memberId(memberId);
        User u = approver(userId);
        String said = ask(value);
        User holder = RlySlackDirectory.holders(new Set<String>{ value }).get(value);
        Boolean elsewhere = holder != null && holder.Id != u.Id;
        if (elsewhere && holder.IsActive) {
            throw RlySlackController.auraError(value + ' is already linked to ' + holder.Name + '. Unlink it there first.');
        }
        if (elsewhere) {
            RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(holder.Id, null, null));
        }
        RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(u.Id, value, RlySlackDirectory.BY_ADMIN));
        return said + 'Linked to ' + u.Name + ' (Linked by Admin).';
    }

    // users.info: who the ID is, or that Slack couldn't be asked; an ID Slack doesn't know is refused.
    private static String ask(String value) {
        RlySlackPeople.Person p;
        try {
            p = RlySlackPeople.byId(value);
        } catch (RlySlackApi.SlackException e) {
            return 'Slack couldn\'t confirm ' + value + ' (' + RlySlackLookup.problemText(e) + '). ';
        }
        if (p == null) {
            throw RlySlackController.auraError('Slack has no member ' + value + '.');
        }
        return 'Slack says ' + value + ' is ' + p.name + (String.isBlank(p.email) ? '' : RlySlackMatch.SEP + p.email) + '. ';
    }

    /**
     * @description Links (or, with null, unlinks) a user by hand without asking Slack (the older Pipeline call).
     * @param userId the user
     * @param value the checked member ID, or null
     */
    public static void link(Id userId, String value) {
        User other = value == null ? null : RlySlackDirectory.linkedUser(value);
        if (other != null && other.Id != userId) {
            throw RlySlackController.auraError(value + ' is already linked to ' + other.Name + '.');
        }
        RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(userId, value, RlySlackDirectory.BY_ADMIN));
    }

    /**
     * @description An active approver, with the Slack link fields.
     * @param userId the user
     * @return the user
     */
    public static User approver(Id userId) {
        for (User u : RlySlackDirectory.approvers()) {
            if (u.Id == userId) {
                return u;
            }
        }
        throw RlySlackController.auraError('That person isn\'t an active approver any more. Refresh the list.');
    }
}
