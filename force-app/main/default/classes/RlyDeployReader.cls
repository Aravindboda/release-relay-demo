/**
 * @description Reads an approved release's merge and deploy: the merge and deploy result files and the pipeline run.
 * The merge result's sync list (branches brought up to date from the target: after a deploy to the hub, every stage
 * branch and then every developer branch) is kept in Deploy_Result__c and, as a JSON array, in Back_Merge_Result__c.
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
        Object sync = mergeResult == null ? null : mergeResult.get('sync');
        if (sync instanceof List<Object>) {
            rel.Back_Merge_Result__c = JSON.serialize(sync).left(32768);
        }
        Map<String, Object> deploy = RlyPipelineRun.result(git, rel, 'deploy');
        if (deploy != null) {
            deployed(rel, withSync(deploy, sync));
        } else if (run != null && run.failed()) {
            rel.Status__c = 'Deploy failed';
            rel.Deploy_Status__c = 'Failed';
            rel.Error_Message__c = 'The pipeline run failed before it wrote a result. Open the run.';
            keepSync(rel, sync);
        } else {
            rel.Deploy_Status__c = 'Deploying';
            keepSync(rel, sync);
        }
    }

    // How the developer branches were updated after the merge (merge.json sync) goes with the deploy result.
    private static Map<String, Object> withSync(Map<String, Object> deploy, Object sync) {
        if (sync != null) {
            deploy.put('sync', sync);
        }
        return deploy;
    }

    private static void keepSync(RLY_Release__c rel, Object sync) {
        if (sync != null) {
            rel.Deploy_Result__c = JSON.serialize(new Map<String, Object>{ 'sync' => sync }).left(131072);
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
