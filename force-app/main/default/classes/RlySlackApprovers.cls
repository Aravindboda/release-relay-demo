/**
 * @description The Approvers window on the Pipeline tab (lwc rlySlackApprovers): the people who can approve releases
 * (RLY_Approver or RLY_Admin, direct or through a permission set group) and the Slack account each one approves from,
 * with how and when it was linked and what needs attention. Admins add approvers (RLY_Approver assigned in system mode,
 * that one permission set only), remove them (only a direct RLY_Approver assignment), run the Slack match in passes
 * (RlySlackMatch; the page loops), set, move, pick and unlink IDs, and check the Slack app's scopes. Every change is
 * checked for RLY_Admin here, not only by hidden buttons. Approvers see the list read-only, without Federation IDs.
 * Adding and matching are separate calls: Salesforce refuses a callout after uncommitted DML.
 */
public with sharing class RlySlackApprovers {

    /** @description What the window shows. */
    public class Window {
        /** @description The viewer can change things (RLY_Admin). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description SSO, Email or Manual. */
        @AuraEnabled public String matchBy;
        /** @description When matching last ran (Match now or Add). */
        @AuraEnabled public Datetime lastMatch;
        /** @description Who ran it. */
        @AuraEnabled public String lastMatchBy;
        /** @description Why Slack can't be asked now (Slack off, missing scopes), or null. */
        @AuraEnabled public String slackProblem;
        /** @description The scopes the bot token lacks, from the last check. */
        @AuraEnabled public List<String> missingScopes = new List<String>();
        /** @description The approvers, needing attention first, then by name. */
        @AuraEnabled public List<RlySlackApproverRows.Row> rows = new List<RlySlackApproverRows.Row>();
        /** @description Approvers linked to a Slack ID. */
        @AuraEnabled public Integer linked = 0;
        /** @description Approvers needing attention (not linked, or changed in Slack). */
        @AuraEnabled public Integer attention = 0;
        /** @description What the last change did, or null. */
        @AuraEnabled public String message;
    }

    /**
     * @description The window's data.
     * @return the window
     */
    @AuraEnabled
    public static Window load() {
        Boolean admin = RlyOrgController.isAdmin();
        if (!admin && !RlyApprovalService.canApprove()) {
            throw RlySlackController.auraError('Only ' + System.Label.RLY_App_Name + ' admins and approvers can see Slack approvers.');
        }
        Window w = new Window();
        w.isAdmin = admin;
        w.matchBy = RlySlackMatch.matchBy();
        fromSettings(w, RlySlack.settings());
        w.rows = new RlySlackApproverRows(w.matchBy, admin ? RlySlackDirectory.access() : null).rows();
        for (RlySlackApproverRows.Row r : w.rows) {
            w.linked += r.memberId == null ? 0 : 1;
            w.attention += r.reasonCode == null ? 0 : 1;
        }
        return w;
    }

    private static void fromSettings(Window w, RLY_Notification__c s) {
        if (s == null || !s.Enabled__c) {
            w.slackProblem = 'Connect Slack first (Slack connection → Edit).';
        }
        if (s == null) {
            return;
        }
        w.lastMatch = s.Last_Match__c;
        w.lastMatchBy = s.Last_Match_By__r == null ? null : s.Last_Match_By__r.Name;
        w.missingScopes = RlySlackPeople.missing(RlySlackPeople.parseScopes(s.Slack_Scopes__c));
        w.slackProblem = w.slackProblem == null ? RlySlackPeople.missingText(w.missingScopes) : w.slackProblem;
    }

    /**
     * @description Checks the Slack app's scopes (see RlySlackScopes.check).
     * @return the check
     */
    @AuraEnabled
    public static RlySlackScopes.ScopeCheck checkScopes() {
        requireAdmin();
        return RlySlackScopes.check();
    }

    /**
     * @description Active users for the Add approvers picker (see RlySlackApproverAdd.search).
     * @param term what was typed (at least two letters)
     * @return up to 50 people, by name
     */
    @AuraEnabled
    public static List<RlySlackApproverAdd.Candidate> searchUsers(String term) {
        requireAdmin();
        return RlySlackApproverAdd.search(term);
    }

    /**
     * @description Adds approvers (see RlySlackApproverAdd.add). No callout here: the page runs matchPass next.
     * @param userIds the people
     * @return who was added
     */
    @AuraEnabled
    public static RlySlackApproverAdd.AddResult addApprovers(List<Id> userIds) {
        requireAdmin();
        return RlySlackApproverAdd.add(userIds);
    }

    /**
     * @description One pass of the Slack match (at most RlySlackMatch.PASS_SIZE lookups). The page calls it again with
     * nextOffset until it is null, waiting retryAfter seconds when Slack is busy, then calls finishMatch.
     * @param userIds the people just added, or null for every approver
     * @param offset where this pass starts
     * @return what the pass did
     */
    @AuraEnabled
    public static RlySlackMatch.Pass matchPass(List<Id> userIds, Integer offset) {
        RlyHubGuard.requireHub();
        requireAdmin();
        return RlySlackMatch.run(userIds, offset);
    }

    /**
     * @description Records that matching ran (Last_Match__c, Last_Match_By__c), in its own call after the passes.
     * @return the window
     */
    @AuraEnabled
    public static Window finishMatch() {
        requireAdmin();
        RLY_Notification__c s = RlySlack.settings();
        if (s != null) {
            RlySlack.saveSettings(new RLY_Notification__c(Id = s.Id, Last_Match__c = System.now(), Last_Match_By__c = UserInfo.getUserId()));
        }
        return load();
    }

    /**
     * @description Set ID by hand: Slack is asked who it is first; saved with Linked by Admin.
     * @param userId the approver
     * @param memberId the Slack member ID
     * @return the window, with what was done
     */
    @AuraEnabled
    public static Window setMember(Id userId, String memberId) {
        requireAdmin();
        String message = RlySlackFix.setByHand(userId, memberId);
        return withMessage(message);
    }

    /**
     * @description A row's fix: move, pick, use or keep (see RlySlackFix.fix).
     * @param userId the approver
     * @param fix move, pick, use or keep
     * @return the window, with what was done
     */
    @AuraEnabled
    public static Window fixRow(Id userId, String fix) {
        requireAdmin();
        if (!RlySlackFix.FIXES.contains(fix)) {
            throw RlySlackController.auraError('Unknown fix.');
        }
        return withMessage(RlySlackFix.fix(userId, fix));
    }

    /**
     * @description Unlinks an approver: they stay an approver; Approve in Slack asks them to link again.
     * @param userId the approver
     * @return the window, with what was done
     */
    @AuraEnabled
    public static Window unlink(Id userId) {
        requireAdmin();
        User u = RlySlackFix.approver(userId);
        RlySlackDirectory.saveOne(RlySlackDirectory.linkRow(userId, null, null));
        return withMessage('Unlinked ' + u.Name + (u.RLY_Slack_Member_Id__c == null ? '.' : ' from ' + u.RLY_Slack_Member_Id__c + '.'));
    }

    /**
     * @description Removes an approver: deletes their direct RLY_Approver assignment (system mode). Admins (RLY_Admin) and
     * people who get approver access from a permission set group are changed in Setup instead. The Slack link is kept.
     * @param userId the approver
     * @return the window, with what was done
     */
    @AuraEnabled
    public static Window removeApprover(Id userId) {
        requireAdmin();
        RlySlackDirectory.Access a = RlySlackDirectory.accessOf(userId);
        String blocked = a == null ? 'That person isn\'t an approver.' : RlySlackApproverRows.removeNote(a);
        if (blocked != null) {
            throw RlySlackController.auraError(blocked);
        }
        User u = RlySlackFix.approver(userId);
        new Data().unassign(a.directApprover);
        return withMessage('Removed ' + u.Name + ' as an approver' + (a.groupName == null ? '.' : '; still one through ' + a.groupName + '.'));
    }

    private static Window withMessage(String message) {
        Window w = load();
        w.message = message;
        return w;
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw RlySlackController.auraError('Changing approvers needs the ' + System.Label.RLY_App_Name + ' Admin permission set.');
        }
    }

    /** @description RLY_Approver assignments, removed in system mode after the admin check. */
    private without sharing class Data {

        /**
         * @description Deletes a direct RLY_Approver assignment.
         * @param assignmentId the assignment
         */
        public void unassign(Id assignmentId) {
            List<PermissionSetAssignment> rows = [SELECT Id FROM PermissionSetAssignment WHERE Id = :assignmentId
                                                  AND PermissionSet.Name = :RlySlackDirectory.APPROVER_SET WITH SYSTEM_MODE LIMIT 1];
            if (!rows.isEmpty()) {
                delete as system rows;
            }
        }
    }
}
