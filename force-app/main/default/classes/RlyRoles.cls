/**
 * @description Who holds what (build 49): the permission set groups and add-ons. Custom permissions answer for the
 * current user (FeatureManagement); for another user (a Slack approver, the approvers window) the holders of a custom
 * permission are read from the permission sets that grant it, assigned directly or through a permission set group.
 * The Auditor (permission set RLY_Auditor) has no custom permission: it is read only, and so is a user with no Release
 * Relay role at all (no Admin, Approver or Deploy Team permission and no Developer permission set). Assignments are
 * read in system mode in the private inner class.
 */
public with sharing class RlyRoles {

    /** @description The read-only Auditor permission set. */
    public static final String AUDITOR_SET = 'RLY_Auditor';
    /** @description The Developer permission set (developers have no custom permission). */
    public static final String DEVELOPER_SET = 'RLY_Developer';
    /** @description Custom permissions that give a role with actions. */
    public static final List<String> ROLE_PERMISSIONS = new List<String>{ 'RLY_Admin', 'RLY_Approver', 'RLY_Deploy_Team' };

    private static Map<String, Boolean> heldSets = new Map<String, Boolean>();

    /**
     * @description Whether the current user holds a role custom permission (Admin, Approver or Deploy Team).
     * @return true for any of them
     */
    public static Boolean hasRolePermission() {
        for (String p : ROLE_PERMISSIONS) {
            if (FeatureManagement.checkPermission(p)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Whether the current user holds the Auditor permission set (directly or through a group).
     * @return true for auditors
     */
    public static Boolean isAuditor() {
        return holdsSet(AUDITOR_SET);
    }

    /**
     * @description Whether the current user only reads: no role custom permission and not a developer.
     * @return true for auditors and users without a Release Relay role
     */
    public static Boolean isReadOnly() {
        return !hasRolePermission() && !holdsSet(DEVELOPER_SET);
    }

    /**
     * @description Whether the current user holds a permission set, directly or through a permission set group.
     * @param setName the permission set's API name
     * @return true when held
     */
    public static Boolean holdsSet(String setName) {
        String slot = UserInfo.getUserId() + ':' + setName;
        if (!heldSets.containsKey(slot)) {
            heldSets.put(slot, new Data().holdsSet(UserInfo.getUserId(), setName));
        }
        return heldSets.get(slot);
    }

    /**
     * @description Which of these users hold a custom permission (through a permission set or a group).
     * @param customPermission the custom permission's API name
     * @param userIds the users, or null for every active holder
     * @return the users holding it
     */
    public static Set<Id> holdersOf(String customPermission, Set<Id> userIds) {
        return new Data().holders(customPermission, userIds);
    }

    /**
     * @description Whether one user holds a custom permission: FeatureManagement for the current user, the assignments
     * for anyone else.
     * @param customPermission the custom permission's API name
     * @param userId the user
     * @return true when held
     */
    public static Boolean userHolds(String customPermission, Id userId) {
        if (userId == null) {
            return false;
        }
        if (userId == UserInfo.getUserId()) {
            return FeatureManagement.checkPermission(customPermission);
        }
        return holdersOf(customPermission, new Set<Id>{ userId }).contains(userId);
    }

    /** @description Permission sets, groups and assignments, read in system mode. */
    private without sharing class Data {

        /**
         * @description Whether the user holds the permission set, directly or through a group.
         * @param userId the user
         * @param setName the permission set's API name
         * @return true when held
         */
        public Boolean holdsSet(Id userId, String setName) {
            Set<Id> groupIds = new Set<Id>();
            for (PermissionSetGroupComponent c : [SELECT PermissionSetGroupId FROM PermissionSetGroupComponent
                                                  WHERE PermissionSet.Name = :setName WITH SYSTEM_MODE LIMIT 200]) {
                groupIds.add(c.PermissionSetGroupId);
            }
            return ![SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :userId
                     AND (PermissionSet.Name = :setName OR PermissionSetGroupId IN :groupIds) WITH SYSTEM_MODE LIMIT 1].isEmpty();
        }

        /**
         * @description Active users holding the custom permission.
         * @param customPermission the custom permission's API name
         * @param userIds only these users, or null for all
         * @return the holders
         */
        public Set<Id> holders(String customPermission, Set<Id> userIds) {
            Set<Id> out = new Set<Id>();
            List<CustomPermission> perms = [SELECT Id FROM CustomPermission WHERE DeveloperName = :customPermission
                                            WITH SYSTEM_MODE LIMIT 1];
            if (perms.isEmpty()) {
                return out;
            }
            Set<Id> setIds = new Set<Id>();
            for (SetupEntityAccess a : [SELECT ParentId FROM SetupEntityAccess WHERE SetupEntityId = :perms[0].Id
                                        WITH SYSTEM_MODE LIMIT 1000]) {
                setIds.add(a.ParentId);
            }
            Set<Id> groupIds = new Set<Id>();
            for (PermissionSetGroupComponent c : [SELECT PermissionSetGroupId FROM PermissionSetGroupComponent
                                                  WHERE PermissionSetId IN :setIds WITH SYSTEM_MODE LIMIT 1000]) {
                groupIds.add(c.PermissionSetGroupId);
            }
            List<PermissionSetAssignment> rows = userIds == null
                ? [SELECT AssigneeId FROM PermissionSetAssignment WHERE (PermissionSetId IN :setIds OR PermissionSetGroupId IN :groupIds)
                   AND Assignee.IsActive = true WITH SYSTEM_MODE LIMIT 2000]
                : [SELECT AssigneeId FROM PermissionSetAssignment WHERE (PermissionSetId IN :setIds OR PermissionSetGroupId IN :groupIds)
                   AND AssigneeId IN :userIds AND Assignee.IsActive = true WITH SYSTEM_MODE LIMIT 2000];
            for (PermissionSetAssignment a : rows) {
                out.add(a.AssigneeId);
            }
            return out;
        }
    }
}
