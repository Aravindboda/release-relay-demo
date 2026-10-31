/**
 * Releases and Approvals in the hub. A release page asks for its latest status every few
 * seconds while something is running (refresh), which moves it along (RlyReleaseFlow.advance).
 */
public with sharing class RlyReleasesController {

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String source;
        @AuraEnabled public String target;
        @AuraEnabled public String raisedBy;
        @AuraEnabled public Datetime raisedOn;
        @AuraEnabled public Decimal components;
        @AuraEnabled public String scan;
        @AuraEnabled public String validation;
    }

    public class Detail {
        @AuraEnabled public RLY_Release__c release;
        @AuraEnabled public List<RLY_Release_Item__c> items;
        @AuraEnabled public Boolean isApprover;
        @AuraEnabled public Boolean running;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String targetName;
    }

    /** view: mine, all or approvals. */
    @AuraEnabled
    public static List<Row> listReleases(String view) {
        List<Row> out = new List<Row>();
        for (RLY_Release__c r : new Data().releases(view)) {
            Row row = new Row();
            row.id = r.Id;
            row.name = r.Name;
            row.title = r.Title__c;
            row.status = r.Status__c;
            row.source = r.Source_Org__r.Name;
            row.target = r.Target_Org__r.Name + ' · ' + r.Target_Branch__c;
            row.raisedBy = r.CreatedBy.Name;
            row.raisedOn = r.CreatedDate;
            row.components = r.Component_Count__c;
            row.scan = r.Scan_Status__c;
            row.validation = r.Validation_Status__c;
            out.add(row);
        }
        return out;
    }

    @AuraEnabled
    public static Boolean isApprover() {
        return RlyReleaseFlow.isApprover();
    }

    /** The release as it is now; refresh = true reads the latest status first (callouts). */
    @AuraEnabled
    public static Detail getRelease(Id releaseId, Boolean refresh) {
        try {
            if (refresh == true) {
                RlyReleaseFlow.advance(releaseId);
            }
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static Detail bypassScan(Id releaseId, String reason) {
        try {
            RlyReleaseFlow.bypassScan(releaseId, reason);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static Detail checkAgain(Id releaseId) {
        try {
            RlyReleaseFlow.checkAgain(releaseId);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static Detail approve(Id releaseId, String comment) {
        try {
            RlyReleaseFlow.approve(releaseId, comment);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static Detail reject(Id releaseId, String comment) {
        try {
            RlyReleaseFlow.reject(releaseId, comment);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Detail detail(Id releaseId) {
        Data data = new Data();
        Detail d = new Detail();
        d.release = data.release(releaseId);
        if (d.release == null) {
            throw new RlyReleaseFlow.FlowException('Release not found.');
        }
        d.items = data.items(releaseId);
        d.isApprover = RlyReleaseFlow.isApprover();
        d.running = RlyReleaseFlow.OPEN_STATUSES.contains(d.release.Status__c);
        d.sourceName = d.release.Source_Org__r.Name;
        d.targetName = d.release.Target_Org__r.Name;
        return d;
    }

    private static AuraHandledException handled(Exception e) {
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }

    /** Releases are shared hub records. */
    private without sharing class Data {
        public List<RLY_Release__c> releases(String view) {
            Id me = UserInfo.getUserId();
            if (view == 'approvals') {
                return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                               CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                        FROM RLY_Release__c WHERE Source_Org__c != null AND Status__c IN ('Ready for approval', 'Checks failed')
                        ORDER BY CreatedDate DESC LIMIT 200];
            }
            if (view == 'all') {
                return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                               CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                        FROM RLY_Release__c WHERE Source_Org__c != null ORDER BY CreatedDate DESC LIMIT 200];
            }
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :me ORDER BY CreatedDate DESC LIMIT 200];
        }
        public RLY_Release__c release(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Id, Name, Title__c, Description__c, Status__c, Source_Org__c, Source_Org__r.Name,
                    Target_Org__c, Target_Org__r.Name, Source_Branch__c, Target_Branch__c, Target_Environment__c, PR_Number__c, PR_URL__c,
                    Run_URL__c, Pending_Run__c, Last_Synced__c, Error_Message__c, Component_Count__c, Test_Classes__c,
                    Scan_Status__c, Scan_Violations__c, Scan_Blocking__c, Scan_Result__c, Scan_Bypassed_By__r.Name, Scan_Bypass_Reason__c,
                    Validation_Status__c, Validation_Result__c, Approval_Status__c, Approved_By__r.Name, Approved_On__c, Approval_Comment__c,
                    Merge_Commit__c, Deploy_Status__c, Deploy_Result__c, CreatedDate, CreatedBy.Name
                FROM RLY_Release__c WHERE Id = :releaseId];
            return rows.isEmpty() ? null : rows[0];
        }
        public List<RLY_Release_Item__c> items(Id releaseId) {
            return [SELECT Id, Metadata_Type__c, Component_Name__c FROM RLY_Release_Item__c
                    WHERE Release__c = :releaseId ORDER BY Metadata_Type__c, Component_Name__c LIMIT 5000];
        }
    }
}
