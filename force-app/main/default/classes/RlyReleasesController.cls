/**
 * @description Releases and Approvals tabs, and the last step of New Release (raising it). The Releases tab filters on
 * the server (listReleasesFor, countReleases); the Approvals tab uses listReleases. A release page asks for its
 * latest status every few seconds while something is running (refreshRelease), which moves it along
 * (RlyStatusReader.advance).
 */
public with sharing class RlyReleasesController {

    /** @description What a list row says about a release's kind (Row extends it). */
    public virtual class RowKind {
        /** @description A hotfix. */
        @AuraEnabled public Boolean isHotfix;
        /** @description Why it's a hotfix, or null. */
        @AuraEnabled public String hotfixReason;
        /** @description Release, Promotion or Back_Promote. */
        @AuraEnabled public String releaseType;
        /** @description For a promotion: the release numbers it carries. */
        @AuraEnabled public List<String> carried = new List<String>();
        /** @description Number of components it deletes. */
        @AuraEnabled public Integer deletionCount;
        /** @description Manual steps of its deploy still to do. */
        @AuraEnabled public Integer manualOpen = 0;
        /** @description It has only manual steps (no metadata, no Git or pipeline steps). */
        @AuraEnabled public Boolean manualOnly;
        /** @description Its latest rollback: Running, Rolled_Back, Failed, or null. */
        @AuraEnabled public String rollbackStatus;
        /** @description The org it was rolled back in, or null. */
        @AuraEnabled public String rolledBackIn;
        /** @description Who rolled it back, or null. */
        @AuraEnabled public String rolledBackBy;
        /** @description When it was rolled back, or null. */
        @AuraEnabled public Datetime rolledBackOn;
    }

    /** @description One row of the release list. */
    public class Row extends RowKind {
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
        /** @description A hotfix (same as isHotfix; kept for older pages). */
        @AuraEnabled public Boolean hotfix;
        /** @description The user who raised it. */
        @AuraEnabled public Id raisedById;
        /** @description When its status was last read, or null. */
        @AuraEnabled public Datetime lastChecked;
    }

    /** @description A release a promotion carries. */
    public class CarriedRelease {
        /** @description The release. */
        @AuraEnabled public Id id;
        /** @description Its number. */
        @AuraEnabled public String name;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description A hotfix. */
        @AuraEnabled public Boolean isHotfix;
        /** @description It has only manual steps (no merge commit to carry). */
        @AuraEnabled public Boolean manualOnly;
    }

    /** @description How one branch was brought up to date after the merge. */
    public class BranchSync {
        /** @description The branch. */
        @AuraEnabled public String branch;
        /** @description Synced, Conflict or Missing. */
        @AuraEnabled public String status;
        /** @description What happened. */
        @AuraEnabled public String message;
        /** @description Stage (a stage branch) or Developer (a developer branch). */
        @AuraEnabled public String kind;
    }

    /** @description What a release page shows about its history, flows and approval rule (RlyReleaseHistory fills it). */
    public virtual class DetailHistory {
        /** @description "Needs approval: contains a Flow and a Profile", "Approved automatically: …" or "Always needs approval in …". */
        @AuraEnabled public String approvalReason;
        /** @description Flow activation per org and flow (Flow_Results__c), with each flow's After deploy choice. */
        @AuraEnabled public List<RlyFlowResults.FlowResult> flows = new List<RlyFlowResults.FlowResult>();
        /** @description The release's history, newest first. */
        @AuraEnabled public List<RlyReleaseHistory.EventRow> events = new List<RlyReleaseHistory.EventRow>();
        /** @description The current user may add changes from the developer org now (RlyAppendRules). */
        @AuraEnabled public Boolean canAppend;
        /** @description Open org: the orgs on the release's route with their login addresses (admins and the deployment team only, else empty). */
        @AuraEnabled public List<RlyOrgLinks.OrgLink> orgLinks = new List<RlyOrgLinks.OrgLink>();
    }

    /** @description What a release page shows about the release's links to others (Detail extends it; RlyReleaseLinks fills it). */
    public virtual class DetailLinks extends DetailHistory {
        /** @description A hotfix. */
        @AuraEnabled public Boolean isHotfix;
        /** @description Why it's a hotfix, or null. */
        @AuraEnabled public String hotfixReason;
        /** @description Release, Promotion or Back_Promote. */
        @AuraEnabled public String releaseType;
        /** @description For a promotion: the releases it carries, oldest deploy first. */
        @AuraEnabled public List<CarriedRelease> carried = new List<CarriedRelease>();
        /** @description The promotion carrying this release, or null. */
        @AuraEnabled public String promotedInName;
        /** @description Its Id, or null. */
        @AuraEnabled public Id promotedInId;
        /** @description How the branches were brought up to date after the merge (stage branches, then developer branches). */
        @AuraEnabled public List<BranchSync> backMerge = new List<BranchSync>();
        /** @description After a deploy to the hub: Off, or where its changes were sent (each back promote org). */
        @AuraEnabled public String backPromote;
        /** @description A hotfix with its first approval, waiting for a second approver. */
        @AuraEnabled public Boolean needsSecondApprover;
        /** @description The first approver's name while it waits for the second, or null. */
        @AuraEnabled public String firstApprover;
        /** @description The components it deletes, as Type:Name. */
        @AuraEnabled public List<String> deletions = new List<String>();
        /** @description Manual steps of its deploy into its target still to do. */
        @AuraEnabled public Integer manualOpen = 0;
        /** @description Of those, the ones before deploy (the deploy waits for them). */
        @AuraEnabled public Integer manualBeforeOpen = 0;
        /** @description For example "2 manual steps: 1 before deploy (open), 1 after deploy", or null when there are none. */
        @AuraEnabled public String manualSummary;
        /** @description Its latest rollback and whether the current user may roll it back (RlyRollbackView). */
        @AuraEnabled public RlyRollbackView.View rollbackState;
    }

    /** @description One release, as its page shows it. */
    public class Detail extends DetailLinks {
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
        /** @description The status pill: Resolving conflicts while a resolve run checks it, otherwise the status. */
        @AuraEnabled public String phase;
        /** @description An info line above the timeline, or null. */
        @AuraEnabled public String notice;
        /** @description Link to the release's Slack card, or null. */
        @AuraEnabled public String slackUrl;
        /** @description Where releases into the target org are approved: Salesforce, Slack, or Salesforce or Slack. */
        @AuraEnabled public String approvedIn;
        /** @description The release can be approved here in Salesforce. */
        @AuraEnabled public Boolean approveHere;
        /** @description The release's test classes. */
        @AuraEnabled public List<String> tests;
        /** @description The Git provider's name, for example GitHub. */
        @AuraEnabled public String gitProvider;
        /** @description The Slack channel the release card was posted to, or null. */
        @AuraEnabled public String slackChannel;
    }

    /**
     * @description The release list.
     * @param view mine, all or approvals
     * @return the rows, newest first
     */
    @AuraEnabled
    public static List<Row> listReleases(String view) {
        return RlyReleaseRows.build(RlyReleaseStore.releases(view));
    }

    /**
     * @description The Releases tab's list, filtered on the server.
     * @param filterJson {"raisedById": a user Id or blank for everyone, "state": "open" (default), "deployed", "rolledback",
     * "failed", "closed" or "all", "searchText": part of the release number or title}
     * @return up to 200 rows, newest first (open: hotfixes first)
     */
    @AuraEnabled
    public static List<Row> listReleasesFor(String filterJson) {
        try {
            return RlyReleaseRows.build(RlyReleaseQuery.releasesFor(RlyReleaseQuery.parse(filterJson)));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The counts on the Releases tab's state chips.
     * @param raisedById the user who raised them, or blank for everyone
     * @return the count by state: open, deployed, rolledback, failed, closed and all
     */
    @AuraEnabled
    public static Map<String, Integer> countReleases(String raisedById) {
        try {
            return RlyReleaseQuery.countsFor(raisedById);
        } catch (Exception e) {
            throw handled(e);
        }
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
     * @description Reads the latest status first (callouts), then returns the release. A release with nothing running
     * reads its running rollback (RlyRollbackRun.advance), or else starts or reads the queued and running back promote syncs
     * (RlyBackPromoteRun.catchUp). Reads are shared: a running release read in the last RlySharedRead.FRESH_SECONDS
     * by anyone is returned as saved, without callouts, and a save that meets another viewer's row lock returns the
     * saved release instead of an error (RlySharedRead).
     * @param releaseId the release
     * @return the release
     */
    @AuraEnabled
    public static Detail refreshRelease(Id releaseId) {
        return refreshWithin(releaseId, RlySharedRead.FRESH_SECONDS);
    }

    /**
     * @description The release page's Check now button: as refreshRelease, but reads again unless the last read is
     * RlySharedRead.CHECK_NOW_SECONDS old or less (instead of FRESH_SECONDS).
     * @param releaseId the release
     * @return the release
     */
    @AuraEnabled
    public static Detail checkRelease(Id releaseId) {
        return refreshWithin(releaseId, RlySharedRead.CHECK_NOW_SECONDS);
    }

    private static Detail refreshWithin(Id releaseId, Integer freshFor) {
        try {
            RlySharedRead.refresh(releaseId, freshFor);
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
        d.phase = RlyReleasePhase.phase(d.release);
        d.notice = RlyReleasePhase.notice(d.release);
        d.slackUrl = RlyReleasePhase.slackUrl(d.release);
        d.approvedIn = RlyApprover.approvalIn(d.release.Target_Org__r);
        d.approveHere = RlyApprover.inSalesforce(d.release.Target_Org__r);
        d.tests = RlyReleasePhase.tests(d.release);
        d.gitProvider = RlyGitName.labelFor(RlyReleaseStore.git());
        d.slackChannel = RlyReleasePhase.slackChannel(d.release);
        d.canAppend = RlyAppendRules.mayAppend(d.release);
        d.orgLinks = RlyOrgLinks.forRelease(d.release);
        RlyRollbackView.fill(d);
        RlyReleaseLinks.fill(d);
        RlyReleaseHistory.fill(d);
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
