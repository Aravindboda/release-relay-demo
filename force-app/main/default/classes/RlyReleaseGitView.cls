/**
 * @description Several Git connections (build 45): what a release page shows about the repository the release lives
 * in: the provider's name, what it calls a pull request (Merge request on GitLab), the repository and its web address,
 * and after a deploy to production how the other repositories' prod branches were kept in step (RlyProdSync).
 */
public with sharing class RlyReleaseGitView {

    /**
     * @description Fills the release page's repository fields.
     * @param d the page's detail, with its release
     */
    public static void fill(RlyReleasesController.Detail d) {
        RLY_Git_Connection__c c = RlyReleaseStore.gitFor(d.release);
        d.gitProvider = RlyGitName.labelFor(c);
        d.prodSync = RlyProdSync.views((String) d.release.getPopulatedFieldsAsMap().get('Prod_Sync__c'));
        for (RlyProdSync.View v : d.prodSync) {
            if (v.state == RlyProdSync.RUNNING) {
                d.running = true; // the page keeps checking until the other repositories' prod branches are in step
            }
        }
        if (c == null || d.gitProvider == null) {
            return;
        }
        d.repository = c.Repository__c;
        try {
            RlyGit git = RlyGit.forConnection(c);
            d.changeRequestLabel = git.changeRequestLabel();
            d.repositoryUrl = git.webUrl();
        } catch (Exception e) {
            d.changeRequestLabel = null;
        }
    }
}
