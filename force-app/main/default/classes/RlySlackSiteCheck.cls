/**
 * @description Checks that the Salesforce Site Slack calls for Approve and Reject can do its work: its guest user
 * needs Read on User External Credentials and access to the Git credential's principal, or Approve does nothing.
 * Each problem is a sentence the Pipeline tab shows. A check that can't be read in this org is skipped.
 */
public with sharing class RlySlackSiteCheck {

    private static final String SLACK_CREDENTIAL = 'RLY_Slack';

    /** @description Tests check another user in place of a Site guest (an org may have no Site). */
    @TestVisible
    private static User guestForTest;

    /**
     * @description What the Site's guest user still needs, for the Pipeline tab (admins only; empty otherwise).
     * @return the problems
     */
    @AuraEnabled
    public static List<String> read() {
        return RlyOrgController.isAdmin() ? problems() : new List<String>();
    }

    /**
     * @description What the Site's guest user still needs (empty when nothing, or when no Site is set up).
     * @return the problems
     */
    public static List<String> problems() {
        List<String> out = new List<String>();
        Data data = new Data();
        User guest = guestForTest != null ? guestForTest : data.guest();
        if (guest == null) {
            return out;
        }
        Set<Id> sets = data.permissionSets(guest);
        for (String p : new List<String>{ credentialProblem(data, sets), principalProblem(data, sets) }) {
            if (p != null) {
                out.add(p);
            }
        }
        return out;
    }

    // A check this org can't read is skipped (null), so it never blocks.
    private static String credentialProblem(Data data, Set<Id> sets) {
        try {
            return data.readsUserCredentials(sets) ? null : 'Give the Site\'s guest profile Read on User External Credentials';
        } catch (Exception e) {
            return null;
        }
    }

    private static String principalProblem(Data data, Set<Id> sets) {
        try {
            return data.lacksGitPrincipal(sets)
                ? 'Give the Site\'s guest user access to the Git credential\'s principal (External Credential Principal Access)' : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** @description Sites, guest users and their permissions are setup data: read in system mode. */
    @TestVisible
    private without sharing class Data {

        /**
         * @description The guest user of the active Site whose guest holds the Slack Site permission set.
         * @return the guest, or null
         */
        public User guest() {
            Set<Id> guests = new Set<Id>();
            for (Schema.Site s : [SELECT GuestUserId FROM Site WHERE Status = 'Active' WITH SYSTEM_MODE LIMIT 100]) {
                guests.add(s.GuestUserId);
            }
            List<PermissionSetAssignment> rows = [SELECT AssigneeId, Assignee.ProfileId FROM PermissionSetAssignment
                                                  WHERE PermissionSet.Name = :RlySlackDirectory.SITE_SET AND AssigneeId IN :guests
                                                  WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : new User(Id = rows[0].AssigneeId, ProfileId = rows[0].Assignee.ProfileId);
        }

        /**
         * @description The guest's permission sets, the one its profile owns included.
         * @param guest the guest user
         * @return the permission set Ids
         */
        public Set<Id> permissionSets(User guest) {
            Set<Id> ids = new Set<Id>();
            for (PermissionSetAssignment a : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :guest.Id
                                              WITH SYSTEM_MODE LIMIT 200]) {
                ids.add(a.PermissionSetId);
            }
            for (PermissionSet p : [SELECT Id FROM PermissionSet WHERE ProfileId = :guest.ProfileId WITH SYSTEM_MODE LIMIT 1]) {
                ids.add(p.Id);
            }
            return ids;
        }

        /**
         * @description Whether one of the permission sets reads User External Credentials.
         * @param sets the permission set Ids
         * @return true when one does
         */
        public Boolean readsUserCredentials(Set<Id> sets) {
            return !Database.queryWithBinds('SELECT Id FROM ObjectPermissions WHERE ParentId IN :sets AND SobjectType = \'UserExternalCredential\' '
                + 'AND PermissionsRead = true LIMIT 1', new Map<String, Object>{ 'sets' => sets }, AccessLevel.SYSTEM_MODE).isEmpty();
        }

        /**
         * @description Whether the org has a named principal outside Slack's credential (the Git one) and none of the
         * permission sets gives access to it.
         * @param sets the permission set Ids
         * @return true when the access is missing
         */
        public Boolean lacksGitPrincipal(Set<Id> sets) {
            Set<Id> principals = new Map<Id, SObject>(Database.queryWithBinds('SELECT Id FROM ExternalCredentialParameter '
                + 'WHERE ParameterType = \'NamedPrincipal\' AND ExternalCredential.DeveloperName != :slack LIMIT 200',
                new Map<String, Object>{ 'slack' => SLACK_CREDENTIAL }, AccessLevel.SYSTEM_MODE)).keySet();
            if (principals.isEmpty()) {
                return false;
            }
            return [SELECT Id FROM SetupEntityAccess WHERE ParentId IN :sets AND SetupEntityId IN :principals WITH SYSTEM_MODE LIMIT 1].isEmpty();
        }
    }
}
