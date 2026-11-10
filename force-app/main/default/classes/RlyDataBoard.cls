/**
 * @description The Data view of the Sync status tab: the data sets, the orgs a run can use (with whether the pipeline can
 * load them, and "Refill this org" when an org's Org Id changed since its last load, i.e. it was refreshed), the latest
 * runs, and what the viewer may do.
 */
public with sharing class RlyDataBoard {

    /** @description The view. */
    public class Board {
        /** @description The data sets. */
        @AuraEnabled public List<SetRow> sets = new List<SetRow>();
        /** @description The orgs. */
        @AuraEnabled public List<OrgRow> orgs = new List<OrgRow>();
        /** @description The latest runs. */
        @AuraEnabled public List<RunRow> runs = new List<RunRow>();
        /** @description Admins edit data sets and copy data down. */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description Approvers and the deployment team load data sent up. */
        @AuraEnabled public Boolean isApprover = false;
        /** @description Copies data down and refills (admins and the deployment team, build 49). */
        @AuraEnabled public Boolean canMoveDown = false;
        /** @description The viewer. */
        @AuraEnabled public Id userId;
    }

    /** @description A data set. */
    public class SetRow {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description What it's for. */
        @AuraEnabled public String description;
        /** @description The definition JSON. */
        @AuraEnabled public String definition;
        /** @description Why it can't be used, or null. */
        @AuraEnabled public String problem;
        /** @description How many objects. */
        @AuraEnabled public Integer objectCount = 0;
    }

    /** @description An org. */
    public class OrgRow {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Developer, Stage or Hub. */
        @AuraEnabled public String role;
        /** @description The pipeline can load it. */
        @AuraEnabled public Boolean canLoad = false;
        /** @description Refreshed since its last load (its Org Id changed). */
        @AuraEnabled public Boolean refillDue = false;
        /** @description The last load's run into it, for Refill. */
        @AuraEnabled public String lastRunId;
    }

    /** @description A run. */
    public class RunRow {
        /** @description The run id. */
        @AuraEnabled public String runId;
        /** @description The data set. */
        @AuraEnabled public String setTitle;
        /** @description The data set record. */
        @AuraEnabled public Id dataSetId;
        /** @description Up, Down or Refill. */
        @AuraEnabled public String direction;
        /** @description Source → target, by name. */
        @AuraEnabled public String route;
        /** @description Source org record. */
        @AuraEnabled public Id sourceOrgId;
        /** @description The run's status. */
        @AuraEnabled public String status;
        /** @description Who started it. */
        @AuraEnabled public String requestedBy;
        /** @description Who started it (record). */
        @AuraEnabled public Id requestedById;
        /** @description Who allowed the load. */
        @AuraEnabled public String approvedBy;
        /** @description Totals JSON. */
        @AuraEnabled public String counts;
        /** @description Why blocked or failed. */
        @AuraEnabled public String message;
        /** @description The pipeline run. */
        @AuraEnabled public String runUrl;
        /** @description The linked release. */
        @AuraEnabled public String releaseName;
    }

    /**
     * @description The board.
     * @return the board
     */
    public static Board read() {
        Board b = new Board();
        b.isAdmin = RlyOrgController.isAdmin();
        b.isApprover = RlyDataRules.mayLoadUp();
        b.canMoveDown = RlyDataRules.mayMoveDown();
        b.userId = UserInfo.getUserId();
        for (RLY_Data_Set__c s : RlyDataStore.sets()) {
            b.sets.add(setRow(s));
        }
        List<RLY_Data_Run__c> runs = RlyDataStore.runs(50);
        for (RLY_Data_Run__c r : runs) {
            b.runs.add(runRow(r));
        }
        for (RLY_Org__c o : RlyDataStore.orgs()) {
            b.orgs.add(orgRow(o, runs));
        }
        return b;
    }

    private static SetRow setRow(RLY_Data_Set__c s) {
        SetRow r = new SetRow();
        r.id = s.Id;
        r.title = String.isBlank(s.Title__c) ? s.Name : s.Title__c;
        r.description = s.Description__c;
        r.definition = s.Definition__c;
        try {
            r.objectCount = RlyDataSet.parse(s.Definition__c).objects.size();
        } catch (RlyReleaseException e) {
            r.problem = e.getMessage();
        }
        return r;
    }

    // An org can be loaded with a sign-in; refill is due when its last load was into another Org Id.
    private static OrgRow orgRow(RLY_Org__c o, List<RLY_Data_Run__c> runs) {
        OrgRow r = new OrgRow();
        r.id = o.Id;
        r.name = o.Name;
        r.role = o.Role__c;
        r.canLoad = RlySyncRoute.hasSignIn(o);
        for (RLY_Data_Run__c run : runs) {
            if (run.Target_Org__c == o.Id && run.Status__c == RlyDataStore.LOADED) {
                r.lastRunId = run.Run_Id__c;
                r.refillDue = String.isNotBlank(o.Org_Id__c) && String.isNotBlank(run.Target_Org_Id__c) && o.Org_Id__c != run.Target_Org_Id__c;
                break;
            }
        }
        return r;
    }

    private static RunRow runRow(RLY_Data_Run__c run) {
        RunRow r = new RunRow();
        r.runId = run.Run_Id__c;
        r.setTitle = run.Data_Set__r == null ? null : run.Data_Set__r.Title__c;
        r.dataSetId = run.Data_Set__c;
        r.direction = run.Direction__c;
        r.route = (run.Source_Org__r == null ? '?' : run.Source_Org__r.Name) + ' → ' + (run.Target_Org__r == null ? '?' : run.Target_Org__r.Name);
        r.sourceOrgId = run.Source_Org__c;
        r.status = run.Status__c;
        r.requestedBy = run.Requested_By__r == null ? null : run.Requested_By__r.Name;
        r.requestedById = run.Requested_By__c;
        r.approvedBy = run.Approved_By__r == null ? null : run.Approved_By__r.Name;
        r.counts = run.Counts__c;
        r.message = run.Message__c;
        r.runUrl = run.Run_Url__c;
        r.releaseName = run.Release__r == null ? null : run.Release__r.Name;
        return r;
    }
}
