/**
 * @description New Release step 2 in parts, so no call grows with the org or the repository (build 36). The page runs
 * the parts a few at a time, tries a failed part again on its own and lists any part that still fails:
 *   listTrackedPage   source tracking, one page per call (cursor: the next page's address)
 *   listFolderPage    a folder type, FOLDERS_PER_CALL folders per call (cursor: the next folder's position)
 *   listFieldPage     custom fields through the Tooling API, one page per call (when listMetadata of CustomField fails)
 *   deletionPlan      Find deleted components: the parts of the org's branch
 *   branchPlan        Delete from the branch (build 37.1): the parts of the target's branch
 *   deletionPart      the components in one part of the branch
 *   presentNames      every component of one type in the org (listMetadata)
 *   presentFields     one page of the org's custom fields through the Tooling API
 * Callouts only, no DML.
 */
public with sharing class RlyChangePartsController {

    /**
     * @description One page of source tracking changes.
     * @param orgId the developer org
     * @param sinceIso the earliest change (ISO), or blank for any time
     * @param cursor the page to read, or blank for the first
     * @return the page
     */
    @AuraEnabled
    public static RlyChangePages.ChangePage listTrackedPage(Id orgId, String sinceIso, String cursor) {
        try {
            return RlyChangePages.tracked(new RlyChangePages.Ask(RlyChangesController.source(orgId), RlyChangesController.since(sinceIso), cursor));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description The changes in one run of folders of a folder type.
     * @param orgId the developer org
     * @param type a folder-based type such as Report
     * @param pageJson {sinceIso, cursor}: the earliest change (blank: any time) and the first folder's position (blank: 0)
     * @return the page
     */
    @AuraEnabled
    public static RlyChangePages.ChangePage listFolderPage(Id orgId, String type, String pageJson) {
        try {
            Map<String, Object> asked = String.isBlank(pageJson) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(pageJson);
            String sinceIso = asked.get('sinceIso') == null ? null : String.valueOf(asked.get('sinceIso'));
            String cursor = asked.get('cursor') == null ? null : String.valueOf(asked.get('cursor'));
            return RlyChangePages.folders(new RlyChangePages.Ask(RlyChangesController.source(orgId), RlyChangesController.since(sinceIso), cursor), type);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description One page of custom field changes through the Tooling API.
     * @param orgId the developer org
     * @param sinceIso the earliest change (ISO), or blank for any time
     * @param cursor the page to read, or blank for the first
     * @return the page
     */
    @AuraEnabled
    public static RlyChangePages.ChangePage listFieldPage(Id orgId, String sinceIso, String cursor) {
        try {
            return RlyChangePages.fields(new RlyChangePages.Ask(RlyChangesController.source(orgId), RlyChangesController.since(sinceIso), cursor));
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Delete from the branch: the parts of the target's branch (the first stage's, or another route
     * branch asked for), with the developer org's folder rules.
     * @param orgId the developer org
     * @param targetBranch the target's branch (blank: the first stage's)
     * @return the plan
     */
    @AuraEnabled
    public static RlyDeletionPlan.Plan branchPlan(Id orgId, String targetBranch) {
        try {
            RLY_Org__c source = RlyChangesController.source(orgId);
            RLY_Org__c target = RlyCompareTarget.of(source, targetBranch);
            return RlyDeletionPlan.buildFor(source, target.Branch__c.trim());
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Delete from the branch: the components in one part of the branch (one part per request).
     * @param orgId the developer org
     * @param partJson the part, as the plan gave it
     * @return the components on the branch
     */
    @AuraEnabled
    public static RlyDeletionPlan.PartResult deletionPart(Id orgId, String partJson) {
        try {
            RlyChangesController.source(orgId);
            RlyDeletionPlan.Part part = String.isBlank(partJson) ? null : (RlyDeletionPlan.Part) JSON.deserialize(partJson, RlyDeletionPlan.Part.class);
            return RlyDeletionPlan.readPart(part);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Delete from the branch: every component of one type in the org.
     * @param orgId the developer org
     * @param type the metadata type
     * @return the names, lower case
     */
    @AuraEnabled
    public static RlyDeletionPresence.Presence presentNames(Id orgId, String type) {
        try {
            return RlyDeletionPresence.names(RlyChangesController.source(orgId), type);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Find deleted components: one page of the org's custom fields through the Tooling API.
     * @param orgId the developer org
     * @param cursor the page to read, or blank for the first
     * @return the names and the next page's cursor
     */
    @AuraEnabled
    public static RlyDeletionPresence.Presence presentFields(Id orgId, String cursor) {
        try {
            return RlyDeletionPresence.fields(RlyChangesController.source(orgId), cursor);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }
}
