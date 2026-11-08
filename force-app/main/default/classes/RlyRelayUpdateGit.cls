/**
 * @description Install Release Relay update: the Git side, through the hub's Git connection (RlyGit.request, so the
 * token stays in the Named Credential). Finds the build's zip in .relay-inbox/ on the update branch, reads it (when it
 * fits in the heap), and copies it, without downloading it, onto the step's new branch made from its target under the
 * name the pipeline expects (.relay-inbox/<request id>.zip):
 *   GitHub: a new commit on the target's head whose tree adds the zip's Git object (git/trees, git/commits, git/refs).
 *   GitLab: RlyRelayUpdateGitLab (cherry-pick, then move; no content is sent).
 * Bitbucket and Azure DevOps aren't supported here yet.
 */
public with sharing class RlyRelayUpdateGit {

    /** @description The folder the pipeline reads the hub's zips from. */
    public static final String INBOX = '.relay-inbox';
    /** @description Heap kept free when a zip is downloaded (the zip is held about twice while it is read). */
    public static final Integer HEAP_MARGIN = 700000;
    private static final String GITHUB = 'GitHub';
    private static final String GITLAB = 'GitLab';
    private static final String GET = 'GET';
    private static final String POST = 'POST';

    private final RlyGit git;
    private final Boolean onGitHub;

    /** @description The zip on the update branch. */
    public class ZipFile {
        /** @description Its path, for example .relay-inbox/build52.zip. */
        public String path;
        /** @description Its Git object id. */
        public String sha;
        /** @description Its size in bytes (GitHub), or null. */
        public Integer size;
        /** @description The commit that last changed it (GitLab), or null. */
        public String commitSha;
    }

    /**
     * @description The Git side for a connection's provider.
     * @param git the provider
     */
    public RlyRelayUpdateGit(RlyGit git) {
        this.git = git;
        String provider = git.connection().Provider__c;
        if (!supports(provider)) {
            throw new RlyReleaseException('Install update works with GitHub or GitLab for now; this connection is ' + provider + '.');
        }
        this.onGitHub = provider == GITHUB;
    }

    /**
     * @description Whether the provider can copy the zip from the hub.
     * @param providerName the connection's provider
     * @return true for GitHub and GitLab
     */
    public static Boolean supports(String providerName) {
        return providerName == GITHUB || providerName == GITLAB;
    }

    /**
     * @description The one zip in .relay-inbox/ on a branch.
     * @param branch the update branch
     * @return the zip
     */
    public ZipFile findZip(String branch) {
        List<ZipFile> zips = onGitHub ? gitHubZips(branch) : RlyRelayUpdateGitLab.zips(git, branch);
        if (zips.isEmpty()) {
            throw new RlyReleaseException('No zip in ' + INBOX + '/ on ' + branch + '. Commit the build\'s zip there first.');
        }
        if (zips.size() > 1) {
            throw new RlyReleaseException(branch + ' has ' + zips.size() + ' zips in ' + INBOX + '/. Keep only the build\'s zip there.');
        }
        ZipFile z = zips[0];
        if (!onGitHub) {
            z.commitSha = RlyRelayUpdateGitLab.commitOf(git, branch, z.path);
        }
        return z;
    }

    /**
     * @description The zip's bytes, or null when it would not fit in the heap (the caller then reads the tests elsewhere).
     * @param z the zip
     * @return the zip, or null
     */
    public Blob download(ZipFile z) {
        if (!fits(z.size)) {
            return null;
        }
        HttpResponse res = onGitHub
            ? git.request(new RlyGitRequest(GET, gitHubRepo() + '/git/blobs/' + z.sha, null).withHeader('Accept', 'application/vnd.github.raw+json'))
            : git.request(new RlyGitRequest(GET, RlyGitLabRuns.project(git, '/repository/blobs/' + z.sha + '/raw'), null));
        git.requireOk(res, 'Reading ' + z.path);
        Blob body = res.getBodyAsBlob();
        return body == null || !fits(body.size()) ? null : body;
    }

    /**
     * @description Puts the zip on a check's new branch (made from its target) as .relay-inbox/<request id>.zip.
     * @param z the zip
     * @param s the check, with requestId, branch and target
     */
    public void copyTo(ZipFile z, RlyRelayUpdateState.Step s) {
        if (onGitHub) {
            gitHubCopy(z, s);
        } else {
            RlyRelayUpdateGitLab.copy(git, z, s);
            RlyRelayUpdateGitLab.rename(git, s.branch, new List<String>{ z.path, inboxPath(s), 'Release Relay update: ' + s.requestId + '.zip' });
        }
    }

    /**
     * @description A list from parsed JSON (empty when it isn't one).
     * @param parsed the parsed value
     * @return the list
     */
    public static List<Object> asList(Object parsed) {
        return parsed instanceof List<Object> ? (List<Object>) parsed : new List<Object>();
    }

    /**
     * @description A zip found in a folder listing.
     * @param path its path
     * @param sha its Git object id
     * @param size its size, or null
     * @return the zip
     */
    public static ZipFile zipOf(String path, String sha, Object size) {
        ZipFile z = new ZipFile();
        z.path = path;
        z.sha = sha;
        z.size = size == null ? null : Integer.valueOf(String.valueOf(size));
        return z;
    }

    /**
     * @description The error for a branch without .relay-inbox/.
     * @param branch the branch
     * @return the exception to throw
     */
    public static RlyReleaseException noInbox(String branch) {
        return new RlyReleaseException('Nothing in ' + INBOX + '/ on ' + branch + ' (or the branch doesn\'t exist). Commit the build\'s zip there first.');
    }

    /**
     * @description Where a check's zip goes on its branch: the name the pipeline reads for its request id.
     * @param s the check
     * @return .relay-inbox/<request id>.zip
     */
    public static String inboxPath(RlyRelayUpdateState.Step s) {
        return INBOX + '/' + s.requestId + '.zip';
    }

    // Whether this many bytes can be held twice with the margin left.
    private static Boolean fits(Integer bytes) {
        return bytes == null || Limits.getHeapSize() + 2 * bytes + HEAP_MARGIN < Limits.getLimitHeapSize();
    }

    private String gitHubRepo() {
        return '/repos/' + git.connection().Repository__c.trim();
    }

    private List<ZipFile> gitHubZips(String branch) {
        HttpResponse res = git.request(new RlyGitRequest(GET, gitHubRepo() + '/contents/' + INBOX + '?ref=' + RlyGitRequest.encode(branch), null));
        if (res.getStatusCode() == 404) {
            throw noInbox(branch);
        }
        git.requireOk(res, 'Reading ' + INBOX + ' on ' + branch);
        List<ZipFile> out = new List<ZipFile>();
        for (Object o : asList(JSON.deserializeUntyped(res.getBody()))) {
            Map<String, Object> f = (Map<String, Object>) o;
            if (String.valueOf(f.get('type')) == 'file' && RlyRelayUpdateZip.isZip(String.valueOf(f.get('name')))) {
                out.add(zipOf(String.valueOf(f.get('path')), String.valueOf(f.get('sha')), f.get('size')));
            }
        }
        return out;
    }

    private void gitHubCopy(ZipFile z, RlyRelayUpdateState.Step s) {
        String repo = gitHubRepo();
        HttpResponse ref = git.request(new RlyGitRequest(GET, repo + '/git/ref/heads/' + RlyGitRequest.encodePath(s.target), null));
        if (ref.getStatusCode() == 404) {
            throw new RlyReleaseException('Branch ' + s.target + ' wasn\'t found in ' + git.connection().Repository__c + '.');
        }
        git.requireOk(ref, 'Reading ' + s.target);
        String head = String.valueOf(field(ref, 'object').get('sha'));
        HttpResponse headCommit = git.request(new RlyGitRequest(GET, repo + '/git/commits/' + head, null));
        git.requireOk(headCommit, 'Reading ' + s.target + '\'s head');
        String baseTree = String.valueOf(field(headCommit, 'tree').get('sha'));
        String tree = created(repo + '/git/trees', new Map<String, Object>{ 'base_tree' => baseTree, 'tree' => new List<Object>{
            new Map<String, Object>{ 'path' => inboxPath(s), 'mode' => '100644', 'type' => 'blob', 'sha' => z.sha } } }, 'Adding the zip');
        String sha = created(repo + '/git/commits', new Map<String, Object>{ 'message' => 'Release Relay update: ' + s.requestId + '.zip', 'tree' => tree,
            'parents' => new List<Object>{ head } }, 'Committing the zip');
        created(repo + '/git/refs', new Map<String, Object>{ 'ref' => 'refs/heads/' + s.branch, 'sha' => sha }, 'Creating branch ' + s.branch);
    }

    // POSTs a body and returns the sha of what was created.
    private String created(String path, Map<String, Object> body, String action) {
        HttpResponse res = git.request(new RlyGitRequest(POST, path, JSON.serialize(body)));
        git.requireOk(res, action);
        Object sha = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('sha');
        return sha == null ? null : String.valueOf(sha);
    }

    private static Map<String, Object> field(HttpResponse res, String name) {
        return (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get(name);
    }
}
