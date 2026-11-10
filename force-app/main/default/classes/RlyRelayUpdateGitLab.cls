/**
 * @description Install Release Relay update on GitLab: the zip in .relay-inbox/ (repository tree), the commit that last
 * changed it, and the copy onto a check's new branch without sending its content: the branch is made from the target,
 * that commit is cherry-picked onto it, and the zip is moved to .relay-inbox/<request id>.zip. Commit the zip on its
 * own: whatever else that commit changed comes along.
 */
public with sharing class RlyRelayUpdateGitLab {

    private static final String GET = 'GET';
    private static final String POST = 'POST';

    /**
     * @description The zips in .relay-inbox/ on a branch.
     * @param git the GitLab provider
     * @param branch the branch
     * @return the zips
     */
    public static List<RlyRelayUpdateGit.ZipFile> zips(RlyGit git, String branch) {
        HttpResponse res = git.request(new RlyGitRequest(GET, RlyGitLabRuns.project(git, '/repository/tree?path='
            + RlyGitRequest.encode(RlyRelayUpdateGit.INBOX) + '&ref=' + RlyGitRequest.encode(branch) + '&per_page=100'), null));
        if (res.getStatusCode() == 404) {
            throw RlyRelayUpdateGit.noInbox(branch);
        }
        git.requireOk(res, 'Reading ' + RlyRelayUpdateGit.INBOX + ' on ' + branch);
        List<RlyRelayUpdateGit.ZipFile> out = new List<RlyRelayUpdateGit.ZipFile>();
        for (Object o : RlyRelayUpdateGit.asList(JSON.deserializeUntyped(res.getBody()))) {
            Map<String, Object> f = (Map<String, Object>) o;
            if (String.valueOf(f.get('type')) == 'blob' && RlyRelayUpdateZip.isZip(String.valueOf(f.get('name')))) {
                out.add(RlyRelayUpdateGit.zipOf(String.valueOf(f.get('path')), String.valueOf(f.get('id')), null));
            }
        }
        return out;
    }

    /**
     * @description The commit on a branch that last changed a file.
     * @param git the GitLab provider
     * @param branch the branch
     * @param path the file
     * @return the commit id
     */
    public static String commitOf(RlyGit git, String branch, String path) {
        HttpResponse res = git.request(new RlyGitRequest(GET, RlyGitLabRuns.project(git, '/repository/commits?ref_name='
            + RlyGitRequest.encode(branch) + '&path=' + RlyGitRequest.encode(path) + '&per_page=1'), null));
        git.requireOk(res, 'Reading the commits of ' + path);
        List<Object> commits = RlyRelayUpdateGit.asList(JSON.deserializeUntyped(res.getBody()));
        if (commits.isEmpty()) {
            throw new RlyReleaseException('No commit on ' + branch + ' changed ' + path + '.');
        }
        return String.valueOf(((Map<String, Object>) commits[0]).get('id'));
    }

    /**
     * @description Makes a branch from another and cherry-picks the zip's commit onto it.
     * @param git the GitLab provider
     * @param z the zip, with commitSha
     * @param s the check: its branch is made from its target
     */
    public static void copy(RlyGit git, RlyRelayUpdateGit.ZipFile z, RlyRelayUpdateState.Step s) {
        String newBranch = s.branch;
        git.createBranch(newBranch, s.target);
        HttpResponse pick = git.request(new RlyGitRequest(POST, RlyGitLabRuns.project(git, '/repository/commits/' + z.commitSha + '/cherry_pick'),
            JSON.serialize(new Map<String, Object>{ 'branch' => newBranch })));
        git.requireOk(pick, 'Copying the zip onto ' + newBranch);
    }

    /**
     * @description Moves the zip to its new name on a branch (nothing when the name is already right).
     * @param git the GitLab provider
     * @param branch the branch
     * @param move the zip's path, its new path and the commit message
     */
    public static void rename(RlyGit git, String branch, List<String> move) {
        if (move[0].equals(move[1])) {
            return;
        }
        HttpResponse moved = git.request(new RlyGitRequest(POST, RlyGitLabRuns.project(git, '/repository/commits'),
            JSON.serialize(new Map<String, Object>{ 'branch' => branch, 'commit_message' => move[2], 'actions' => new List<Object>{
                new Map<String, Object>{ 'action' => 'move', 'previous_path' => move[0], 'file_path' => move[1] } } })));
        git.requireOk(moved, 'Naming the zip on ' + branch);
    }
}
