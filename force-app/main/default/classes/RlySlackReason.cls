/**
 * @description What needs attention for one approver on the Approvers window, worked out from the link, the note the
 * last match left (RLY_Slack_Match_Note__c) and the match setting: not found in Slack, Federation ID empty or not an
 * email, same email on two approvers (Email mode), Slack ID already used, changed in Slack (a Self or Admin link that
 * differs from what matching finds), or simply not linked yet.
 */
public with sharing class RlySlackReason {

    /** @description Reason code: a Self or Admin link differs from what matching finds now. */
    public static final String CHANGED = 'changed';

    private String how;

    /**
     * @description Reasons for a match setting.
     * @param how SSO, Email or Manual
     */
    public RlySlackReason(String how) {
        this.how = how;
    }

    /**
     * @description Marks the row with what needs attention (nothing for a linked approver without a Changed note).
     * @param r the row (memberId filled)
     * @param u the approver
     */
    public void mark(RlySlackApproverRows.Row r, User u) {
        String note = noteOf(u);
        if (r.memberId == null) {
            unlinked(r, u);
        } else if (note.startsWith(RlySlackMatch.NOTE_CHANGED)) {
            r.needs(CHANGED, RlySlackMatch.NOTE_CHANGED, detailOf(note));
        }
    }

    private static String noteOf(User u) {
        return u.RLY_Slack_Match_Note__c == null ? '' : u.RLY_Slack_Match_Note__c;
    }

    private static String detailOf(String note) {
        return note.contains(RlySlackMatch.SEP) ? note.substringAfter(RlySlackMatch.SEP) : null;
    }

    private void unlinked(RlySlackApproverRows.Row r, User u) {
        String note = noteOf(u);
        String fedNote = how == RlySlackDirectory.BY_SSO ? RlySlackLookup.skipReason(u, how, new Map<String, Integer>()) : null;
        if (fromNote(r, note)) {
            return;
        }
        if (fedNote != null) {
            Boolean empty = fedNote == RlySlackMatch.NOTE_FED_EMPTY;
            r.needs(empty ? 'fedEmpty' : 'fedNotEmail', fedNote,
                empty ? 'set it in Setup, or link by hand' : 'not looked up; set the ID by hand or switch to Email');
        } else if (note.startsWith(RlySlackMatch.NOTE_NOT_FOUND)) {
            String detail = detailOf(note);
            r.needs('notFound', RlySlackMatch.NOTE_NOT_FOUND, 'no Slack account with this email' + (detail == null ? '' : RlySlackMatch.SEP + detail));
        } else {
            r.needs('notLinked', 'Not linked', notLinkedDetail(note));
        }
    }

    // Same email (Email mode) and Slack ID already used come from the last match's note.
    private Boolean fromNote(RlySlackApproverRows.Row r, String note) {
        if (note.startsWith(RlySlackMatch.NOTE_SAME_EMAIL) && how == RlySlackDirectory.BY_EMAIL) {
            r.needs('pick', RlySlackMatch.NOTE_SAME_EMAIL, 'pick the one this Slack account belongs to');
            return true;
        }
        if (note.startsWith(RlySlackMatch.NOTE_USED)) {
            r.needs('used', RlySlackMatch.NOTE_USED, detailOf(note));
            return true;
        }
        return false;
    }

    private String notLinkedDetail(String note) {
        if (how == RlySlackMatch.MANUAL) {
            return 'set the ID by hand, or the approver links from Slack';
        }
        return note == '' ? 'not matched yet · press Match now' : note;
    }
}
