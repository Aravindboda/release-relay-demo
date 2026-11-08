/**
 * @description The Changes card on GitHub (build 45; the reads RlyPullRequestFiles made before): GET /pulls/{n}/files a
 * page at a time and GET /pulls/{n} for the totals, through RlyGitHub.readPullRequest.
 */
public with sharing class RlyGitHubChanges extends RlyGitChanges {

    /** @description The reader with this provider's files view and anchors. */
    public RlyGitHubChanges() {
        super('/files', '#diff-', 'SHA-256');
    }

    /**
     * @description One page of the pull request's files, as GitHub lists them.
     * @param prNumber the pull request number
     * @param pageNo the page, from 1
     * @param pageSize files per page
     * @return the files
     */
    public override List<Object> page(Integer prNumber, Integer pageNo, Integer pageSize) {
        return (List<Object>) ((RlyGitHub) git).readPullRequest(prNumber, '/files?per_page=' + pageSize + '&page=' + pageNo);
    }

    /**
     * @description The pull request itself: GitHub counts changed_files, additions and deletions.
     * @param prNumber the pull request number
     * @param pageAdditions not used (GitHub counts lines)
     * @param pageDeletions not used
     * @return the pull request
     */
    public override Map<String, Object> totals(Integer prNumber, Integer pageAdditions, Integer pageDeletions) {
        return (Map<String, Object>) ((RlyGitHub) git).readPullRequest(prNumber, '');
    }
}
