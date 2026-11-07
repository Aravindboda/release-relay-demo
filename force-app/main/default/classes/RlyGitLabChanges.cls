/**
 * @description The Changes card on GitLab (build 45): GET /merge_requests/:iid/diffs a page at a time (RlyGitLabDiffs
 * gives each file GitHub's keys and counts its lines) and GET /merge_requests/:iid for changes_count.
 */
public with sharing class RlyGitLabChanges extends RlyGitChanges {

    /**
     * @description One page of the merge request's files.
     * @param prNumber the merge request's iid
     * @param pageNo the page, from 1
     * @param pageSize files per page
     * @return the files
     */
    public override List<Object> page(Integer prNumber, Integer pageNo, Integer pageSize) {
        HttpResponse res = git.request(new RlyGitRequest('GET', RlyGitLabRuns.project(git, '/merge_requests/' + prNumber
            + '/diffs?per_page=' + pageSize + '&page=' + pageNo), null));
        git.requireOk(res, 'Reading merge request !' + prNumber);
        return RlyGitLabDiffs.toFiles((List<Object>) JSON.deserializeUntyped(res.getBody()));
    }

    /**
     * @description changed_files from changes_count; GitLab doesn't count lines, so the first page's stay.
     * @param prNumber the merge request's iid
     * @param pageAdditions lines added on the first page
     * @param pageDeletions lines removed on the first page
     * @return the totals
     */
    public override Map<String, Object> totals(Integer prNumber, Integer pageAdditions, Integer pageDeletions) {
        HttpResponse res = git.request(new RlyGitRequest('GET', RlyGitLabRuns.project(git, '/merge_requests/' + prNumber), null));
        git.requireOk(res, 'Reading merge request !' + prNumber);
        Map<String, Object> mr = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return new Map<String, Object>{ 'changed_files' => RlyGitLabDiffs.changesCount(mr.get('changes_count')),
            'additions' => pageAdditions, 'deletions' => pageDeletions };
    }

    /**
     * @description The merge request's Changes view.
     * @param prUrl the merge request's link
     * @return its link + /diffs, or null when the link is blank
     */
    public override String filesUrl(String prUrl) {
        return String.isBlank(prUrl) ? null : prUrl.trim().removeEnd('/') + '/diffs';
    }

    /**
     * @description A file in the Changes view: # and the SHA-1 of its path, in hex.
     * @param filesUrl the Changes view's link, or null
     * @param filename the file's path, or null
     * @return the link
     */
    public override String fileUrl(String filesUrl, String filename) {
        return filesUrl == null || filename == null ? filesUrl
            : filesUrl + '#' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(filename)));
    }
}
