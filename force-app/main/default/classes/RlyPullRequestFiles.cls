/**
 * @description The Changes card on the release page: the files a release's pull request changes, read through the hub's
 * Git connection (RlyGitChanges: GitHub and, from build 45, GitLab list them; other providers get a message to open the
 * pull request). Build 37: one page of
 * files per call, without their patches (files, then filesPage while nextPage is set), so a big pull request never
 * holds every patch at once; a file's patch is read when it's opened (filePatch), cut at MAX_PATCH characters. Anyone
 * who can open the release can read them. No DML: callouts only.
 */
public with sharing class RlyPullRequestFiles {

    /** @description Files per page. */
    public static final Integer PAGE_SIZE = 30;
    /** @description Most pages: GitHub lists up to 3,000 files of a pull request. */
    public static final Integer MAX_PAGE = 100;
    /** @description Most characters of one file's patch shown. */
    public static final Integer MAX_PATCH = 20000;

    /** @description The provider of this call (start sets it). */
    private static RlyGitChanges reader;

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
        /** @description More files than GitHub lists (the first 3,000 are listed). */
        @AuraEnabled public Boolean truncated = false;
        /** @description How many files the pull request changes in all, when more than one page; otherwise null. */
        @AuraEnabled public Integer totalFiles;
        /** @description The next page to read (filesPage), or null when this was the last. */
        @AuraEnabled public Integer nextPage;
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
        /** @description The unified-diff patch: only from filePatch (null in the list). */
        @AuraEnabled public String patch;
        /** @description The provider has a patch for it (false: binary or too big). */
        @AuraEnabled public Boolean hasPatch = false;
        /** @description The page it's on, to read its patch. */
        @AuraEnabled public Integer pageNo;
        /** @description The path before a rename, or null. */
        @AuraEnabled public String previousFilename;
        /** @description Link to this file in the pull request's files view, or null. */
        @AuraEnabled public String url;
        /** @description Shown instead of a diff when there is no patch, or null. */
        @AuraEnabled public String note;
    }

    /**
     * @description The first page of a release's pull request files, without their patches.
     * @param releaseId the release (a release or a promotion with a pull request)
     * @return the changes, or a message when they can't be listed
     */
    @AuraEnabled
    public static Changes files(Id releaseId) {
        return filesPage(releaseId, 1);
    }

    /**
     * @description One page of a release's pull request files, without their patches.
     * @param releaseId the release
     * @param pageNo the page, from 1
     * @return the page's files and the next page, or a message when they can't be listed
     */
    @AuraEnabled
    public static Changes filesPage(Id releaseId, Integer pageNo) {
        try {
            checkPage(pageNo);
            Changes c = start(releaseId);
            if (c.available) {
                readPage(c, pageNo);
            }
            return c;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description One file's patch, read when it's opened (cut at MAX_PATCH characters, with a note).
     * @param releaseId the release
     * @param pageNo the page the file is on
     * @param filename the file's path
     * @return the file with its patch
     */
    @AuraEnabled
    public static FileChange filePatch(Id releaseId, Integer pageNo, String filename) {
        try {
            checkPage(pageNo);
            Changes c = start(releaseId);
            if (!c.available) {
                throw new RlyReleaseException(c.message);
            }
            for (Object o : filesOf(c, pageNo)) {
                Map<String, Object> raw = (Map<String, Object>) o;
                if (filename != null && filename.equals(RlyPullRequestFileRow.text(raw.get('filename')))) {
                    return RlyPullRequestFileRow.withPatch(listed(c, raw, pageNo), RlyPullRequestFileRow.text(raw.get('patch')), c.provider);
                }
            }
            throw new RlyReleaseException('That file isn\'t in the pull request any more: refresh the Changes tab.');
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // The release, its pull request and the Git connection; available = false with a message when nothing can be read.
    private static Changes start(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        Changes c = new Changes();
        c.targetName = rel.Target_Org__r?.Name;
        c.targetBranch = rel.Target_Branch__c;
        c.sourceName = rel.Source_Org__r?.Name;
        RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
        if (rel.PR_Number__c == null || conn == null) {
            c.message = rel.PR_Number__c == null ? 'This release has no pull request yet.' : 'Set up the Git connection first.';
            return c;
        }
        RlyGit git = RlyGit.forConnection(conn);
        c.provider = git.providerLabel();
        c.prNumber = rel.PR_Number__c.intValue();
        reader = RlyGitChanges.of(git);
        if (reader == null) {
            c.message = 'Changes are shown for GitHub and GitLab only; open the ' + git.changeRequestLabel().toLowerCase() + '.';
            return c;
        }
        c.filesUrl = reader.filesUrl(rel.PR_URL__c);
        c.available = true;
        return c;
    }

    // One page: its files without patches; a full first page reads the pull request's totals too.
    private static void readPage(Changes c, Integer pageNo) {
        List<Object> page = filesOf(c, pageNo);
        for (Object o : page) {
            FileChange f = listed(c, (Map<String, Object>) o, pageNo);
            c.additions += f.additions;
            c.deletions += f.deletions;
            c.files.add(f);
        }
        Boolean full = page.size() == PAGE_SIZE;
        c.nextPage = full && pageNo < MAX_PAGE ? pageNo + 1 : null;
        if (full && pageNo == 1) {
            Map<String, Object> pr = reader.totals(c.prNumber, c.additions, c.deletions);
            c.totalFiles = RlyPullRequestFileRow.count(pr.get('changed_files'));
            c.additions = RlyPullRequestFileRow.count(pr.get('additions'));
            c.deletions = RlyPullRequestFileRow.count(pr.get('deletions'));
            c.truncated = c.totalFiles > MAX_PAGE * PAGE_SIZE;
        }
    }

    private static List<Object> filesOf(Changes c, Integer pageNo) {
        return reader.page(c.prNumber, pageNo, PAGE_SIZE);
    }

    // A file of the list, linked at the provider's own anchor in its files view.
    private static FileChange listed(Changes c, Map<String, Object> raw, Integer pageNo) {
        FileChange f = RlyPullRequestFileRow.listed(c, raw, pageNo);
        f.url = reader.fileUrl(c.filesUrl, f.filename);
        return f;
    }

    private static void checkPage(Integer pageNo) {
        if (pageNo == null || pageNo < 1 || pageNo > MAX_PAGE) {
            throw new RlyReleaseException('Pages go from 1 to ' + MAX_PAGE + '.');
        }
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
