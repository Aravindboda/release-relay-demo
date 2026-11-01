/**
 * @description The Home tab's "Needs you" card (RlyHomeController): one group per role of the viewer, approvals first.
 * Approvers (RlyApprovalService.canApprove): releases ready for approval that the viewer may approve (a hotfix that needs
 * two approvers is left out for whoever raised it and for its first approver, RlyTwoApprovers). Deployment team
 * (RlyManualSteps.canCheck): manual steps still to do, before deploy for approved releases and after deploy for deployed
 * ones. Developers (everyone who raised a release, or has no other role): their releases with a problem (RlyHomeProblems).
 * Releases and manual step runs are shared hub records, read in system mode in the private inner without sharing class; nothing is written.
 */
public with sharing class RlyHomeNeeds {

    /** @description Group key: releases waiting for the viewer's approval. */
    public static final String GROUP_APPROVALS = 'approvals';
    /** @description Group key: manual steps to do. */
    public static final String GROUP_STEPS = 'steps';
    /** @description Group key: the viewer's releases with a problem. */
    public static final String GROUP_MINE = 'mine';

    private static final String TONE_INFO = 'info';
    private static final String TONE_WAIT = 'wait';
    private static final String STATUS_DEPLOYED = 'Deployed';
    /** @description Release statuses whose manual steps the deployment team may be working on. */
    private static final Set<String> STEP_STATUSES = new Set<String>{ 'Ready for approval', 'Approved', 'Merging', 'Merged',
        'Deploying', STATUS_DEPLOYED };

    /** @description What needs the viewer. */
    public class Needs {
        /** @description The viewer's roles, in words: approver, deploy team, developer. */
        @AuraEnabled public List<String> roles = new List<String>();
        /** @description One group per role, approvals first. */
        @AuraEnabled public List<NeedGroup> groups = new List<NeedGroup>();
        /** @description How many releases wait for the viewer's approval. */
        @AuraEnabled public Integer approvalCount = 0;
    }

    /** @description One role's group. */
    public class NeedGroup {
        /** @description approvals, steps or mine. */
        @AuraEnabled public String key;
        /** @description The group heading. */
        @AuraEnabled public String label;
        /** @description The rows. */
        @AuraEnabled public List<NeedRow> rows = new List<NeedRow>();
    }

    /** @description One thing that needs the viewer. */
    public class NeedRow {
        /** @description Unique within the card. */
        @AuraEnabled public String key;
        /** @description The release to open. */
        @AuraEnabled public Id releaseId;
        /** @description The release number. */
        @AuraEnabled public String releaseName;
        /** @description The release title, or the manual step's title. */
        @AuraEnabled public String title;
        /** @description The status pill's text. */
        @AuraEnabled public String pill;
        /** @description Its tone: info, wait or bad (hotfixes: hot). */
        @AuraEnabled public String tone;
        /** @description Where: "DEV1 → SIT" for a release, the org for a manual step. */
        @AuraEnabled public String org;
        /** @description Who raised the release. */
        @AuraEnabled public String raisedBy;
        /** @description Since when it waits. */
        @AuraEnabled public Datetime since;
        /** @description One more line about it, or null. */
        @AuraEnabled public String note;
    }

    /**
     * @description What needs the current user, per role.
     * @return the groups
     */
    public static Needs forViewer() {
        Data store = new Data();
        Needs n = new Needs();
        Boolean approver = RlyApprovalService.canApprove();
        Boolean deployTeam = RlyManualSteps.canCheck();
        Id me = UserInfo.getUserId();
        if (approver) {
            NeedGroup g = approvals(store.readyForApproval(), me);
            n.approvalCount = g.rows.size();
            n.groups.add(g);
            n.roles.add('approver');
        }
        if (deployTeam) {
            n.groups.add(steps(store.openRuns()));
            n.roles.add('deploy team');
        }
        if (!(approver || deployTeam) || store.raisedCount(me) > 0) {
            n.groups.add(RlyHomeProblems.forUser(me));
            n.roles.add('developer');
        }
        return n;
    }

    /**
     * @description An empty group.
     * @param key approvals, steps or mine
     * @param label the heading
     * @return the group
     */
    public static NeedGroup groupOf(String key, String label) {
        NeedGroup g = new NeedGroup();
        g.key = key;
        g.label = label;
        return g;
    }

    /**
     * @description Whether a user may approve a release that's ready: a hotfix that needs two approvers can't be approved
     * by whoever raised it, nor twice by its first approver.
     * @param rel the release, with CreatedById, Approved_By__c, Is_Hotfix__c and Target_Org__r.Hotfix_Two_Approvers__c
     * @param userId the user
     * @return true when the user may approve it
     */
    public static Boolean mayApprove(RLY_Release__c rel, Id userId) {
        if (!RlyTwoApprovers.needsTwo(rel)) {
            return true;
        }
        return rel.CreatedById != userId && !(RlyTwoApprovers.waitsForSecond(rel) && rel.Approved_By__c == userId);
    }

    private static NeedGroup approvals(List<RLY_Release__c> ready, Id me) {
        NeedGroup g = groupOf(GROUP_APPROVALS, 'Waiting for your approval');
        for (RLY_Release__c r : ready) {
            if (mayApprove(r, me)) {
                NeedRow row = releaseRow(r);
                approvalPill(row, r);
                g.rows.add(row);
            }
        }
        return g;
    }

    private static void approvalPill(NeedRow row, RLY_Release__c r) {
        row.pill = 'Ready';
        row.tone = TONE_INFO;
        if (RlyTwoApprovers.waitsForSecond(r)) {
            row.pill = '2nd approver';
            row.note = 'Approved by ' + (r.Approved_By__r == null ? 'an approver' : r.Approved_By__r.Name)
                + '. Waiting for a second approver.';
        } else if (RlyHotfix.isHotfix(r)) {
            row.pill = 'Hotfix';
            row.tone = 'hot';
            row.note = r.Hotfix_Reason__c;
        } else if (RlyPromotion.typeOf(r) == RlyPromotion.TYPE_PROMOTION) {
            row.pill = 'Promotion';
        }
    }

    /**
     * @description A release as a row: number, title, "source → target", who raised it, last change.
     * @param r the release, with Source_Org__r.Name, Target_Org__r.Name, CreatedBy.Name and LastModifiedDate
     * @return the row (no pill yet)
     */
    public static NeedRow releaseRow(RLY_Release__c r) {
        NeedRow row = new NeedRow();
        row.key = r.Id;
        row.releaseId = r.Id;
        row.releaseName = r.Name;
        row.title = r.Title__c;
        String target = r.Target_Org__r == null ? '' : r.Target_Org__r.Name;
        row.org = r.Source_Org__r == null ? target : r.Source_Org__r.Name + ' → ' + target;
        row.raisedBy = r.CreatedBy == null ? null : r.CreatedBy.Name;
        row.since = r.LastModifiedDate;
        return row;
    }

    // Before deploy steps count until the release is deployed; after deploy steps once it is.
    private static NeedGroup steps(List<RLY_Manual_Step_Run__c> runs) {
        NeedGroup g = groupOf(GROUP_STEPS, 'Manual steps to do');
        for (RLY_Manual_Step_Run__c run : runs) {
            Boolean beforeDeploy = run.Step__r.Timing__c == RlyManualSteps.TIMING_BEFORE;
            Boolean deployed = run.Release__r.Status__c == STATUS_DEPLOYED;
            if (beforeDeploy != deployed) {
                g.rows.add(stepRow(run));
            }
        }
        return g;
    }

    private static NeedRow stepRow(RLY_Manual_Step_Run__c run) {
        Boolean beforeDeploy = run.Step__r.Timing__c == RlyManualSteps.TIMING_BEFORE;
        NeedRow row = new NeedRow();
        row.key = run.Id;
        row.releaseId = run.Release__c;
        row.releaseName = run.Release__r.Name;
        row.title = run.Step__r.Title__c;
        row.pill = beforeDeploy ? 'Before deploy' : 'After deploy';
        row.tone = beforeDeploy ? TONE_WAIT : TONE_INFO;
        row.org = run.Org__r == null ? null : run.Org__r.Name;
        row.raisedBy = run.Release__r.CreatedBy == null ? null : run.Release__r.CreatedBy.Name;
        row.since = run.CreatedDate;
        row.note = beforeDeploy ? 'Blocks the deploy' : 'Deployed';
        return row;
    }

    /** @description Shared hub releases and manual step runs, read in system mode. */
    private without sharing class Data {

        /**
         * @description Releases ready for approval, hotfixes first, then oldest first.
         * @return up to 200 releases
         */
        public List<RLY_Release__c> readyForApproval() {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, Target_Org__r.Hotfix_Two_Approvers__c,
                           CreatedById, CreatedBy.Name, LastModifiedDate, Is_Hotfix__c, Hotfix_Reason__c, Release_Type__c,
                           Approved_By__c, Approved_By__r.Name, Approval_Status__c
                    FROM RLY_Release__c WHERE Status__c = 'Ready for approval'
                    WITH SYSTEM_MODE ORDER BY Is_Hotfix__c DESC, CreatedDate ASC LIMIT 200];
        }

        /**
         * @description Manual step runs still to do, of releases on their way or deployed.
         * @return up to 200 runs, oldest first
         */
        public List<RLY_Manual_Step_Run__c> openRuns() {
            return [SELECT Id, Release__c, Release__r.Name, Release__r.Status__c, Release__r.CreatedBy.Name, Step__r.Title__c,
                           Step__r.Timing__c, Org__r.Name, CreatedDate
                    FROM RLY_Manual_Step_Run__c WHERE Status__c = 'To_Do' AND Release__r.Status__c IN :STEP_STATUSES
                    WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 200];
        }

        /**
         * @description How many releases a user raised (at most 1 is counted).
         * @param userId the user
         * @return 0 or 1
         */
        public Integer raisedCount(Id userId) {
            return [SELECT COUNT() FROM RLY_Release__c WHERE CreatedById = :userId WITH SYSTEM_MODE LIMIT 1];
        }
    }
}
