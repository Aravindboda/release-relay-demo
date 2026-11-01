/**
 * @description New Release in append mode (Add changes from the developer org, on an open release's page): what the
 * release has already, and adding the picked changes to it (RlyAppendService).
 */
public with sharing class RlyAppendController {

    /**
     * @description The release to add to: its developer org, target and what's in it already.
     * @param releaseId the release
     * @return the start
     */
    @AuraEnabled
    public static RlyAppendService.AppendStart getAppend(Id releaseId) {
        try {
            return RlyAppendService.start(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Adds the picked changes to the release: starts their retrieve and saves the release waiting for it.
     * @param requestJson a RlyAppendService.AppendRequest as JSON
     * @return the release Id
     */
    @AuraEnabled
    public static Id appendChanges(String requestJson) {
        try {
            RlyAppendService.AppendRequest req = (RlyAppendService.AppendRequest) JSON.deserialize(requestJson, RlyAppendService.AppendRequest.class);
            return RlyAppendService.append(req);
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
