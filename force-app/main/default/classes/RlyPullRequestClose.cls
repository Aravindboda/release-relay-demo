/**
 * @description Closes a rejected release's pull request: posts the reason as a comment, then closes it. The two
 * are independent, so the pull request is closed even when the comment can't be posted; each problem is
 * reported in words for the release's Error_Message__c.
 */
public with sharing class RlyPullRequestClose {

    /**
     * @description Comments on the pull request and closes it.
     * @param rel the release, with PR_Number__c
     * @param comment the comment to post
     * @return what went wrong (empty when both worked)
     */
    public static List<String> closeWithComment(RLY_Release__c rel, String comment) {
        List<String> problems = new List<String>();
        RlyGit git;
        try {
            git = RlyGit.forConnection(RlyReleaseStore.git());
        } catch (Exception e) {
            problems.add('the pull request couldn\'t be closed: ' + e.getMessage());
            return problems;
        }
        Integer prNumber = rel.PR_Number__c.intValue();
        try {
            git.commentOnPullRequest(prNumber, comment);
        } catch (Exception e) {
            problems.add('the comment couldn\'t be posted on the pull request: ' + e.getMessage());
        }
        try {
            git.closePullRequest(prNumber);
        } catch (Exception e) {
            problems.add('the pull request couldn\'t be closed: ' + e.getMessage());
        }
        return problems;
    }
}
