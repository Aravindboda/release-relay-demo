/**
 * @description Who may act from Slack: the active users who hold the RLY_Approver or RLY_Admin permission set (directly
 * or through a permission set group), their linked Slack member IDs (User.RLY_Slack_Member_Id__c, unique) with how and
 * when each was linked, and the Salesforce Site whose guest user receives Slack's button clicks (the guest user holds
 * RLY_Slack_Site). Users and assignments are read and saved in system mode: the Slack request runs as the Site guest user.
 * A member ID is saved upper case; a save that hits the unique field says who already has it.
 */
public with sharing class RlySlackDirectory {

    /** @description Permission sets whose holders may approve. */
    public static final Set<String> APPROVER_SETS = new Set<String>{ 'RLY_Approver', 'RLY_Admin' };
    /** @description The permission set admins add and remove on the Approvers window. */
    public static final String APPROVER_SET = 'RLY_Approver';
    /** @description The admin permission set. */
    public static final String ADMIN_SET = 'RLY_Admin';
    /** @description The permission set of the Site guest user. */
    public static final String SITE_SET = 'RLY_Slack_Site';
    /** @description Path of the Slack endpoint on the Site. */
    public static final String ACTIONS_PATH = '/services/apexrest/rly/slack/actions';
    /** @description Linked by: the SSO Federation ID found in Slack. */
    public static final String BY_SSO = 'SSO';
    /** @description Linked by: the Salesforce email found in Slack. */
    public static final String BY_EMAIL = 'Email';
    /** @description Linked by: the approver, from Slack. */
    public static final String BY_SELF = 'Self';
    /** @description Linked by: an admin, by hand. */
    public static final String BY_ADMIN = 'Admin';

    /** @description How a user holds approver access. */
    public class Access {
        /** @description Holds RLY_Admin (directly or through a group). */
        public Boolean admin = false;
        /** @description The direct RLY_Approver assignment, or null. */
        public Id directApprover;
        /** @description The permission set group that gives approver access, or null. */
        public String groupName;
    }

    /**
     * @description Every active approver (RLY_Approver or RLY_Admin, direct or through a group), by name.
     * @return the users, with their Slack link fields, Username, Email and FederationIdentifier
     */
    public static List<User> approvers() {
        Data data = new Data();
        return data.readUsers(data.readAccess(null).keySet());
    }

    /**
     * @description How each active approver holds access.
     * @return user Id to access
     */
    public static Map<Id, Access> access() {
        return new Data().readAccess(null);
    }

    /**
     * @description How one user holds approver access.
     * @param userId the user
     * @return the access, or null when the user isn't an approver
     */
    public static Access accessOf(Id userId) {
        return new Data().readAccess(new Set<Id>{ userId }).get(userId);
    }

    /**
     * @description The active user linked to a Slack member ID, when that user is an approver.
     * @param memberId the Slack user ID
     * @return the user, with Name, or null
     */
    public static User approverFor(String memberId) {
        User u = linkedUser(memberId);
        return u != null && accessOf(u.Id) != null ? u : null;
    }

    /**
     * @description The active user linked to a Slack member ID, approver or not.
     * @param memberId the Slack user ID
     * @return the user, with Name, or null
     */
    public static User linkedUser(String memberId) {
        return String.isBlank(memberId) ? null : new Data().readLinkedUser(memberId.trim().toUpperCase());
    }

    /**
     * @description The users (active or not) holding these member IDs.
     * @param memberIds the member IDs, upper case
     * @return member ID (upper case) to user, with Name and IsActive
     */
    public static Map<String, User> holders(Set<String> memberIds) {
        Map<String, User> out = new Map<String, User>();
        for (User u : new Data().readHolders(memberIds)) {
            out.put(u.RLY_Slack_Member_Id__c.toUpperCase(), u);
        }
        return out;
    }

    /**
     * @description Active users with this Federation ID or email (to tell an approver from someone who isn't one).
     * @param value the Federation ID or email
     * @param how SSO (compare the Federation ID) or Email (compare the Salesforce email)
     * @return the users, with their Slack link fields
     */
    public static List<User> usersWith(String value, String how) {
        if (String.isBlank(value)) {
            return new List<User>();
        }
        Data data = new Data();
        return how == BY_EMAIL ? data.readUsersByEmail(value.trim()) : data.readUsersByFederation(value.trim());
    }

    /**
     * @description A user row that sets (or, with a null member ID, clears) a link. Linked By User is the person saving
     * it for Self and Admin links (the approver, or the admin); SSO and Email links have none.
     * @param userId the user
     * @param memberId the member ID, or null to clear the link
     * @param how SSO, Email, Self or Admin
     * @return the row to save
     */
    public static User linkRow(Id userId, String memberId, String how) {
        Boolean clear = String.isBlank(memberId);
        Boolean byPerson = how == BY_SELF || how == BY_ADMIN;
        return new User(Id = userId, RLY_Slack_Member_Id__c = clear ? null : memberId.trim().toUpperCase(),
            RLY_Slack_Linked_By__c = clear ? null : how, RLY_Slack_Linked_On__c = clear ? null : System.now(),
            RLY_Slack_Linked_By_User__c = clear || !byPerson ? null : UserInfo.getUserId(), RLY_Slack_Match_Note__c = null);
    }

    /**
     * @description Saves user rows (link fields only), each on its own: one that fails doesn't stop the others.
     * @param rows the rows
     * @return user Id to why it wasn't saved ("Slack ID already used by …" for a member ID someone else has)
     */
    public static Map<Id, String> save(List<User> rows) {
        Map<Id, String> failed = new Map<Id, String>();
        if (rows == null || rows.isEmpty()) {
            return failed;
        }
        Data data = new Data();
        List<Database.SaveResult> results = data.saveUsers(rows);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failed.put(rows[i].Id, failure(data, rows[i], results[i].getErrors()));
            }
        }
        return failed;
    }

    /**
     * @description Saves one user row; a failure becomes an error the page shows.
     * @param row the row
     */
    public static void saveOne(User row) {
        Map<Id, String> failed = save(new List<User>{ row });
        if (failed.containsKey(row.Id)) {
            throw RlySlackController.auraError(failed.get(row.Id));
        }
    }

    // DUPLICATE_VALUE: the unique member ID field refused it; say who holds the ID.
    private static String failure(Data data, User row, List<Database.Error> errors) {
        for (Database.Error e : errors) {
            if (e.getStatusCode() == StatusCode.DUPLICATE_VALUE && row.RLY_Slack_Member_Id__c != null) {
                List<User> holder = data.readHolders(new Set<String>{ row.RLY_Slack_Member_Id__c });
                return 'Slack ID already used by ' + (holder.isEmpty() ? 'another user' : holder[0].Name) + '.';
            }
        }
        return errors.isEmpty() ? 'Not saved.' : errors[0].getMessage();
    }

    /**
     * @description The URL to give Slack (Interactivity Request URL): the active Site whose guest user holds RLY_Slack_Site.
     * @return the URL, or null when no such Site is set up
     */
    public static String actionsUrl() {
        try {
            String base = new Data().readSiteUrl();
            return base == null ? null : base.removeEnd('/') + ACTIONS_PATH;
        } catch (Exception e) {
            return null;
        }
    }

    /** @description Users, assignments and Sites, read and saved in system mode. */
    private without sharing class Data {

        /**
         * @description How active users hold RLY_Approver or RLY_Admin, directly or through a permission set group.
         * @param only these users only, or null for every approver
         * @return user Id to access
         */
        public Map<Id, Access> readAccess(Set<Id> only) {
            Map<Id, String> groupSet = new Map<Id, String>();
            Map<Id, String> groupName = new Map<Id, String>();
            for (PermissionSetGroupComponent c : [SELECT PermissionSetGroupId, PermissionSetGroup.MasterLabel, PermissionSet.Name
                                                  FROM PermissionSetGroupComponent WHERE PermissionSet.Name IN :APPROVER_SETS
                                                  WITH SYSTEM_MODE LIMIT 200]) {
                Boolean admin = c.PermissionSet.Name == ADMIN_SET || groupSet.get(c.PermissionSetGroupId) == ADMIN_SET;
                groupSet.put(c.PermissionSetGroupId, admin ? ADMIN_SET : APPROVER_SET);
                groupName.put(c.PermissionSetGroupId, c.PermissionSetGroup.MasterLabel);
            }
            Set<Id> groupIds = groupSet.keySet();
            List<PermissionSetAssignment> rows = only == null
                ? [SELECT Id, AssigneeId, PermissionSet.Name, PermissionSetGroupId FROM PermissionSetAssignment
                   WHERE (PermissionSet.Name IN :APPROVER_SETS OR PermissionSetGroupId IN :groupIds) AND Assignee.IsActive = true
                   WITH SYSTEM_MODE LIMIT 2000]
                : [SELECT Id, AssigneeId, PermissionSet.Name, PermissionSetGroupId FROM PermissionSetAssignment
                   WHERE (PermissionSet.Name IN :APPROVER_SETS OR PermissionSetGroupId IN :groupIds) AND Assignee.IsActive = true
                   AND AssigneeId IN :only WITH SYSTEM_MODE LIMIT 2000];
            Map<Id, Access> out = new Map<Id, Access>();
            for (PermissionSetAssignment a : rows) {
                Access acc = out.containsKey(a.AssigneeId) ? out.get(a.AssigneeId) : new Access();
                String setName = a.PermissionSetGroupId == null ? a.PermissionSet.Name : groupSet.get(a.PermissionSetGroupId);
                acc.admin = acc.admin || setName == ADMIN_SET;
                if (a.PermissionSetGroupId != null) {
                    acc.groupName = groupName.get(a.PermissionSetGroupId);
                } else if (setName == APPROVER_SET) {
                    acc.directApprover = a.Id;
                }
                out.put(a.AssigneeId, acc);
            }
            return out;
        }

        /**
         * @description The users, with their Slack link fields.
         * @param ids the users
         * @return the users, by name
         */
        public List<User> readUsers(Set<Id> ids) {
            return [SELECT Id, Name, Username, Email, FederationIdentifier, RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c,
                           RLY_Slack_Linked_On__c, RLY_Slack_Linked_By_User__c, RLY_Slack_Linked_By_User__r.Name, RLY_Slack_Match_Note__c
                    FROM User WHERE Id IN :ids AND IsActive = true WITH SYSTEM_MODE ORDER BY Name, Id LIMIT 2000];
        }

        /**
         * @description The active user with this Slack member ID.
         * @param memberId the Slack member ID
         * @return the user, or null
         */
        public User readLinkedUser(String memberId) {
            List<User> rows = [SELECT Id, Name, RLY_Slack_Member_Id__c FROM User WHERE RLY_Slack_Member_Id__c = :memberId AND IsActive = true
                               WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The users, active or not, holding these member IDs.
         * @param memberIds the member IDs
         * @return the users
         */
        public List<User> readHolders(Set<String> memberIds) {
            return [SELECT Id, Name, IsActive, RLY_Slack_Member_Id__c FROM User WHERE RLY_Slack_Member_Id__c IN :memberIds
                    WITH SYSTEM_MODE LIMIT 2000];
        }

        /**
         * @description Active users with this email.
         * @param value the email
         * @return the users
         */
        public List<User> readUsersByEmail(String value) {
            return [SELECT Id, Name, RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c FROM User WHERE Email = :value AND IsActive = true
                    WITH SYSTEM_MODE LIMIT 5];
        }

        /**
         * @description Active users with this Federation ID.
         * @param value the Federation ID
         * @return the users
         */
        public List<User> readUsersByFederation(String value) {
            return [SELECT Id, Name, RLY_Slack_Member_Id__c, RLY_Slack_Linked_By__c FROM User WHERE FederationIdentifier = :value
                    AND IsActive = true WITH SYSTEM_MODE LIMIT 5];
        }

        /**
         * @description Saves the rows one by one (allOrNone false).
         * @param rows the rows
         * @return the results, in order
         */
        public List<Database.SaveResult> saveUsers(List<User> rows) {
            return Database.update(rows, false, AccessLevel.SYSTEM_MODE);
        }

        /**
         * @description The secure URL of the active Site whose guest user holds RLY_Slack_Site.
         * @return the URL, or null
         */
        public String readSiteUrl() {
            Map<Id, Id> siteByGuest = new Map<Id, Id>();
            for (Schema.Site s : [SELECT Id, GuestUserId FROM Site WHERE Status = 'Active' WITH SYSTEM_MODE LIMIT 100]) {
                siteByGuest.put(s.GuestUserId, s.Id);
            }
            List<PermissionSetAssignment> guests = [SELECT AssigneeId FROM PermissionSetAssignment
                                                    WHERE PermissionSet.Name = :SITE_SET AND AssigneeId IN :siteByGuest.keySet()
                                                    WITH SYSTEM_MODE LIMIT 1];
            Id siteId = guests.isEmpty() ? null : siteByGuest.get(guests[0].AssigneeId);
            List<SiteDetail> details = siteId == null ? new List<SiteDetail>()
                : [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :siteId WITH SYSTEM_MODE LIMIT 1];
            return details.isEmpty() ? null : details[0].SecureUrl;
        }
    }
}
