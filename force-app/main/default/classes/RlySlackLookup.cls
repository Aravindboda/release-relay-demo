/**
 * @description The Slack lookup of one approver for matching (RlySlackMatch): the value looked up (Federation ID for SSO,
 * Salesforce email for Email), why it can't be looked up (blank, not an email, an email two approvers share), and Slack's
 * answer (users.lookupByEmail). Also what the page says when Slack can't be asked, and which failures stop a whole run.
 */
public with sharing class RlySlackLookup {

    /**
     * @description Email mode: how many approvers have each email (lower case); SSO mode: empty.
     * @param everyone every approver
     * @param how SSO or Email
     * @return email to count
     */
    public static Map<String, Integer> emailCounts(List<User> everyone, String how) {
        Map<String, Integer> out = new Map<String, Integer>();
        if (how != RlySlackDirectory.BY_EMAIL) {
            return out;
        }
        for (User u : everyone) {
            String key = u.Email == null ? '' : u.Email.toLowerCase();
            out.put(key, (out.containsKey(key) ? out.get(key) : 0) + 1);
        }
        return out;
    }

    /**
     * @description What the page says when Slack can't be asked.
     * @param e the failure
     * @return the sentence
     */
    public static String problemText(Exception e) {
        if (RlySlackApi.code(e) == 'missing_scope') {
            return RlySlackPeople.missingText(new List<String>{ RlySlackPeople.EMAIL_SCOPE });
        }
        if (RlySlackApi.isNotSetUp(e)) {
            return 'Connect Slack first (Slack connection → Edit).';
        }
        return RlySlackApi.isRateLimited(e) ? RlySlackApi.BUSY_RESULT : ('Slack: ' + e.getMessage()).left(255);
    }

    /**
     * @description Whether a failure stops the whole run (busy, not set up, missing scope), not just one approver.
     * @param e the failure
     * @return true when it does
     */
    public static Boolean stopsRun(Exception e) {
        return RlySlackApi.isRateLimited(e) || RlySlackApi.isNotSetUp(e) || RlySlackApi.code(e) == 'missing_scope';
    }

    /**
     * @description The value an approver is looked up by: the Federation ID (SSO) or the Salesforce email.
     * @param u the approver
     * @param how SSO or Email
     * @return the value, or null
     */
    public static String keyOf(User u, String how) {
        return how == RlySlackDirectory.BY_EMAIL ? u.Email : u.FederationIdentifier;
    }

    /**
     * @description Why an approver can't be looked up: blank or not an email, or an email two approvers share.
     * @param u the approver
     * @param how SSO or Email
     * @param emails Email mode: how many approvers have each email (lower case)
     * @return the note, or null when it can be looked up
     */
    public static String skipReason(User u, String how, Map<String, Integer> emails) {
        String key = keyOf(u, how);
        Boolean byEmail = how == RlySlackDirectory.BY_EMAIL;
        if (String.isBlank(key)) {
            return byEmail ? RlySlackMatch.NOTE_NOT_FOUND : RlySlackMatch.NOTE_FED_EMPTY;
        }
        if (!key.contains('@')) {
            return RlySlackMatch.NOTE_FED_NOT_EMAIL;
        }
        Integer onEmail = emails.get(key.toLowerCase());
        return onEmail != null && onEmail > 1 ? RlySlackMatch.NOTE_SAME_EMAIL : null;
    }

    /**
     * @description One approver: the reason it can't be looked up, or Slack's answer.
     * @param u the approver
     * @param how SSO or Email
     * @param emails Email mode: approvers per email
     * @return the step
     */
    public static RlySlackMatch.Step lookup(User u, String how, Map<String, Integer> emails) {
        RlySlackMatch.Step s = new RlySlackMatch.Step();
        s.u = u;
        s.note = skipReason(u, how, emails);
        if (s.note != null) {
            return s;
        }
        try {
            RlySlackPeople.Person p = RlySlackPeople.byEmail(keyOf(u, how));
            s.memberId = p == null ? null : p.memberId;
            s.note = p == null ? RlySlackMatch.NOTE_NOT_FOUND + RlySlackMatch.SEP + System.now().format('MMM d') : null;
        } catch (Exception e) {
            s.stop = stopsRun(e) ? e : null;
            s.note = s.stop == null ? problemText(e) : null;
        }
        return s;
    }

    /**
     * @description Counts the approvers asked in Slack on the pass and gives the Slack IDs it found.
     * @param out the pass
     * @param steps the lookups
     * @return the Slack IDs found
     */
    public static Set<String> found(RlySlackMatch.Pass out, List<RlySlackMatch.Step> steps) {
        Set<String> ids = new Set<String>();
        for (RlySlackMatch.Step s : steps) {
            Boolean notFound = s.note != null && s.note.startsWith(RlySlackMatch.NOTE_NOT_FOUND + RlySlackMatch.SEP);
            out.looked += s.memberId != null || notFound ? 1 : 0;
            if (s.memberId != null) {
                ids.add(s.memberId);
            }
        }
        return ids;
    }

    /**
     * @description Links the unique field refused on a pass: noted instead ("Slack ID already used by …"), and counted.
     * @param out the pass
     * @param failed user Id to why it wasn't saved
     * @param linking the approvers whose link was being saved, by Id
     */
    public static void refused(RlySlackMatch.Pass out, Map<Id, String> failed, Map<Id, User> linking) {
        List<User> notes = new List<User>();
        for (Id userId : failed.keySet()) {
            User u = linking.get(userId);
            if (u != null) {
                notes.add(new User(Id = userId, RLY_Slack_Match_Note__c = failed.get(userId).left(255)));
                out.changed--;
                out.notLinked += String.isBlank(u.RLY_Slack_Member_Id__c) ? 1 : 0;
                out.misses.add(RlySlackMatch.miss(u, failed.get(userId)));
            }
        }
        RlySlackDirectory.save(notes);
    }
}
