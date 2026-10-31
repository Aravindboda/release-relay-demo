/**
 * @description Releases and Approvals tabs, and the last step of New Release (raising it). A release page asks for its
 * latest status every few seconds while something is running (refreshRelease), which moves it along
 * (RlyStatusReader.advance).
 */
public with sharing class RlyReleasesController {

    /** @description One row of the release list. */
    public class Row {
        /** @description Release Id. */
        @AuraEnabled public Id id;
        /** @description Release number. */
        @AuraEnabled public String name;
        /** @description Title. */
        @AuraEnabled public String title;
        /** @description Status. */
        @AuraEnabled public String status;
        /** @description Developer org. */
        @AuraEnabled public String source;
        /** @description Target org and branch. */
        @AuraEnabled public String target;
        /** @description Who raised it. */
        @AuraEnabled public String raisedBy;
        /** @description When it was raised. */
        @AuraEnabled public Datetime raisedOn;
        /** @description Number of components. */
        @AuraEnabled public Decimal components;
        /** @description Code scan status. */
        @AuraEnabled public String scan;
        /** @description Validation status. */
        @AuraEnabled public String validation;
        /** @description A hotfix raised from a stage org. */
        @AuraEnabled public Boolean hotfix;
    }

    /** @description One release, as its page shows it. */
    public class Detail {
        /** @description The release. */
        @AuraEnabled public RLY_Release__c release;
        /** @description Its components. */
        @AuraEnabled public List<RLY_Release_Item__c> items;
        /** @description The current user approves releases. */
        @AuraEnabled public Boolean isApprover;
        /** @description Something is running: the page keeps checking. */
        @AuraEnabled public Boolean running;
        /** @description Developer org name. */
        @AuraEnabled public String sourceName;
        /** @description Target org name. */
        @AuraEnabled public String targetName;
        /** @description The current user may resolve conflicts (raised it, or approves releases). */
        @AuraEnabled public Boolean canResolve;
        /** @description A hotfix raised from a stage org. */
        @AuraEnabled public Boolean hotfix;
    }

    /**
     * @description The release list.
     * @param view mine, all or approvals
     * @return the rows, newest first
     */
    @AuraEnabled
    public static List<Row> listReleases(String view) {
        List<Row> out = new List<Row>();
        for (RLY_Release__c r : RlyReleaseStore.releases(view)) {
            out.add(toRow(r));
        }
        return out;
    }

    private static Row toRow(RLY_Release__c r) {
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
        row.hotfix = RlyHotfix.isHotfix(r);
        return row;
    }

    /**
     * @description Whether the current user approves releases.
     * @return true for approvers and admins
     */
    @AuraEnabled
    public static Boolean isApprover() {
        return RlyApprovalService.canApprove();
    }

    /**
     * @description The release as it is now, without reading its latest status.
     * @param releaseId the release
     * @return the release
     */
    @AuraEnabled
    public static Detail getRelease(Id releaseId) {
        try {
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Reads the latest status first (callouts), then returns the release.
     * @param releaseId the release
     * @return the release
     */
    @AuraEnabled
    public static Detail refreshRelease(Id releaseId) {
        try {
            RlyStatusReader.advance(releaseId);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Raises the release: starts the retrieve in the developer org and saves it.
     * @param requestJson a RlyRaiseService.RaiseRequest as JSON
     * @return the release Id
     */
    @AuraEnabled
    public static Id raiseRelease(String requestJson) {
        try {
            RlyRaiseService.RaiseRequest req = (RlyRaiseService.RaiseRequest) JSON.deserialize(requestJson, RlyRaiseService.RaiseRequest.class);
            return RlyRaiseService.raise(req);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description An approver accepts a blocking code scan's findings.
     * @param releaseId the release
     * @param reason why the findings are accepted
     * @return the release
     */
    @AuraEnabled
    public static Detail bypassScan(Id releaseId, String reason) {
        try {
            RlyApprovalService.acceptScanFindings(releaseId, reason);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Runs the code scan and validation again.
     * @param releaseId the release
     * @return the release
     */
    @AuraEnabled
    public static Detail checkAgain(Id releaseId) {
        try {
            RlyApprovalService.rerunChecks(releaseId);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Approves the release: merge and deploy.
     * @param releaseId the release
     * @param comment the approver's comment
     * @return the release
     */
    @AuraEnabled
    public static Detail approve(Id releaseId, String comment) {
        try {
            RlyApprovalService.approveRelease(releaseId, comment);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Rejects the release with a comment.
     * @param releaseId the release
     * @param comment why it's rejected
     * @return the release
     */
    @AuraEnabled
    public static Detail reject(Id releaseId, String comment) {
        try {
            RlyApprovalService.rejectRelease(releaseId, comment);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Resolves the release's conflicts with its target and checks it again (mode resolve).
     * @param releaseId the release
     * @param resolutionsJson {"resolutions":[{"file","choice":"mine"|"theirs"|"edit","content" (edit only)}]}
     * @return the release
     */
    @AuraEnabled
    public static Detail resolveConflicts(Id releaseId, String resolutionsJson) {
        try {
            RlyConflictService.commitResolutions(releaseId, resolutionsJson);
            return detail(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Detail detail(Id releaseId) {
        Detail d = new Detail();
        d.release = RlyReleaseStore.release(releaseId);
        if (d.release == null) {
            throw new RlyReleaseException('Release not found.');
        }
        d.items = RlyReleaseStore.items(releaseId);
        d.isApprover = RlyApprovalService.canApprove();
        d.running = RlyStatusReader.OPEN_STATUSES.contains(d.release.Status__c);
        d.sourceName = d.release.Source_Org__r.Name;
        d.targetName = d.release.Target_Org__r.Name;
        d.canResolve = RlyConflictService.mayResolve(d.release);
        d.hotfix = RlyHotfix.isHotfix(d.release);
        return d;
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
