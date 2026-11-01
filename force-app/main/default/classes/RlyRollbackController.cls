/**
 * @description The release page's Roll back dialog: the orgs the release was deployed to (rollbackChoices), what rolling
 * one back will do (previewRollback, read from the snapshot's manifest) and starting it (startRollback). The page then
 * reads the release again (RlyReleasesController.refreshRelease), which follows the rollback until it ends.
 */
public with sharing class RlyRollbackController {

    /**
     * @description The orgs the release was deployed to, in route order, each with its snapshot or why there's none.
     * @param releaseId the release
     * @return the choices
     */
    @AuraEnabled
    public static List<RlyRollbackPlan.OrgChoice> rollbackChoices(Id releaseId) {
        try {
            return RlyRollbackPlan.choices(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description What rolling one org back will do: restores, removes, Apex and later releases that changed the same components.
     * @param releaseId the release
     * @param orgId the org
     * @return the preview
     */
    @AuraEnabled
    public static RlyRollbackPreview.Preview previewRollback(Id releaseId, Id orgId) {
        try {
            return RlyRollbackPreview.preview(releaseId, orgId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Starts the rollback (Release Relay admins and the deployment team, on the hub).
     * @param releaseId the release
     * @param requestJson {"orgId", "reason", "tests": "release" | "all"}
     */
    @AuraEnabled
    public static void startRollback(Id releaseId, String requestJson) {
        try {
            RlyRollback.Request req = String.isBlank(requestJson) ? new RlyRollback.Request()
                : (RlyRollback.Request) JSON.deserialize(requestJson, RlyRollback.Request.class);
            RlyRollback.start(releaseId, req);
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
