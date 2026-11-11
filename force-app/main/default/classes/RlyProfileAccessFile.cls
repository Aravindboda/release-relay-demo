/**
 * @description The profile access file the hub commits on a new release's branch with its components:
 * .relay-inbox/<REL>-access.json, {"profiles": [{profile, label, rows: [{section, key, values}]}]}. The pipeline
 * (version 32) writes each row into the profile's file on the branch and takes the upload file off; a release that
 * carries only profile access commits this file alone.
 */
public with sharing class RlyProfileAccessFile {

    /**
     * @description Whether a release carries profile access.
     * @param rel the release, with Profile_Access_Count__c
     * @return true when it has rows
     */
    public static Boolean has(RLY_Release__c rel) {
        return rel != null && rel.Profile_Access_Count__c != null && rel.Profile_Access_Count__c > 0;
    }

    /**
     * @description The file's path on the release branch.
     * @param rel the release, with Name
     * @return .relay-inbox/<REL>-access.json
     */
    public static String pathOf(RLY_Release__c rel) {
        return '.relay-inbox/' + rel.Name + '-access.json';
    }

    /**
     * @description The file to commit.
     * @param rel the release, with Id, Name and Profile_Access_Count__c
     * @param branch the release branch
     * @return the file, or null when the release carries no profile access
     */
    public static RlyGitFile fileFor(RLY_Release__c rel, String branch) {
        if (!has(rel)) {
            return null;
        }
        List<RlyProfileAccessRules.ProfileRows> profiles = RlyProfileAccessRules.fromField(RlyReleaseStore.profileAccess(rel.Id));
        if (profiles.isEmpty()) {
            return null;
        }
        String body = JSON.serialize(new Map<String, Object>{ 'profiles' => profiles }, true);
        return new RlyGitFile(pathOf(rel), branch).withContent(EncodingUtil.base64Encode(Blob.valueOf(body)), rel.Name + ': profile access');
    }

    /**
     * @description Whether a release that has no zip and no deletions marker goes ahead with its profile access alone.
     * @param rel the release, with Retrieve_Id__c and Profile_Access_Count__c
     * @return true for a new release with only profile access
     */
    public static Boolean carriesAlone(RLY_Release__c rel) {
        return String.isBlank(rel.Retrieve_Id__c) && has(rel) && !RlyAppendRun.isPending(rel);
    }

    /**
     * @description Commits the release's files on its branch: the zip or marker (when any), then its profile access and
     * the lines it takes out on purpose (a new release's only: an add to an open release carries neither).
     * @param rel the release
     * @param git the Git connection
     * @param first the zip or marker, or null
     */
    public static void commitWith(RLY_Release__c rel, RlyGit git, RlyGitFile first) {
        if (first != null) {
            git.putFile(first);
        }
        if (RlyAppendRun.isPending(rel)) {
            return;
        }
        String branch = RlyPipelineRun.branchName(rel);
        RlyGitFile access = fileFor(rel, branch);
        if (access != null) {
            git.putFile(access);
        }
        RlyGitFile keep = RlyKeepFile.fileFor(rel, branch); // build 60: lines taken out on purpose (D40)
        if (keep != null) {
            git.putFile(keep);
        }
    }

    /**
     * @description The profile access rows of the releases a promotion carries (their rows travel in Git).
     * @param carried the releases, with Profile_Access_Count__c
     * @return the number of rows
     */
    public static Decimal carriedRows(List<RLY_Release__c> carried) {
        Decimal n = 0;
        for (RLY_Release__c r : carried) {
            n += r.Profile_Access_Count__c == null ? 0 : r.Profile_Access_Count__c;
        }
        return n;
    }

    /**
     * @description The words a release's log adds for its profile access: ", 3 profile access rows", or ''.
     * @param rel the release, with Profile_Access_Count__c
     * @return the words
     */
    public static String logWords(RLY_Release__c rel) {
        return has(rel) ? ', ' + RlyProfileAccessRules.rowWords(rel.Profile_Access_Count__c.intValue()) : '';
    }
}
