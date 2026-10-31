/**
 * @description Back promote (optional, off by default: RLY_Git_Connection__c.Back_Promote__c): orgs with the role
 * Back_Promote receive production's changes, metadata only, and never send anything up the route. Each sync is a
 * release record (Release_Type__c Back_Promote, source the hub org, target that org) run with pipeline mode sync
 * (RlyBackPromoteRun). An org gets one after every deploy to the hub (Back_Promote_When__c After_Deploy) or when an
 * admin clicks Sync now (Manual, the default); with Back_Promote_Approval__c it waits for an approver first.
 * A sync is saved queued (Status Submitted) and started on the next read (its page, the hub release's page or the
 * Pipeline tab), because the run is named after the record and a callout can't follow the insert.
 */
public with sharing class RlyBackPromote {

    /** @description RLY_Org__c.Role__c of a back promote org. */
    public static final String ROLE = 'Back_Promote';
    /** @description Back_Promote_When__c: when an admin clicks Sync now (the default). */
    public static final String WHEN_MANUAL = 'Manual';
    /** @description Back_Promote_When__c: after every deploy to the hub. */
    public static final String WHEN_AFTER_DEPLOY = 'After_Deploy';

    /** @description What the Pipeline tab shows about back promote. */
    public class BackPromoteBoard {
        /** @description Back promote is on. */
        @AuraEnabled public Boolean enabled = false;
        /** @description The current user is an admin. */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description The back promote orgs, by name. */
        @AuraEnabled public List<BackPromoteOrg> orgs = new List<BackPromoteOrg>();
    }

    /** @description One back promote org. */
    public class BackPromoteOrg {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Its branch. */
        @AuraEnabled public String branch;
        /** @description Its Salesforce environment. */
        @AuraEnabled public String environment;
        /** @description Its Git environment. */
        @AuraEnabled public String gitEnvironment;
        /** @description Its last sign-in check. */
        @AuraEnabled public String status;
        /** @description Manual or After_Deploy. */
        @AuraEnabled public String whenValue;
        /** @description Each sync waits for an approver. */
        @AuraEnabled public Boolean approval;
        /** @description How many hub deploys it hasn't received. */
        @AuraEnabled public Integer behind;
        /** @description Their release numbers. */
        @AuraEnabled public List<String> behindNames = new List<String>();
        /** @description When its last successful sync started. */
        @AuraEnabled public Datetime syncedOn;
        /** @description Deployed, Failed, Conflict or Running. */
        @AuraEnabled public String syncStatus;
        /** @description Its latest sync release, or null. */
        @AuraEnabled public Id lastSyncId;
    }

    /**
     * @description The board: whether back promote is on and each back promote org with how far behind it is. A never
     * synced org counts the hub deploys since it was registered (its first sync makes its branch from the hub's).
     * @return the board
     */
    public static BackPromoteBoard board() {
        BackPromoteBoard b = new BackPromoteBoard();
        b.isAdmin = RlyOrgController.isAdmin();
        b.enabled = isOn(RlyReleaseStore.git());
        RLY_Org__c hub = RlyPromoteStore.hub();
        List<RLY_Release__c> deployed = hub == null ? new List<RLY_Release__c>() : RlyPromoteStore.hubDeployed(hub.Id);
        Map<Id, RLY_Release__c> lastSync = latestByOrg();
        for (RLY_Org__c o : RlyPromoteStore.backPromoteOrgs()) {
            BackPromoteOrg x = toOrg(o);
            x.lastSyncId = lastSync.containsKey(o.Id) ? lastSync.get(o.Id).Id : null;
            Datetime since = o.Synced_On__c == null ? o.CreatedDate : o.Synced_On__c;
            for (RLY_Release__c r : deployed) {
                if (r.Last_Synced__c != null && (since == null || r.Last_Synced__c > since)) {
                    x.behindNames.add(r.Name);
                }
            }
            x.behind = x.behindNames.size();
            b.orgs.add(x);
        }
        return b;
    }

    private static BackPromoteOrg toOrg(RLY_Org__c o) {
        BackPromoteOrg x = new BackPromoteOrg();
        x.orgId = o.Id;
        x.name = o.Name;
        x.branch = o.Branch__c;
        x.environment = o.Environment__c;
        x.gitEnvironment = o.Git_Environment__c;
        x.status = o.Status__c;
        x.whenValue = whenOf(o);
        x.approval = o.Back_Promote_Approval__c == true;
        x.syncedOn = o.Synced_On__c;
        x.syncStatus = o.Sync_Status__c;
        return x;
    }

    /**
     * @description When an org gets the hub's changes.
     * @param o the org
     * @return Manual (also when blank) or After_Deploy
     */
    public static String whenOf(RLY_Org__c o) {
        return o.Back_Promote_When__c == WHEN_AFTER_DEPLOY ? WHEN_AFTER_DEPLOY : WHEN_MANUAL;
    }

    /**
     * @description Whether back promote is on.
     * @param conn the Git connection, or null
     * @return true when on
     */
    public static Boolean isOn(RLY_Git_Connection__c conn) {
        return conn != null && conn.Back_Promote__c == true;
    }

    // The newest sync of each org.
    private static Map<Id, RLY_Release__c> latestByOrg() {
        Map<Id, RLY_Release__c> out = new Map<Id, RLY_Release__c>();
        for (RLY_Release__c r : RlyPromoteStore.latestSyncs()) {
            if (!out.containsKey(r.Target_Org__c)) {
                out.put(r.Target_Org__c, r);
            }
        }
        return out;
    }

    /**
     * @description Turns back promote on or off (admins).
     * @param state on or off
     */
    public static void setEnabled(String state) {
        requireAdmin();
        if (state != 'on' && state != 'off') {
            throw problem('Say on or off.');
        }
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null) {
            throw problem('Save the Git connection first.');
        }
        RlyPromoteStore.saveGit(new RLY_Git_Connection__c(Id = conn.Id, Back_Promote__c = state == 'on'));
    }

    /**
     * @description Saves when a back promote org syncs and whether an approver approves each sync first (admins).
     * @param settingsJson {orgId, whenValue: Manual|After_Deploy, approval: true|false}
     */
    public static void saveOrgSettings(String settingsJson) {
        requireAdmin();
        Map<String, Object> s;
        try {
            s = (Map<String, Object>) JSON.deserializeUntyped(settingsJson);
        } catch (Exception e) {
            throw problem('The back promote settings couldn\'t be read.');
        }
        RLY_Org__c o = findOrg(String.valueOf(s.get('orgId')));
        String whenValue = s.get('whenValue') == null ? whenOf(o) : String.valueOf(s.get('whenValue'));
        if (whenValue != WHEN_MANUAL && whenValue != WHEN_AFTER_DEPLOY) {
            throw problem('Pick when ' + o.Name + ' gets the changes: Manual or After_Deploy.');
        }
        Boolean approval = s.get('approval') == null ? o.Back_Promote_Approval__c == true : Boolean.valueOf(s.get('approval'));
        RlyPromoteStore.saveOrgs(new List<RLY_Org__c>{
            new RLY_Org__c(Id = o.Id, Back_Promote_When__c = whenValue, Back_Promote_Approval__c = approval) });
    }

    /**
     * @description A registered back promote org.
     * @param orgId the org's Id (15 or 18 characters)
     * @return the org
     */
    public static RLY_Org__c findOrg(String orgId) {
        for (RLY_Org__c o : RlyPromoteStore.backPromoteOrgs()) {
            if (String.valueOf(o.Id).equals(orgId) || String.valueOf(o.Id).left(15).equals(orgId)) {
                return o;
            }
        }
        throw problem('Pick a registered back promote org.');
    }

    /**
     * @description Refuses users who aren't Release Relay admins.
     */
    public static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw problem('Changing back promote needs the Release Relay Admin permission set.');
        }
    }

    /**
     * @description A problem the page shows as it is.
     * @param message the message
     * @return the exception to throw
     */
    public static AuraHandledException problem(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
