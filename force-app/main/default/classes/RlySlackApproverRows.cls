/**
 * @description The approver rows of the Approvers window and the counts on the Slack connection line: each approver's
 * Slack link (how, when, by whom), access (Admin or Approver), whether Remove approver is allowed, and what needs
 * attention, worked out from the link, the note matching left (RLY_Slack_Match_Note__c) and the match setting.
 * Federation IDs and emails are filled for admins only.
 */
public with sharing class RlySlackApproverRows {

    private String how;
    private Map<Id, RlySlackDirectory.Access> access;

    /** @description One approver. */
    public class Row {
        /** @description The user. */
        @AuraEnabled public Id userId;
        /** @description The name. */
        @AuraEnabled public String name;
        /** @description The username. */
        @AuraEnabled public String username;
        /** @description The Federation ID (admins only). */
        @AuraEnabled public String federationId;
        /** @description The Salesforce email (admins only). */
        @AuraEnabled public String email;
        /** @description The Slack member ID, or null. */
        @AuraEnabled public String memberId;
        /** @description SSO, Email, Self or Admin. */
        @AuraEnabled public String linkedBy;
        /** @description When it was linked. */
        @AuraEnabled public Datetime linkedOn;
        /** @description The person who set it (Admin and Self links). */
        @AuraEnabled public String linkedByName;
        /** @description Admin or Approver. */
        @AuraEnabled public String access;
        /** @description Why Remove approver is off, or null when it can be removed. */
        @AuraEnabled public String removeNote;
        /** @description notFound, fedEmpty, fedNotEmail, pick, used, changed or notLinked; null when nothing needs attention. */
        @AuraEnabled public String reasonCode;
        /** @description The reason as shown, for example Not found in Slack. */
        @AuraEnabled public String reasonText;
        /** @description The detail after the reason. */
        @AuraEnabled public String reasonDetail;

        /**
         * @description Marks what needs attention.
         * @param code the reason code
         * @param text the reason
         * @param detail the detail, or null
         */
        public void needs(String code, String text, String detail) {
            reasonCode = code;
            reasonText = text;
            reasonDetail = detail;
        }
    }

    /**
     * @description Rows for a match setting.
     * @param how SSO, Email or Manual
     * @param access for an admin viewer, how each approver holds access (Federation IDs and emails shown); null otherwise
     */
    public RlySlackApproverRows(String how, Map<Id, RlySlackDirectory.Access> access) {
        this.how = how;
        this.access = access;
    }

    /**
     * @description Every approver, needing attention first, then by name.
     * @return the rows
     */
    public List<Row> rows() {
        List<Row> attention = new List<Row>();
        List<Row> fine = new List<Row>();
        for (User u : RlySlackDirectory.approvers()) {
            Row r = row(u);
            if (r.reasonCode == null) {
                fine.add(r);
            } else {
                attention.add(r);
            }
        }
        attention.addAll(fine);
        return attention;
    }

    /**
     * @description Approvers linked and needing attention, for the Slack connection line.
     * @return linked, attention and total
     */
    public static Map<String, Integer> counts() {
        List<Row> all = new RlySlackApproverRows(RlySlackMatch.matchBy(), null).rows();
        Integer linked = 0;
        Integer attention = 0;
        for (Row r : all) {
            linked += r.memberId == null ? 0 : 1;
            attention += r.reasonCode == null ? 0 : 1;
        }
        return new Map<String, Integer>{ 'linked' => linked, 'attention' => attention, 'total' => all.size() };
    }

    private Row row(User u) {
        Row r = new Row();
        r.userId = u.Id;
        r.name = u.Name;
        r.username = u.Username;
        if (access != null) {
            r.federationId = u.FederationIdentifier;
            r.email = u.Email;
        }
        r.memberId = String.isBlank(u.RLY_Slack_Member_Id__c) ? null : u.RLY_Slack_Member_Id__c;
        if (r.memberId != null) {
            r.linkedBy = u.RLY_Slack_Linked_By__c;
            r.linkedOn = u.RLY_Slack_Linked_On__c;
            r.linkedByName = u.RLY_Slack_Linked_By_User__r == null ? null : u.RLY_Slack_Linked_By_User__r.Name;
        }
        RlySlackDirectory.Access a = access == null ? null : access.get(u.Id);
        r.access = a != null && a.admin ? 'Admin' : 'Approver';
        r.removeNote = removeNote(a);
        new RlySlackReason(how).mark(r, u);
        return r;
    }

    /**
     * @description Why an approver can't be removed on the window, or null when they can.
     * @param a how they hold access
     * @return the reason, or null
     */
    public static String removeNote(RlySlackDirectory.Access a) {
        if (a == null) {
            return null;
        }
        if (a.admin) {
            return 'Admin access comes from RLY_Admin. Change it in Setup.';
        }
        return a.directApprover == null ? 'Comes from group ' + a.groupName + '. Change it in Setup.' : null;
    }
}
