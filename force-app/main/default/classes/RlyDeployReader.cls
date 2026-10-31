/**
 * @description Reads an approved release's merge and deploy: the merge and deploy result files and the pipeline run.
 */
public with sharing class RlyDeployReader {

    /**
     * @description Reads the merge and deploy results of a release that is deploying.
     * @param rel the release (Deploying)
     * @param git the Git provider
     */
    public static void readDeploy(RLY_Release__c rel, RlyGit git) {
        RlyGit.Run run = RlyPipelineRun.findRun(git, rel);
        Map<String, Object> mergeResult = RlyPipelineRun.result(git, rel, 'merge');
        if (mergeResult != null && String.valueOf(mergeResult.get('status')) == 'Failed') {
            mergeFailed(rel, mergeResult);
            return;
        }
        if (mergeResult != null) {
            rel.Merge_Commit__c = String.valueOf(mergeResult.get('sha')).left(40);
        }
        Map<String, Object> deploy = RlyPipelineRun.result(git, rel, 'deploy');
        if (deploy != null) {
            deployed(rel, deploy);
        } else if (run != null && run.failed()) {
            rel.Status__c = 'Deploy failed';
            rel.Deploy_Status__c = 'Failed';
            rel.Error_Message__c = 'The pipeline run failed before it wrote a result. Open the run.';
        } else {
            rel.Deploy_Status__c = 'Deploying';
        }
    }

    private static void mergeFailed(RLY_Release__c rel, Map<String, Object> mergeResult) {
        rel.Status__c = 'Deploy failed';
        rel.Deploy_Status__c = 'Failed';
        rel.Deploy_Result__c = JSON.serialize(mergeResult).left(131072);
        rel.Error_Message__c = ('Merge failed: ' + String.valueOf(mergeResult.get('message'))).left(2000);
    }

    private static void deployed(RLY_Release__c rel, Map<String, Object> deploy) {
        Boolean ok = String.valueOf(deploy.get('status')) == 'Deployed';
        rel.Status__c = ok ? 'Deployed' : 'Deploy failed';
        rel.Deploy_Status__c = ok ? 'Deployed' : 'Failed';
        rel.Deploy_Result__c = JSON.serialize(deploy).left(131072);
        rel.Error_Message__c = ok ? null : String.valueOf(deploy.get('message')).left(2000);
    }
}
