/**
 * @description The release page's Manual steps card (rlyManualSteps) and the Promote tab's carried steps: read a release's
 * steps and runs per org (getSteps), add, change or delete its steps (saveStep, deleteStep: who raised it, or an admin,
 * until it is first deployed) and check runs off (markRun: the deployment team or admins; the last Before deploy step
 * of an approved release starts its deploy). Files on steps and proof on runs (RlyStepFiles): removeFile, logDownload,
 * and on New Release draftFiles and removeDraftFile; uploads go straight to Salesforce Files (lightning-file-upload).
 */
public with sharing class RlyManualStepController {

    /**
     * @description A release's manual steps and their runs per org.
     * @param releaseId the release
     * @return the board
     */
    @AuraEnabled
    public static RlyManualSteps.StepBoard getSteps(Id releaseId) {
        try {
            return RlyManualStepBoard.build(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Adds or changes a manual step; the release's runs in its current target follow.
     * @param stepJson {id (blank for a new step), releaseId, title, instructions, category, timing, sequence, backPromote, orgScope}
     * @return the release's board
     */
    @AuraEnabled
    public static RlyManualSteps.StepBoard saveStep(String stepJson) {
        try {
            return RlyManualStepBoard.build(RlyManualStepEdit.save(RlyManualStepEdit.parse(stepJson)));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Deletes a manual step and its runs.
     * @param stepId the step
     * @return the board of the release it belonged to
     */
    @AuraEnabled
    public static RlyManualSteps.StepBoard deleteStep(Id stepId) {
        try {
            return RlyManualStepBoard.build(RlyManualStepEdit.remove(stepId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Checks a manual step off in one org (deployment team or admins).
     * @param runJson {runId, status: Done | Not_Needed | To_Do, note (required for Not_Needed), releaseId (the page's release)}
     * @return the board of releaseId (or of the run's release)
     */
    @AuraEnabled
    public static RlyManualSteps.StepBoard markRun(String runJson) {
        RlyHubGuard.requireHub();
        try {
            return RlyManualStepBoard.build(RlyManualStepCheck.mark(RlyManualStepCheck.parse(runJson)));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Removes a file from a step (the raiser or an admin, before approval) or a run's proof (the person who
     * added it, or an admin); the file is deleted too when the current user owns it and nothing else holds it.
     * @param recordId the step or run
     * @param contentDocumentId the file
     * @param releaseId the release whose page sent it
     * @return that release's board
     */
    @AuraEnabled
    public static RlyManualSteps.StepBoard removeFile(Id recordId, Id contentDocumentId, Id releaseId) {
        RlyHubGuard.requireHub();
        try {
            RlyStepFileActions.remove(recordId, contentDocumentId);
            return RlyManualStepBoard.build(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Writes "Downloaded <file>" to the release's History and returns where the file downloads.
     * @param contentDocumentId the file
     * @param releaseId the release whose page it was downloaded from
     * @param orgId the org tab, or null
     * @return the download address
     */
    @AuraEnabled
    public static String logDownload(Id contentDocumentId, Id releaseId, Id orgId) {
        try {
            return RlyStepFileActions.logDownload(contentDocumentId, releaseId, orgId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description New Release: the draft files the current user uploaded for its steps.
     * @param contentDocumentIds the files
     * @return the rows (only the current user's own files)
     */
    @AuraEnabled
    public static List<RlyStepFiles.FileRow> draftFiles(List<Id> contentDocumentIds) {
        try {
            return RlyStepFileDrafts.draftFiles(contentDocumentIds);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description New Release: deletes a draft file the current user uploaded (not yet on a saved step).
     * @param contentDocumentId the file
     * @return true when deleted
     */
    @AuraEnabled
    public static Boolean removeDraftFile(Id contentDocumentId) {
        try {
            RlyStepFileDrafts.removeDraft(contentDocumentId);
            return true;
        } catch (Exception e) {
            throw handled(e);
        }
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
