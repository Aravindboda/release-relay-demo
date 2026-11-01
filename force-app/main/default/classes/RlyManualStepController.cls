/**
 * @description The release page's Manual steps card (rlyManualSteps) and the Promote tab's carried steps: read a release's
 * steps and runs per org (getSteps), add, change or delete its steps (saveStep, deleteStep: who raised it, or an admin,
 * until it is first deployed) and check runs off (markRun: the deployment team or admins; the last Before deploy step
 * of an approved release starts its deploy).
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
        try {
            return RlyManualStepBoard.build(RlyManualStepCheck.mark(RlyManualStepCheck.parse(runJson)));
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
