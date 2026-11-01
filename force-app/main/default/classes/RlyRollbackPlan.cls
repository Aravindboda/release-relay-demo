/**
 * @description What a rollback of a release can do: the orgs it was deployed to (by itself, or by the promotions that
 * carried it on, in route order), each with the snapshot the pipeline took just before that deploy (deploy.json
 * "snapshot", kept in Deploy_Result__c) or why there is none. RlyRollbackPreview reads what one org's rollback does.
 * Releases and orgs are shared hub records: read in system mode, in the private inner without sharing class.
 */
public with sharing class RlyRollbackPlan {

    /** @description The branch the pipeline keeps the snapshots on. */
    public static final String SNAPSHOT_BRANCH = 'release-relay-snapshots';

    private static final String DEPLOYING = 'Deploying';
    private static final Integer MAX_HOPS = 6;

    /** @description One org the release was deployed to: a chip in the confirm dialog. */
    public class OrgChoice {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description Its name. */
        @AuraEnabled public String orgName;
        /** @description Its Git environment (the pipeline's TARGET_ENVIRONMENT). */
        @AuraEnabled public String environment;
        /** @description Its branch. */
        @AuraEnabled public String branch;
        /** @description Production (the hub, or an org registered as Production): tests run there. */
        @AuraEnabled public Boolean production;
        /** @description When the deploy finished. */
        @AuraEnabled public Datetime deployedOn;
        /** @description The release (or promotion) whose deploy took the snapshot. */
        @AuraEnabled public Id ownerId;
        /** @description Its number: the request the rollback runs as. */
        @AuraEnabled public String ownerName;
        /** @description The snapshot was taken by a promotion that carried this release (and maybe others). */
        @AuraEnabled public Boolean byPromotion;
        /** @description The snapshot's folder on the snapshots branch, or null. */
        @AuraEnabled public String snapshotPath;
        /** @description There is a snapshot to roll back to. */
        @AuraEnabled public Boolean hasSnapshot;
        /** @description Why there is no snapshot, or null. */
        @AuraEnabled public String why;
        /** @description The owner's tests (run in production with "This release's tests"). */
        @AuraEnabled public List<String> tests = new List<String>();
        /** @description A deploy into this org is running for the owner: it can't be rolled back now. */
        @AuraEnabled public Boolean busy;
        /** @description When the owner was approved (later releases are those approved after it). */
        public Datetime approvedOn;
    }

    /**
     * @description The orgs a release was deployed to, in route order (its own target first, then each promotion's).
     * @param releaseId the release
     * @return the choices (empty when it was never deployed)
     */
    public static List<OrgChoice> choices(Id releaseId) {
        List<OrgChoice> out = new List<OrgChoice>();
        SystemAccess access = new SystemAccess();
        RLY_Release__c current = access.readRelease(releaseId);
        Integer hops = 0;
        while (current != null && hops < MAX_HOPS) {
            if (current.Status__c == 'Deployed' || current.Status__c == DEPLOYING) {
                out.add(choiceOf(current, releaseId));
            }
            current = current.Promoted_In__c == null ? null : access.readRelease(current.Promoted_In__c);
            hops++;
        }
        return out;
    }

    /**
     * @description The choice for one org, or an error when the release was never deployed there with a snapshot.
     * @param releaseId the release
     * @param orgId the org
     * @return the choice
     */
    public static OrgChoice choiceFor(Id releaseId, Id orgId) {
        for (OrgChoice c : choices(releaseId)) {
            if (c.orgId == orgId) {
                return c;
            }
        }
        throw new RlyReleaseException('This release wasn\'t deployed to that org.');
    }

    // One deploy: the owner's target org and the snapshot its deploy.json recorded.
    private static OrgChoice choiceOf(RLY_Release__c owner, Id releaseId) {
        OrgChoice c = new OrgChoice();
        RLY_Org__c org = owner.Target_Org__r;
        c.orgId = owner.Target_Org__c;
        c.orgName = org == null ? '' : org.Name;
        c.environment = org == null ? null : org.Git_Environment__c;
        c.branch = org == null || String.isBlank(org.Branch__c) ? owner.Target_Branch__c : org.Branch__c;
        c.production = org != null && (org.Role__c == 'Hub' || org.Environment__c == 'Production');
        c.ownerId = owner.Id;
        c.ownerName = owner.Name;
        c.byPromotion = owner.Id != releaseId;
        c.tests = RlyReleasePhase.tests(owner);
        c.busy = owner.Status__c == DEPLOYING;
        c.approvedOn = owner.Approved_On__c;
        Map<String, Object> deploy = RlyEvidenceText.parse(owner.Deploy_Result__c);
        c.deployedOn = toTime(deploy.get('finishedAt'));
        snapshotOf(c, deploy.get('snapshot'));
        if (c.busy) {
            c.hasSnapshot = false;
            c.why = 'Deploying now';
        } else if (String.isBlank(c.environment) && c.hasSnapshot) {
            c.hasSnapshot = false;
            c.why = 'No Git environment';
        }
        return c;
    }

    private static void snapshotOf(OrgChoice c, Object raw) {
        Map<String, Object> snap = raw instanceof Map<String, Object> ? (Map<String, Object>) raw : new Map<String, Object>();
        c.snapshotPath = RlyEvidenceText.str(snap.get('path'));
        c.hasSnapshot = c.snapshotPath != null;
        if (!c.hasSnapshot) {
            c.why = snap.get('error') != null ? 'Snapshot failed' : 'No snapshot';
        }
    }

    /**
     * @description An ISO date and time from a result file.
     * @param value the value, for example 2026-11-01T09:12:00.000Z
     * @return the time, or null
     */
    public static Datetime toTime(Object value) {
        String text = RlyEvidenceText.str(value);
        if (text == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    /** @description Shared hub releases and their components, read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description A release with what a rollback choice needs.
         * @param releaseId the release
         * @return the release, or null
         */
        public RLY_Release__c readRelease(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Id, Name, Status__c, Release_Type__c, Promoted_In__c, Target_Org__c, Target_Branch__c,
                    Target_Org__r.Name, Target_Org__r.Role__c, Target_Org__r.Environment__c, Target_Org__r.Git_Environment__c,
                    Target_Org__r.Branch__c, Deploy_Result__c, Test_Classes__c, Approved_On__c
                FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
