/**
 * @description Resolves a release's conflicts with its target: the hub commits the choices
 * (.relay-inbox/REL-xxxxx-resolve.json) to the release branch and starts the pipeline in mode resolve, which
 * applies them and runs the code scan and the merged validation again. Allowed for approvers and for the user who
 * raised the release. Callouts come first and the one save last.
 */
public with sharing class RlyConflictService {

    /**
     * @description Whether the current user may resolve the release's conflicts.
     * @param rel the release, with CreatedById
     * @return true for approvers and for whoever raised it
     */
    public static Boolean mayResolve(RLY_Release__c rel) {
        return rel != null && (rel.CreatedById == UserInfo.getUserId() || RlyApprovalService.canApprove());
    }

    /**
     * @description Commits the resolutions and checks the release again (mode resolve).
     * @param releaseId the release
     * @param requestJson a RlyConflictRules.ResolveRequest as JSON
     * @return the release as saved
     */
    public static RLY_Release__c commitResolutions(Id releaseId, String requestJson) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        if (!mayResolve(rel)) {
            throw new RlyReleaseException('Only the developer who raised this release or an approver can resolve its conflicts.');
        }
        String body = RlyConflictRules.resolveFile(rel, requestJson);
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        RlyGit git = RlyGit.forConnection(conn);
        git.putFile(new RlyGitFile('.relay-inbox/' + rel.Name + '-resolve.json', rel.Source_Branch__c)
            .withContent(EncodingUtil.base64Encode(Blob.valueOf(body)), rel.Name + ': conflict resolutions'));
        git.startPipeline(RlyPipelineRun.inputs(rel, 'resolve', rel.Source_Branch__c));
        rel.Status__c = 'Validating';
        rel.Pending_Run__c = 'resolve';
        rel.Checks_Requested__c = System.now();
        rel.Scan_Status__c = conn.Code_Scan__c ? 'Pending' : 'Not configured';
        rel.Validation_Status__c = 'Pending';
        rel.Scan_Bypassed_By__c = null;
        rel.Scan_Bypass_Reason__c = null;
        rel.Error_Message__c = null;
        RlyReleaseStore.save(rel);
        return rel;
    }
}
