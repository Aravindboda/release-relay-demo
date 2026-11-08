/**
 * @description Build 55: Edit a file on the release page. Every file of an open release can be opened: the target
 * branch's copy, the release branch's copy (what will be deployed, editable) and, where Compare can read it, the source
 * org's copy (the page reads that one through RlyCompareController, as Compare on Review does). Lines that reference a
 * package are marked on the page. Save edit commits the file to the release branch through the Git provider's file API
 * (RlyGit.putFile: GitHub and GitLab), adds "Edited by <user>: <file>" to History and runs the checks again, as Check
 * again does (mode check). Who: the person who raised it or an admin (as Cancel release), only while it is open and no
 * run is going (Checks failed or Ready for approval, with its pull request). The release branch's copy is read again
 * before the commit: a file that changed since it was opened is refused. Callouts first (the read, the commit, the run,
 * the Slack card), then the saves.
 */
public with sharing class RlyFileEdit {

    /** @description Event_Type__c of the History event. */
    public static final String EVENT = 'File_Edited';
    /** @description What the page shows first. */
    public class Files {
        /** @description The current user may edit (open, no run going, the raiser or an admin). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description Why not, or null. */
        @AuraEnabled public String whyNot;
        /** @description The release's name. */
        @AuraEnabled public String releaseName;
        /** @description The release branch (what will be deployed). */
        @AuraEnabled public String releaseBranch;
        /** @description The target branch. */
        @AuraEnabled public String targetBranch;
        /** @description The target org's name. */
        @AuraEnabled public String targetName;
        /** @description The source org. */
        @AuraEnabled public Id sourceOrgId;
        /** @description The source org's name. */
        @AuraEnabled public String sourceName;
        /** @description The source org's copy can be read (a developer org, or a stage that can raise releases). */
        @AuraEnabled public Boolean sourceReadable = false;
        /** @description The release's components (deletions left out). */
        @AuraEnabled public List<Item> items = new List<Item>();
        /** @description Every org's namespaces (empty when no org has a package). */
        @AuraEnabled public List<RlyReleaseStart.OrgPackages> packages = new List<RlyReleaseStart.OrgPackages>();
    }

    /** @description One component of the release. */
    public class Item {
        /** @description Type:Name. */
        @AuraEnabled public String key;
        /** @description The name. */
        @AuraEnabled public String name;
        /** @description The type. */
        @AuraEnabled public String type;
        /** @description Its files can be found on the branch. */
        @AuraEnabled public Boolean editable = false;
        /** @description Compare can read the source org's copy. */
        @AuraEnabled public Boolean comparable = false;
    }

    /** @description One file, both branches. */
    public class FileText {
        /** @description Path below the source path. */
        @AuraEnabled public String path;
        /** @description The release branch's copy (what will be deployed), or null. */
        @AuraEnabled public String release;
        /** @description The target branch's copy, or null. */
        @AuraEnabled public String target;
        /** @description Why it can't be shown, or null. */
        @AuraEnabled public String reason;
    }

    /** @description What Save edit sends. */
    public class EditRequest {
        /** @description The file, below the source path. */
        public String path;
        /** @description The new content. */
        public String content;
        /** @description The release branch's copy the edit started from. */
        public String expected;
    }

    /**
     * @description Whether the current user may edit the release's files now.
     * @param rel the release, with Status__c, PR_Number__c, Source_Branch__c and CreatedById
     * @return true when they may
     */
    public static Boolean mayEdit(RLY_Release__c rel) {
        return whyNot(rel) == null;
    }

    /**
     * @description The release's files for the page.
     * @param releaseId the release
     * @return the files view
     */
    @AuraEnabled
    public static Files files(Id releaseId) {
        try {
            RLY_Release__c rel = requireRelease(releaseId);
            Files f = new Files();
            f.whyNot = RlyHubGuard.isHub() ? whyNot(rel) : RlyHubGuard.COPY_MESSAGE;
            f.canEdit = f.whyNot == null;
            f.releaseName = rel.Name;
            f.releaseBranch = rel.Source_Branch__c;
            f.targetBranch = rel.Target_Branch__c;
            f.targetName = rel.Target_Org__r == null ? null : rel.Target_Org__r.Name;
            f.sourceOrgId = rel.Source_Org__c;
            f.sourceName = rel.Source_Org__r == null ? null : rel.Source_Org__r.Name;
            f.sourceReadable = RlyRaiseRoute.canRaiseFrom(RlyReleaseStore.org(rel.Source_Org__c));
            for (RLY_Release_Item__c i : RlyReleaseStore.items(rel.Id)) {
                if (i.Is_Deletion__c != true) {
                    f.items.add(RlyFileEditPaths.item(i.Metadata_Type__c, i.Component_Name__c));
                }
            }
            f.packages = RlyReleaseStart.orgPackages();
            return f;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description A component's files on the release branch and the target branch (callouts only).
     * @param releaseId the release
     * @param key Type:Name, one of the release's components
     * @return one entry per file, main file first
     */
    @AuraEnabled
    public static List<FileText> readFile(Id releaseId, String key) {
        try {
            RLY_Release__c rel = requireRelease(releaseId);
            RlyFileEditPaths.requireItem(RlyReleaseStore.items(rel.Id), key);
            RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
            RlyGit git = RlyGit.forConnection(conn);
            RlyCompareBranch onRelease = new RlyCompareBranch(git, conn.Source_Path__c, rel.Source_Branch__c);
            List<String> paths = RlyFileEditPaths.pathsFor(key);
            if (paths == null) {
                paths = onRelease.filesUnder(RlyCompareFiles.bundleFolder(key));
            }
            if (paths == null || paths.isEmpty()) {
                throw new RlyReleaseException('Its files can\'t be found on the release branch. Open the branch in Git.');
            }
            List<RlyCompareFiles.FileDiff> mine = onRelease.readPaths(paths);
            List<RlyCompareFiles.FileDiff> theirs = new RlyCompareBranch(git, conn.Source_Path__c, rel.Target_Branch__c).readPaths(paths);
            List<FileText> out = new List<FileText>();
            for (Integer n = 0; n < paths.size(); n++) {
                out.add(RlyFileEditPaths.fileText(paths[n], mine[n], theirs[n]));
            }
            return out;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
    }

    /**
     * @description Commits an edited file to the release branch, records it in History and runs the checks again.
     * @param releaseId the release
     * @param editJson an EditRequest as JSON: path (one of the release's files), content, and expected (the release
     * branch's copy the edit started from: refused when the branch has another now)
     * @return the release, as the page shows it
     */
    @AuraEnabled
    public static RlyReleasesController.Detail saveFile(Id releaseId, String editJson) {
        try {
            EditRequest req = String.isBlank(editJson) ? null : (EditRequest) JSON.deserialize(editJson, EditRequest.class);
            commitEdit(releaseId, req);
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e);
        }
        return RlyReleasesController.getRelease(releaseId);
    }

    /**
     * @description See saveFile: the commit (callouts: the file read again, the commit, the run, the Slack card), then the
     * History event and the save.
     * @param releaseId the release
     * @param req the edit
     * @return the release as saved
     */
    public static RLY_Release__c commitEdit(Id releaseId, EditRequest req) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = requireRelease(releaseId);
        RlyFileEditRules.checkEdit(rel, req);
        RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
        RlyGit git = RlyGit.forConnection(conn);
        String repoPath = (String.isBlank(conn.Source_Path__c) ? '' : conn.Source_Path__c.trim().removeEnd('/') + '/') + req.path;
        if (!RlyFileEditRules.sameText(git.getFileRaw(repoPath, rel.Source_Branch__c), req.expected)) {
            throw new RlyReleaseException(req.path + ' changed on ' + rel.Source_Branch__c + ' since you opened it. Open it again to edit the latest copy.');
        }
        String link = git.putFile(new RlyGitFile(repoPath, rel.Source_Branch__c).withContent(
            EncodingUtil.base64Encode(Blob.valueOf(req.content)), (rel.Name + ': edit ' + req.path + ' in Release Relay by ' + UserInfo.getName()).left(250)));
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        RlyApprovalRuns.startChecks(rel, conn, 'check');
        RlySlackCardSync.notifyChange(before, rel);
        RlyReleaseLog.add(rel, EVENT, 'Edited by ' + UserInfo.getName() + ': ' + req.path).inOrg(rel.Target_Org__c)
            .byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(link);
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        return rel;
    }

    /**
     * @description Why the current user can't edit the release's files now, or null when they can (RlyFileEditRules).
     * @param rel the release
     * @return the reason, or null
     */
    public static String whyNot(RLY_Release__c rel) {
        return RlyFileEditRules.whyNot(rel);
    }

    private static RLY_Release__c requireRelease(Id releaseId) {
        RLY_Release__c rel = RlyReleaseStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('That release isn\'t there any more.');
        }
        return rel;
    }
}
