/**
 * @description Production approval (build 49). With the hub setting "Production approval needs the add-on" on
 * (RLY_Approval_Setting__c.Prod_Needs_Addon__c, org default row), approving a release whose target is the production hub
 * needs the RLY_Prod_Approver custom permission (add-on permission set RLY_Prod_Approver_Addon); an approver without it
 * approves only the other orgs. It applies wherever a release is approved (the release page, the Approvals tab, Slack,
 * both approvals of a two-approver hotfix). The setting is off by default, so a hub upgraded with existing approvers
 * isn't locked out; admins see a banner until they turn it on. A new hub turns it on when its first Git connection is
 * saved. The setting is read and written in system mode in the private inner class.
 */
public with sharing class RlyProdApproval {

    /** @description The custom permission that approves releases into production. */
    public static final String PERMISSION = 'RLY_Prod_Approver';
    /** @description What an approver without the add-on is told. */
    public static final String NOTE = 'Approving production needs the Production Approver add-on.';
    /** @description The admins' banner while the setting is off. */
    public static final String BANNER = 'Turn on once you\'ve assigned the Production Approver add-on.';
    /** @description The state value that turns it on (saveProdApproval). */
    public static final String STATE_ON = 'On';
    /** @description Changed_By__c when a new hub turned it on. */
    public static final String NEW_HUB = 'New hub';

    private static final Integer NAMES_SHOWN = 10;

    /** @description The setting for the Pipeline tab. */
    public class View {
        /** @description Whether approving production needs the add-on. */
        @AuraEnabled public Boolean isOn = false;
        /** @description Whether the viewer may change it (admins). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description The admins' banner while it is off, or null. */
        @AuraEnabled public String banner;
        /** @description How many active users hold the add-on. */
        @AuraEnabled public Integer holderCount = 0;
        /** @description Up to ten of their names. */
        @AuraEnabled public List<String> holderNames = new List<String>();
        /** @description Who changed it last and when, or null. */
        @AuraEnabled public String changedText;
        /** @description The sentence approvers without the add-on see. */
        @AuraEnabled public String note = NOTE;
    }

    /**
     * @description Whether approving a release into production needs the add-on.
     * @return true when the setting is on
     */
    public static Boolean isOn() {
        RLY_Approval_Setting__c s = new Data().read();
        return s != null && s.Prod_Needs_Addon__c == true;
    }

    /**
     * @description Whether the release goes into the production hub.
     * @param rel the release, with Target_Org__r.Role__c
     * @return true for the hub
     */
    public static Boolean isProduction(RLY_Release__c rel) {
        return rel != null && rel.Target_Org__r != null && rel.Target_Org__r.Role__c == 'Hub';
    }

    /**
     * @description Whether approving this release needs the add-on.
     * @param rel the release
     * @return true for a release into production with the setting on
     */
    public static Boolean needsAddon(RLY_Release__c rel) {
        return isProduction(rel) && isOn();
    }

    /**
     * @description Whether a user may approve the release, as far as the add-on goes.
     * @param rel the release
     * @param userId who approves (the current user, or a linked Slack user)
     * @return true when the add-on isn't needed or the user holds it
     */
    public static Boolean mayApprove(RLY_Release__c rel, Id userId) {
        return !needsAddon(rel) || RlyRoles.userHolds(PERMISSION, userId);
    }

    /**
     * @description Throws when the approver lacks the add-on the release needs.
     * @param rel the release
     * @param who who approves
     */
    public static void require(RLY_Release__c rel, RlyApprover who) {
        if (who != null && who.userId != null && !mayApprove(rel, who.userId)) {
            throw new RlyReleaseException(NOTE);
        }
    }

    /**
     * @description The release page's note for an approver who can't approve this one for want of the add-on.
     * @param rel the release
     * @return the note, or null
     */
    public static String noteFor(RLY_Release__c rel) {
        if (rel == null || rel.Status__c != 'Ready for approval' || !RlyApprovalService.canApprove()) {
            return null;
        }
        return mayApprove(rel, UserInfo.getUserId()) ? null : NOTE;
    }

    /**
     * @description The setting for the Pipeline tab.
     * @return the view
     */
    public static View view() {
        View v = new View();
        Data data = new Data();
        RLY_Approval_Setting__c s = data.read();
        v.isOn = s != null && s.Prod_Needs_Addon__c == true;
        v.canEdit = RlyOrgController.isAdmin();
        v.banner = v.canEdit && !v.isOn ? BANNER : null;
        if (s != null && s.Changed_On__c != null) {
            v.changedText = (v.isOn ? 'Turned on ' : 'Turned off ') + s.Changed_On__c.format('d MMM yyyy')
                + (String.isBlank(s.Changed_By__c) ? '' : ' by ' + s.Changed_By__c);
        }
        Set<Id> holders = RlyRoles.holdersOf(PERMISSION, null);
        v.holderCount = holders.size();
        for (User u : data.names(holders)) {
            v.holderNames.add(u.Name);
        }
        return v;
    }

    /**
     * @description Turns the setting on or off (admins).
     * @param state On (approving production needs the add-on) or Off
     * @return the view as saved
     */
    public static View save(String state) {
        if (!RlyOrgController.isAdmin()) {
            throw new RlyReleaseException('Only a Release Relay admin can change who approves production.');
        }
        new Data().write(state == STATE_ON ? STATE_ON : 'Off', UserInfo.getName());
        return view();
    }

    /**
     * @description A new hub (its first Git connection was just saved) starts with the setting on, unless an admin set
     * it already.
     */
    public static void onNewHub() {
        Data data = new Data();
        RLY_Approval_Setting__c s = data.read();
        if (s == null || s.Id == null) {
            data.write(STATE_ON, NEW_HUB);
        }
    }

    /** @description The protected setting and the holders' names, read and written in system mode. */
    private without sharing class Data {

        /**
         * @description The org default row (Id null when none is saved).
         * @return the row
         */
        public RLY_Approval_Setting__c read() {
            return RLY_Approval_Setting__c.getOrgDefaults();
        }

        /**
         * @description Saves the org default row.
         * @param state On or Off
         * @param byName who changed it
         */
        public void write(String state, String byName) {
            RLY_Approval_Setting__c s = RLY_Approval_Setting__c.getOrgDefaults();
            if (s == null || s.Id == null) {
                s = new RLY_Approval_Setting__c(SetupOwnerId = UserInfo.getOrganizationId());
            }
            s.Prod_Needs_Addon__c = state == STATE_ON;
            s.Changed_On__c = System.now();
            s.Changed_By__c = byName == null ? null : byName.left(121);
            upsert as system s;
        }

        /**
         * @description Names of up to ten users.
         * @param ids the users
         * @return the users, by name
         */
        public List<User> names(Set<Id> ids) {
            return [SELECT Name FROM User WHERE Id IN :ids WITH SYSTEM_MODE ORDER BY Name LIMIT :NAMES_SHOWN];
        }
    }
}
