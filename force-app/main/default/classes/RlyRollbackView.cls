/**
 * @description What a release page shows about rolling it back (RlyReleasesController.Detail.rollback): the latest
 * rollback (Running, Rolled_Back or Failed, in which org, by whom, when, why, and its result), whether the current
 * user sees the Roll back button (Release Relay admins and the deployment team, on the hub, for a deployed release
 * that isn't manual steps only) and whether it is disabled now (a deploy or a rollback is running).
 */
public with sharing class RlyRollbackView {

    /** @description The release page's rollback part. */
    public class View {
        /** @description Running, Rolled_Back, Failed, or null when it was never rolled back. */
        @AuraEnabled public String status;
        /** @description "Rolling back in PROD", "Rolled back in PROD" or "Rollback failed in PROD", or null. */
        @AuraEnabled public String label;
        /** @description The org rolled back, or null. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String orgName;
        /** @description Who started it. */
        @AuraEnabled public String byName;
        /** @description When it started (and, once it finished, when it finished). */
        @AuraEnabled public Datetime rolledBackOn;
        /** @description Why. */
        @AuraEnabled public String reason;
        /** @description What was started and, once finished, rollback.json (deployId, restored, removed, message, …), as JSON. */
        @AuraEnabled public String resultJson;
        /** @description A rollback is running: the page keeps checking. */
        @AuraEnabled public Boolean running = false;
        /** @description The current user sees the Roll back button. */
        @AuraEnabled public Boolean canRollBack = false;
        /** @description The button is disabled: a deploy or a rollback is running. */
        @AuraEnabled public Boolean busy = false;
    }

    /**
     * @description Fills the page's rollback part; a running rollback keeps the page checking.
     * @param d the page payload, with release and running set
     */
    public static void fill(RlyReleasesController.Detail d) {
        d.rollbackState = of(d.release);
        d.running = d.running == true || d.rollbackState.running;
    }

    /**
     * @description The rollback part of a release page.
     * @param rel the release (RlyReleaseStore.release)
     * @return the view
     */
    public static View of(RLY_Release__c rel) {
        View v = new View();
        RLY_Release__c row = RlyRollbackState.rowOf(rel.Id);
        v.status = row.Rollback_Status__c;
        v.label = RlyRollbackState.label(row);
        if (v.status != null) {
            v.orgId = row.Rollback_Org__c;
            v.orgName = RlyRollbackState.orgName(row);
            v.byName = RlyRollbackState.byName(row);
            v.rolledBackOn = row.Rollback_On__c;
            v.reason = row.Rollback_Reason__c;
            v.resultJson = row.Rollback_Result__c;
        }
        v.running = v.status == RlyRollbackState.RUNNING;
        v.canRollBack = rel.Status__c == 'Deployed' && !RlyManualOnly.isManualOnly(rel) && RlyRollback.mayRollBack() && RlyHubGuard.isHub();
        v.busy = v.running || RlyStatusReader.isOpen(rel);
        return v;
    }
}
