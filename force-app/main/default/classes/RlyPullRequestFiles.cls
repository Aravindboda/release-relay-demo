/**
 * @description The Changes card on the release page: the files a release's pull request changes, with their
 * patches, read through the hub's Git connection (RlyGitHub lists them; other providers get a message to open the
 * pull request). Anyone who can open the release can read them. No DML: callouts only.
 */
public with sharing class RlyPullRequestFiles {

    private static final Integer PAGE_SIZE = 100;
    private static final Integer MAX_PAGES = 3;

    /** @description What the Changes card shows. */
    public class Changes {
        /** @description The files could be listed. */
        @AuraEnabled public Boolean available = false;
        /** @description Why they aren't listed (no pull request, provider), or null. */
        @AuraEnabled public String message;
        /** @description The Git provider's name, for example GitHub. */
        @AuraEnabled public String provider;
        /** @description The pull request number. */
        @AuraEnabled public Integer prNumber;
        /** @description Link to the pull request's files view, or null. */
        @AuraEnabled public String filesUrl;
        /** @description The changed files, in the provider's order. */
        @AuraEnabled public List<FileChange> files = new List<FileChange>();
        /** @description Lines added, all files. */
        @AuraEnabled public Integer additions = 0;
        /** @description Lines removed, all files. */
        @AuraEnabled public Integer deletions = 0;
        /** @description More files than could be read (the first 300 are listed). */
        @AuraEnabled public Boolean truncated = false;
        /** @description How many files the pull request changes in all, when more than are listed; otherwise null. */
        @AuraEnabled public Integer totalFiles;
        /** @description The org the release goes to (the left side of a compare). */
        @AuraEnabled public String targetName;
        /** @description The branch the pull request merges into. */
        @AuraEnabled public String targetBranch;
        /** @description The org the release comes from (the right side of a compare). */
        @AuraEnabled public String sourceName;
    }

    /** @description One changed file of the pull request. */
    public class FileChange {
        /** @description Path in the repository. */
        @AuraEnabled public String filename;
        /** @description added, modified, removed or renamed (the provider's word). */
        @AuraEnabled public String status;
        /** @description Lines added. */
        @AuraEnabled public Integer additions;
        /** @description Lines removed. */
        @AuraEnabled public Integer deletions;
        /** @description The unified-diff patch, or null when the provider gives none (binary or too big). */
        @AuraEnabled public String patch;
        /** @description The path before a rename, or null. */
        @AuraEnabled public String previousFilename;
        /** @description Link to this file in the pull request's files view, or null. */
        @AuraEnabled public String url;
        /** @description Shown instead of a diff when there is no patch, or null. */
        @AuraEnabled public String note;
    }

    /**
     * @description The files of a release's pull request.
     * @param releaseId the release (a release or a promotion with a pull request)
     * @return the changes, or a message when they can't be listed
     */
    @AuraEnabled
    public static Changes files(Id releaseId) {
        try {
            return read(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static Changes read(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        Changes c = new Changes();
        c.targetName = rel.Target_Org__r?.Name;
        c.targetBranch = rel.Target_Branch__c;
        c.sourceName = rel.Source_Org__r?.Name;
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (rel.PR_Number__c == null || conn == null) {
            c.message = rel.PR_Number__c == null ? 'This release has no pull request yet.' : 'Set up the Git connection first.';
            return c;
        }
        RlyGit git = RlyGit.forConnection(conn);
        c.provider = git.providerLabel();
        c.prNumber = rel.PR_Number__c.intValue();
        if (!(git instanceof RlyGitHub)) {
            c.message = 'Changes are shown for GitHub only; open the pull request.';
            return c;
        }
        c.filesUrl = String.isBlank(rel.PR_URL__c) ? null : rel.PR_URL__c.trim().removeEnd('/') + '/files';
        c.available = true;
        readPages((RlyGitHub) git, c);
        return c;
    }

    // Reads the pages while they are full, up to MAX_PAGES.
    private static void readPages(RlyGitHub git, Changes c) {
        Integer pageNo = 1;
        List<Object> page = filesPage(git, c.prNumber, pageNo);
        while (page != null) {
            for (Object o : page) {
                add(c, (Map<String, Object>) o);
            }
            if (page.size() < PAGE_SIZE) {
                page = null;
            } else if (pageNo == MAX_PAGES) {
                c.truncated = true;
                c.totalFiles = toCount(((Map<String, Object>) git.readPullRequest(c.prNumber, '')).get('changed_files'));
                page = null;
            } else {
                pageNo++;
                page = filesPage(git, c.prNumber, pageNo);
            }
        }
    }

    private static List<Object> filesPage(RlyGitHub git, Integer prNumber, Integer pageNo) {
        return (List<Object>) git.readPullRequest(prNumber, '/files?per_page=' + PAGE_SIZE + '&page=' + pageNo);
    }

    private static void add(Changes c, Map<String, Object> raw) {
        FileChange f = new FileChange();
        f.filename = toText(raw.get('filename'));
        f.status = toText(raw.get('status'));
        f.additions = toCount(raw.get('additions'));
        f.deletions = toCount(raw.get('deletions'));
        f.patch = toText(raw.get('patch'));
        f.previousFilename = toText(raw.get('previous_filename'));
        f.url = c.filesUrl == null || f.filename == null ? c.filesUrl : c.filesUrl + '#diff-' + anchor(f.filename);
        f.note = String.isBlank(f.patch) ? 'No preview: open in ' + c.provider + '.' : null;
        c.additions += f.additions;
        c.deletions += f.deletions;
        c.files.add(f);
    }

    // The files view's anchor of a file: the SHA-256 of its path, in hex.
    private static String anchor(String filename) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(filename)));
    }

    private static String toText(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Integer toCount(Object value) {
        return value == null ? 0 : Integer.valueOf(value);
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
