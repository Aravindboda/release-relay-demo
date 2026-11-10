/**
 * @description One update of the pipeline files in the hub's Git repository (RlyPipelineFiles.updateRepository): this
 * hub's packaged files, written on a branch with a pull request into the pipeline branch, or straight to the pipeline
 * branch. Callouts only.
 */
public with sharing class RlyPipelineUpdate {

    private RlyGit git;
    private String pipelineBranch;
    private List<RlyPipelineFiles.FileInfo> files;
    private Map<String, String> bodies = new Map<String, String>();
    private Integer packagedVersion;

    /**
     * @description An update of these files, from and into the pipeline branch.
     * @param git the Git provider
     * @param pipelineBranch the pipeline branch
     * @param files this hub's files
     */
    public RlyPipelineUpdate(RlyGit git, String pipelineBranch, List<RlyPipelineFiles.FileInfo> files) {
        this.git = git;
        this.pipelineBranch = pipelineBranch;
        this.files = files;
    }

    /**
     * @description Takes the packaged content; throws when a file isn't packaged.
     * @param packaged static resource name to content
     * @param packagedVersion the packaged version
     */
    public void load(Map<String, String> packaged, Integer packagedVersion) {
        for (RlyPipelineFiles.FileInfo f : files) {
            if (!packaged.containsKey(f.resourceName)) {
                throw new RlyGit.GitException('The static resource ' + f.resourceName + ' isn\'t in this hub.');
            }
        }
        this.bodies = packaged;
        this.packagedVersion = packagedVersion;
    }

    /**
     * @description Writes the files and fills the result.
     * @param how commit to commit straight to the pipeline branch; anything else opens a pull request
     * @param r the result to fill
     */
    public void apply(String how, RlyPipelineFiles.UpdateResult r) {
        if (how == RlyPipelineFiles.VIA_COMMIT) {
            r.url = writeTo(pipelineBranch);
            r.message = 'Committed version ' + packagedVersion + ' of the pipeline files to ' + pipelineBranch + '.';
        } else {
            r.url = viaPullRequest();
            r.message = 'Opened a pull request with version ' + packagedVersion + ' of the pipeline files into ' + pipelineBranch
                + '. Merge it to start using them.';
        }
        r.ok = true;
    }

    // The update branch (reused when it's there), the files on it, and its pull request (reused when it's open).
    private String viaPullRequest() {
        String head = 'release-relay/pipeline-files-v' + packagedVersion;
        if (!git.branchExists(head)) {
            git.createBranch(head, pipelineBranch);
        }
        writeTo(head);
        RlyGit.PullRequest existing = git.findPullRequest(head, pipelineBranch);
        if (existing != null && existing.state == 'open') {
            return existing.url;
        }
        List<String> paths = new List<String>();
        for (RlyPipelineFiles.FileInfo f : files) {
            paths.add(f.repoPath);
        }
        return git.openPullRequest(head, pipelineBranch, title() + '\n\nUpdates the ' + System.Label.RLY_App_Name
            + ' pipeline files to version ' + packagedVersion + ': ' + String.join(paths, ', ') + '.');
    }

    // Commits every file on the branch; the link of the last commit.
    private String writeTo(String target) {
        String link;
        for (RlyPipelineFiles.FileInfo f : files) {
            link = git.putFile(new RlyGitFile(f.repoPath, target)
                .withContent(EncodingUtil.base64Encode(Blob.valueOf(bodies.get(f.resourceName))), title() + ': ' + f.name));
        }
        return link;
    }

    private String title() {
        return System.Label.RLY_App_Name + ' pipeline files v' + packagedVersion;
    }
}
