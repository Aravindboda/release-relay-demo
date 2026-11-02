/**
 * @description Add approvers on the Approvers window: searching active users (name, username or Federation ID) and
 * assigning RLY_Approver to the people picked, in system mode and for that one permission set only, so an admin needs no
 * "Assign Permission Sets" right. People who already approve, or whose license can't hold RLY_Approver, are greyed. The
 * admin check is the caller's (RlySlackApprovers). No callout: matching runs in a separate call afterwards.
 */
public with sharing class RlySlackApproverAdd {

    /** @description Most people added in one call. */
    public static final Integer MAX_ADD = 200;
    /** @description Fewest letters a people search needs. */
    public static final Integer MIN_SEARCH = 2;

    /** @description A person the Add approvers picker shows. */
    public class Candidate {
        /** @description The user. */
        @AuraEnabled public Id userId;
        /** @description The name. */
        @AuraEnabled public String name;
        /** @description The username. */
        @AuraEnabled public String username;
        /** @description The Federation ID. */
        @AuraEnabled public String federationId;
        /** @description Why this person can't be picked (already an approver, license), or null. */
        @AuraEnabled public String blocked;
        /** @description Short label for blocked: Approver or License. */
        @AuraEnabled public String blockedTag;
    }

    /** @description What Add did. */
    public class AddResult {
        /** @description The people given RLY_Approver. */
        @AuraEnabled public List<Id> added = new List<Id>();
        /** @description Who couldn't be added and why. */
        @AuraEnabled public List<String> problems = new List<String>();
        /** @description Matching is manual only: the page doesn't run a match. */
        @AuraEnabled public Boolean manual = false;
    }

    /**
     * @description Active users for the Add approvers picker: name, username or Federation ID contains the text.
     * @param term what was typed (at least two letters)
     * @return up to 50 people, by name
     */
    public static List<Candidate> search(String term) {
        String t = term == null ? '' : term.trim();
        if (t.length() < MIN_SEARCH) {
            return new List<Candidate>();
        }
        Data data = new Data();
        Id license = data.approverLicense();
        Map<Id, RlySlackDirectory.Access> access = RlySlackDirectory.access();
        List<Candidate> out = new List<Candidate>();
        for (User u : data.findUsers(t)) {
            out.add(candidate(u, access.containsKey(u.Id), license));
        }
        return out;
    }

    private static Candidate candidate(User u, Boolean approver, Id license) {
        Candidate c = new Candidate();
        c.userId = u.Id;
        c.name = u.Name;
        c.username = u.Username;
        c.federationId = u.FederationIdentifier;
        if (approver) {
            c.blocked = 'Already an approver.';
            c.blockedTag = 'Approver';
        } else if (license != null && u.Profile.UserLicenseId != license) {
            c.blocked = 'Their license (' + u.Profile.UserLicense.Name + ') can\'t hold RLY_Approver.';
            c.blockedTag = 'License';
        }
        return c;
    }

    /**
     * @description Adds approvers: assigns RLY_Approver to each (system mode, that permission set only). No callout here:
     * the page runs matchPass for the added people next.
     * @param userIds the people
     * @return who was added
     */
    public static AddResult add(List<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            throw RlySlackController.auraError('Pick at least one person.');
        }
        if (userIds.size() > MAX_ADD) {
            throw RlySlackController.auraError('Add at most ' + MAX_ADD + ' people at a time.');
        }
        AddResult out = new AddResult();
        out.manual = RlySlackMatch.matchBy() == RlySlackMatch.MANUAL;
        Map<Id, RlySlackDirectory.Access> access = RlySlackDirectory.access();
        Data data = new Data();
        List<PermissionSetAssignment> rows = new List<PermissionSetAssignment>();
        Id setId = data.approverSetId();
        for (User u : data.activeUsers(new Set<Id>(userIds))) {
            if (!access.containsKey(u.Id)) {
                rows.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = setId));
            }
        }
        added(out, rows, data.assign(rows));
        return out;
    }

    private static void added(AddResult out, List<PermissionSetAssignment> rows, List<Database.SaveResult> results) {
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                out.added.add(rows[i].AssigneeId);
            } else {
                out.problems.add(rows[i].AssigneeId + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
    }

    /**
     * @description Escapes LIKE wildcards in typed text.
     * @param value the text
     * @return the text with backslash, % and _ escaped
     */
    @TestVisible
    private static String likeText(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    /** @description Users, licenses and RLY_Approver assignments, in system mode after the admin check. */
    private without sharing class Data {

        /**
         * @description Active standard users whose name, username or Federation ID contains the text.
         * @param term the text
         * @return up to 50 users
         */
        public List<User> findUsers(String term) {
            String pattern = '%' + likeText(term) + '%';
            return [SELECT Id, Name, Username, FederationIdentifier, Profile.UserLicenseId, Profile.UserLicense.Name FROM User
                    WHERE IsActive = true AND UserType = 'Standard'
                    AND (Name LIKE :pattern OR Username LIKE :pattern OR FederationIdentifier LIKE :pattern)
                    WITH SYSTEM_MODE ORDER BY Name LIMIT 50];
        }

        /**
         * @description Active standard users among these.
         * @param ids the users
         * @return the users
         */
        public List<User> activeUsers(Set<Id> ids) {
            return [SELECT Id FROM User WHERE Id IN :ids AND IsActive = true AND UserType = 'Standard' WITH SYSTEM_MODE LIMIT 200];
        }

        /**
         * @description RLY_Approver's Id.
         * @return the Id
         */
        public Id approverSetId() {
            List<PermissionSet> rows = [SELECT Id FROM PermissionSet WHERE Name = :RlySlackDirectory.APPROVER_SET WITH SYSTEM_MODE LIMIT 1];
            if (rows.isEmpty()) {
                throw RlySlackController.auraError('The RLY_Approver permission set isn\'t in this org.');
            }
            return rows[0].Id;
        }

        /**
         * @description The user license RLY_Approver needs, or null when it needs none (or a permission set license).
         * @return the UserLicense Id, or null
         */
        public Id approverLicense() {
            List<PermissionSet> rows = [SELECT LicenseId FROM PermissionSet WHERE Name = :RlySlackDirectory.APPROVER_SET WITH SYSTEM_MODE LIMIT 1];
            Id license = rows.isEmpty() ? null : rows[0].LicenseId;
            return license != null && license.getSobjectType() == UserLicense.SObjectType ? license : null;
        }

        /**
         * @description Inserts the assignments one by one.
         * @param rows RLY_Approver assignments
         * @return the results, in order
         */
        public List<Database.SaveResult> assign(List<PermissionSetAssignment> rows) {
            return Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
