/**
 * @description The saves of one match pass (RlySlackMatch), worked out after its callouts. A link set by the approver
 * (Self) or an admin (Admin) is never overwritten: a different Slack ID for them is noted as "Changed in Slack". A Slack
 * ID held by a deactivated user moves to the approver (the holder is cleared first, so the unique field allows it); one
 * held by an active user is noted. A save the unique field refuses becomes a note naming who holds the ID.
 */
public with sharing class RlySlackMatchPlan {

    private RlySlackMatch.Pass out;
    private String how;
    private List<RlySlackMatch.Step> steps;
    private Map<String, User> holders = new Map<String, User>();
    private List<User> freeFirst = new List<User>();
    private List<User> rows = new List<User>();
    private Set<String> taken = new Set<String>();
    private Map<Id, User> linking = new Map<Id, User>();

    /**
     * @description A plan for a pass's lookups.
     * @param out the pass result, counted here
     * @param how SSO or Email (saved as Linked by)
     * @param steps the lookups
     */
    public RlySlackMatchPlan(RlySlackMatch.Pass out, String how, List<RlySlackMatch.Step> steps) {
        this.out = out;
        this.how = how;
        this.steps = steps;
    }

    /**
     * @description Works out and saves the links and notes, and counts them on the pass.
     */
    public void save() {
        holders = RlySlackDirectory.holders(RlySlackLookup.found(out, steps));
        for (RlySlackMatch.Step s : steps) {
            if (s.memberId == null) {
                noteUnlinked(s.u, s.note);
            } else {
                decide(s.u, s.memberId);
            }
        }
        RlySlackDirectory.save(freeFirst);
        RlySlackLookup.refused(out, RlySlackDirectory.save(rows), linking);
    }

    // No Slack ID: a linked approver keeps the link; only one without a link needs attention.
    private void noteUnlinked(User u, String note) {
        if (String.isBlank(u.RLY_Slack_Member_Id__c)) {
            out.notLinked++;
            out.misses.add(RlySlackMatch.miss(u, note));
        }
        keepNote(u, note);
    }

    private void keepNote(User u, String note) {
        if (note != u.RLY_Slack_Match_Note__c) {
            rows.add(new User(Id = u.Id, RLY_Slack_Match_Note__c = note?.left(255)));
        }
    }

    private void decide(User u, String memberId) {
        String current = u.RLY_Slack_Member_Id__c;
        String by = u.RLY_Slack_Linked_By__c;
        if (current != null && current.equalsIgnoreCase(memberId)) {
            same(u);
        } else if (current != null && (by == RlySlackDirectory.BY_SELF || by == RlySlackDirectory.BY_ADMIN)) {
            String note = RlySlackMatch.NOTE_CHANGED + RlySlackMatch.SEP + how + ' finds ' + memberId;
            out.misses.add(RlySlackMatch.miss(u, note));
            keepNote(u, note);
        } else if (usedElsewhere(u, memberId)) {
            noteUnlinked(u, RlySlackMatch.NOTE_USED + RlySlackMatch.SEP + 'by ' + holderName(memberId));
        } else {
            link(u, memberId);
        }
    }

    private String holderName(String memberId) {
        User holder = holders.get(memberId);
        return holder == null ? 'another approver' : holder.Name;
    }

    private void same(User u) {
        out.same++;
        if (u.RLY_Slack_Match_Note__c != null || u.RLY_Slack_Linked_By__c == null) {
            rows.add(new User(Id = u.Id, RLY_Slack_Match_Note__c = null,
                RLY_Slack_Linked_By__c = u.RLY_Slack_Linked_By__c == null ? how : u.RLY_Slack_Linked_By__c));
        }
    }

    private Boolean usedElsewhere(User u, String memberId) {
        User holder = holders.get(memberId);
        return taken.contains(memberId) || (holder != null && holder.Id != u.Id && holder.IsActive);
    }

    private void link(User u, String memberId) {
        User holder = holders.get(memberId);
        User row = RlySlackDirectory.linkRow(u.Id, memberId, how);
        if (holder != null && holder.Id != u.Id) {
            freeFirst.add(RlySlackDirectory.linkRow(holder.Id, null, null));
            row.RLY_Slack_Match_Note__c = (RlySlackMatch.NOTE_MOVED + RlySlackMatch.SEP + holder.Name).left(255);
        }
        rows.add(row);
        linking.put(u.Id, u);
        taken.add(memberId);
        out.changed++;
    }
}
