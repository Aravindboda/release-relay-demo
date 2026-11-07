/**
 * @description The provider side of the release page's Changes card (build 45): a pull request's changed files a page
 * at a time, with GitHub's keys (filename, status, additions, deletions, patch, previous_filename), its totals and its
 * links. GitHub (RlyGitHubChanges) and GitLab (RlyGitLabChanges) have one; the other providers have none (of returns
 * null) and the card says to open the pull request.
 */
public abstract with sharing class RlyGitChanges {

    /** @description The provider the files are read through. */
    protected RlyGit git;

    /**
     * @description The Changes card's reader for a provider.
     * @param git the provider
     * @return the reader, or null when the provider can't list a pull request's files
     */
    public static RlyGitChanges of(RlyGit git) {
        RlyGitChanges reader;
        if (git instanceof RlyGitHub) {
            reader = new RlyGitHubChanges();
        } else if (git instanceof RlyGitLab) {
            reader = new RlyGitLabChanges();
        }
        if (reader != null) {
            reader.git = git;
        }
        return reader;
    }

    /**
     * @description One page of a pull request's changed files.
     * @param prNumber the pull request number (GitLab: the merge request's iid)
     * @param pageNo the page, from 1
     * @param pageSize files per page
     * @return the files, each a map with GitHub's keys
     */
    public abstract List<Object> page(Integer prNumber, Integer pageNo, Integer pageSize);

    /**
     * @description A pull request's totals: changed_files, additions and deletions.
     * @param prNumber the pull request number
     * @param pageAdditions lines added on the first page (kept where the provider doesn't count lines)
     * @param pageDeletions lines removed on the first page (likewise)
     * @return the totals
     */
    public abstract Map<String, Object> totals(Integer prNumber, Integer pageAdditions, Integer pageDeletions);

    /**
     * @description The link to a pull request's changed files.
     * @param prUrl the pull request's link
     * @return the files view's link, or null when the link is blank
     */
    public abstract String filesUrl(String prUrl);

    /**
     * @description The link to one file in the files view.
     * @param filesUrl the files view's link, or null
     * @param filename the file's path, or null
     * @return the file's link (the files view's when either is missing)
     */
    public abstract String fileUrl(String filesUrl, String filename);
}
