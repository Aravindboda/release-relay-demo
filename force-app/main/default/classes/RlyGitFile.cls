/**
 * @description A file to commit on a branch of the hub's Git repository (RlyGit.putFile).
 */
public with sharing class RlyGitFile {

    /** @description Path in the repository. */
    public String path;
    /** @description Branch to commit on. */
    public String branch;
    /** @description The content, base64. */
    public String base64Content;
    /** @description The commit message. */
    public String message;

    /**
     * @description A commit of one file on a branch.
     * @param path path in the repository
     * @param branch branch to commit on
     */
    public RlyGitFile(String path, String branch) {
        this.path = path;
        this.branch = branch;
    }

    /**
     * @description Sets the content and the commit message.
     * @param base64Content the content, base64
     * @param message the commit message
     * @return this commit
     */
    public RlyGitFile withContent(String base64Content, String message) {
        this.base64Content = base64Content;
        this.message = message;
        return this;
    }
}
