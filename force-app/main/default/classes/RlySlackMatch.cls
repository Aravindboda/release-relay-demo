/**
 * @description Links approvers to their Slack accounts. The hub's Slack record says how (Slack_Match_By__c): SSO (the
 * default: the user's Federation ID, when it is an email, looked up with users.lookupByEmail), Email (the Salesforce
 * email, only when exactly one approver has it) or Manual (nothing is matched). Matching runs on a button press only, in
 * passes of at most PASS_SIZE lookups (the page loops the passes; no async Apex); callouts first, then RlySlackMatchPlan
 * saves. When Slack says it is busy (HTTP 429) the pass stops and tells the page when to go on. The on-the-spot match
 * for a Slack press is RlySlackPresser; an admin's fixes for one approver are RlySlackFix.
 */
public with sharing class RlySlackMatch {

    /** @description Most Slack lookups in one pass (one Apex call). */
    public static final Integer PASS_SIZE = 50;
    /** @description Match approvers by: nothing automatic. */
    public static final String MANUAL = 'Manual';
    /** @description Note: Slack has no account with the email. */
    public static final String NOTE_NOT_FOUND = 'Not found in Slack';
    /** @description Note: SSO mode and the Federation ID is blank. */
    public static final String NOTE_FED_EMPTY = 'Federation ID empty';
    /** @description Note: SSO mode and the Federation ID has no @. */
    public static final String NOTE_FED_NOT_EMAIL = 'Federation ID isn\'t an email';
    /** @description Note: Email mode and two approvers share the email. */
    public static final String NOTE_SAME_EMAIL = 'Same email on 2 approvers — pick one';
    /** @description Note: the Slack ID Slack found is linked to another active user. */
    public static final String NOTE_USED = 'Slack ID already used';
    /** @description Note: a Self or Admin link differs from what matching finds now. */
    public static final String NOTE_CHANGED = 'Changed in Slack';
    /** @description Note: the Slack ID was taken from a deactivated user. */
    public static final String NOTE_MOVED = 'Moved from deactivated user';
    /** @description Between a note and its detail. */
    public static final String SEP = ' · ';

    /** @description What one pass did. */
    public class Pass {
        /** @description Approvers in the run (every approver, or the ones just added). */
        @AuraEnabled public Integer total = 0;
        /** @description Looked up in Slack in this pass. */
        @AuraEnabled public Integer looked = 0;
        /** @description Already linked to the ID Slack gave. */
        @AuraEnabled public Integer same = 0;
        /** @description Linked now (new or changed). */
        @AuraEnabled public Integer changed = 0;
        /** @description Still not linked after this pass. */
        @AuraEnabled public Integer notLinked = 0;
        /** @description Where the next pass starts, or null when the run is done (or stopped by a problem). */
        @AuraEnabled public Integer nextOffset;
        /** @description Slack is busy: seconds to wait before the next pass (nextOffset says where). */
        @AuraEnabled public Integer retryAfter;
        /** @description Why the run can't go on (missing scope, Slack not set up), or null. */
        @AuraEnabled public String problem;
        /** @description The approvers who need attention after this pass. */
        @AuraEnabled public List<Miss> misses = new List<Miss>();
    }

    /** @description An approver matching couldn't link. */
    public class Miss {
        /** @description The user. */
        @AuraEnabled public Id userId;
        /** @description The user's name. */
        @AuraEnabled public String name;
        /** @description Why (the note). */
        @AuraEnabled public String reason;
    }

    /** @description One approver's lookup. */
    public class Step {
        /** @description The approver. */
        public User u;
        /** @description The member ID Slack gave, or null. */
        public String memberId;
        /** @description Why there is none, or null. */
        public String note;
        /** @description A failure that stops the run, or null. */
        public Exception stop;
    }

    // Where a pass looks: its slice of the run, how, and Email mode's counts.
    private class Slice {
        public String how;
        public Map<String, Integer> emails;
        public Integer start;
        public Integer stop;
    }

    /**
     * @description How approvers are matched (Slack_Match_By__c), SSO when not set.
     * @return SSO, Email or Manual
     */
    public static String matchBy() {
        RLY_Notification__c s = RlySlack.settings();
        return s == null || String.isBlank(s.Slack_Match_By__c) ? RlySlackDirectory.BY_SSO : s.Slack_Match_By__c;
    }

    /**
     * @description Runs one pass: up to PASS_SIZE approvers from offset are looked up in Slack, then saved.
     * @param onlyIds these approvers only (just added), or null for every approver
     * @param offset where this pass starts in the run
     * @return what the pass did
     */
    public static Pass run(List<Id> onlyIds, Integer offset) {
        Pass out = new Pass();
        String how = matchBy();
        if (how == MANUAL) {
            out.problem = 'Matching is manual only.';
            return out;
        }
        List<User> everyone = RlySlackDirectory.approvers();
        List<User> batch = only(everyone, onlyIds);
        out.total = batch.size();
        Integer start = Math.max(0, offset == null ? 0 : offset);
        Integer stop = Math.min(batch.size(), start + PASS_SIZE);
        Slice win = new Slice();
        win.how = how;
        win.emails = RlySlackLookup.emailCounts(everyone, how);
        win.start = start;
        win.stop = stop;
        List<Step> steps = lookups(out, batch, win);
        if (out.retryAfter == null && out.problem == null) {
            out.nextOffset = stop < batch.size() ? stop : null;
        }
        new RlySlackMatchPlan(out, how, steps).save();
        return out;
    }

    // The pass's lookups, from start to stop, until a failure that stops the run.
    private static List<Step> lookups(Pass out, List<User> batch, Slice win) {
        List<Step> steps = new List<Step>();
        for (Integer at = win.start; at < win.stop; at++) {
            Step s = RlySlackLookup.lookup(batch[at], win.how, win.emails);
            if (s.stop != null) {
                stopped(out, s.stop, at);
                break;
            }
            steps.add(s);
        }
        return steps;
    }

    private static List<User> only(List<User> everyone, List<Id> onlyIds) {
        if (onlyIds == null || onlyIds.isEmpty()) {
            return everyone;
        }
        Set<Id> ids = new Set<Id>(onlyIds);
        List<User> out = new List<User>();
        for (User u : everyone) {
            if (ids.contains(u.Id)) {
                out.add(u);
            }
        }
        return out;
    }

    // Busy: go on later from this approver. Anything else that stops the run: say why.
    private static void stopped(Pass out, Exception e, Integer at) {
        if (RlySlackApi.isRateLimited(e)) {
            out.retryAfter = RlySlackApi.retryAfterSeconds();
            out.nextOffset = at;
        } else {
            out.problem = RlySlackLookup.problemText(e);
        }
    }

    /**
     * @description A miss for the result.
     * @param u the approver
     * @param reason why
     * @return the miss
     */
    public static Miss miss(User u, String reason) {
        Miss m = new Miss();
        m.userId = u.Id;
        m.name = u.Name;
        m.reason = reason;
        return m;
    }
}
