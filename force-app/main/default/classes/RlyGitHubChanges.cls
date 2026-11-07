/**
 * @description The Changes card on GitHub (build 45; the reads RlyPullRequestFiles made before): GET /pulls/{n}/files a
 * page at a time and GET /pulls/{n} for the totals, through RlyGitHub.readPullRequest.
 */
public with sharing class RlyGitHubChanges extends RlyGitChanges {

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

    /**
     * @description The pull request's Files changed view.
     * @param prUrl the pull request's link
     * @return its link + /files, or null when the link is blank
     */
    public override String filesUrl(String prUrl) {
        return String.isBlank(prUrl) ? null : prUrl.trim().removeEnd('/') + '/files';
    }

    /**
     * @description A file in the Files changed view: #diff- and the SHA-256 of its path, in hex.
     * @param filesUrl the files view's link, or null
     * @param filename the file's path, or null
     * @return the link
     */
    public override String fileUrl(String filesUrl, String filename) {
        return filesUrl == null || filename == null ? filesUrl
            : filesUrl + '#diff-' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(filename)));
    }
}
