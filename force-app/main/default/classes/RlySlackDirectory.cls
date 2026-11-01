/**
 * @description Who may act from Slack: the users who hold the RLY_Approver or RLY_Admin permission set, their linked
 * Slack member IDs (User.RLY_Slack_Member_Id__c), and the Salesforce Site whose guest user receives Slack's button
 * clicks (the guest user holds RLY_Slack_Site). Users and assignments are read in system mode: the Slack request runs
 * as the Site guest user.
 */
public with sharing class RlySlackDirectory {

    /** @description Permission sets whose holders may approve. */
    public static final Set<String> APPROVER_SETS = new Set<String>{ 'RLY_Approver', 'RLY_Admin' };
    /** @description The permission set of the Site guest user. */
    public static final String SITE_SET = 'RLY_Slack_Site';
    /** @description Path of the Slack endpoint on the Site. */
    public static final String ACTIONS_PATH = '/services/apexrest/rly/slack/actions';

    /**
     * @description Every active approver (RLY_Approver or RLY_Admin), by name.
     * @return the users, with Name and RLY_Slack_Member_Id__c
     */
    public static List<User> approvers() {
        return new Data().readApprovers();
    }

    /**
     * @description The active user linked to a Slack member ID, when that user is an approver.
     * @param memberId the Slack user ID
     * @return the user, with Name, or null
     */
    public static User approverFor(String memberId) {
        if (String.isBlank(memberId)) {
            return null;
        }
        Data data = new Data();
        User u = data.readLinkedUser(memberId);
        return u != null && data.isApprover(u.Id) ? u : null;
    }

    /**
     * @description Links a user to a Slack member ID (admins only; checked by RlySlackController).
     * @param userId the user
     * @param memberId the Slack member ID, or null to clear it
     */
    public static void link(Id userId, String memberId) {
        Data data = new Data();
        User other = memberId == null ? null : data.readLinkedUser(memberId);
        if (other != null && other.Id != userId) {
            throw RlySlackController.auraError(memberId + ' is already linked to ' + other.Name + '.');
        }
        data.saveMember(userId, memberId);
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

    /** @description Users, assignments and Sites, read in system mode. */
    private without sharing class Data {

        /**
         * @description See RlySlackDirectory.approvers.
         * @return the users
         */
        public List<User> readApprovers() {
            Set<Id> ids = new Set<Id>();
            for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment
                                              WHERE PermissionSet.Name IN :APPROVER_SETS AND Assignee.IsActive = true
                                              WITH SYSTEM_MODE LIMIT 1000]) {
                ids.add(a.AssigneeId);
            }
            return [SELECT Id, Name, RLY_Slack_Member_Id__c FROM User WHERE Id IN :ids WITH SYSTEM_MODE ORDER BY Name LIMIT 1000];
        }

        /**
         * @description The active user with this Slack member ID.
         * @param memberId the Slack member ID
         * @return the user, or null
         */
        public User readLinkedUser(String memberId) {
            List<User> rows = [SELECT Id, Name FROM User WHERE RLY_Slack_Member_Id__c = :memberId AND IsActive = true
                               WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Whether the user holds RLY_Approver or RLY_Admin.
         * @param userId the user
         * @return true when it does
         */
        public Boolean isApprover(Id userId) {
            return ![SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.Name IN :APPROVER_SETS
                     WITH SYSTEM_MODE LIMIT 1].isEmpty();
        }

        /**
         * @description Saves the link.
         * @param userId the user
         * @param memberId the Slack member ID, or null
         */
        public void saveMember(Id userId, String memberId) {
            update as system new User(Id = userId, RLY_Slack_Member_Id__c = memberId);
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
