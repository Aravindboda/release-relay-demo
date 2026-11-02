/**
 * @description What the release page does with files on manual steps (RlyStepFiles), through RlyManualStepController:
 * the board's files (fill: each step's files with its lock, each run's proof), removing a file and logging a download.
 * New Release's draft files: RlyStepFileDrafts. RlyStepFileGuard checks every link again on the server and writes History.
 */
public with sharing class RlyStepFileActions {

    private static final String NOT_ON_STEP = 'This file isn\'t on a manual step any more. Reload the page.';

    /**
     * @description Adds the files to a board: each step's files with its lock, each run's proof.
     * @param b the board (RlyManualStepBoard)
     */
    public static void fill(RlyManualSteps.StepBoard b) {
        Set<Id> recordIds = new Set<Id>();
        for (RlyManualSteps.StepRow s : b.steps) {
            recordIds.add(s.id);
        }
        Map<Id, RLY_Manual_Step__c> steps = RlyStepFileStore.stepsWithRelease(recordIds.clone());
        for (RlyManualSteps.OrgRuns o : b.orgs) {
            recordIds.addAll(runMap(o.runs).keySet());
        }
        Map<Id, List<RlyStepFiles.FileRow>> files = RlyStepFileStore.rowsByRecord(recordIds);
        for (RlyManualSteps.StepRow s : b.steps) {
            fillStep(s, steps.get(s.id), RlyStepFileStore.rowsOf(files, s.id));
        }
        Boolean proofer = RlyStepFiles.proofAddRefusal() == null;
        for (RlyManualSteps.OrgRuns o : b.orgs) {
            for (RlyManualSteps.RunRow r : o.runs) {
                fillRun(r, named(RlyStepFileStore.rowsOf(files, r.id), o.orgName), proofer);
            }
        }
    }

    private static Map<Id, RlyManualSteps.RunRow> runMap(List<RlyManualSteps.RunRow> runs) {
        Map<Id, RlyManualSteps.RunRow> out = new Map<Id, RlyManualSteps.RunRow>();
        for (RlyManualSteps.RunRow r : runs) {
            out.put(r.id, r);
        }
        return out;
    }

    private static void fillStep(RlyManualSteps.StepRow s, RLY_Manual_Step__c step, List<RlyStepFiles.FileRow> files) {
        RLY_Release__c rel = step?.Release__r;
        s.locked = RlyStepFiles.isLocked(rel);
        s.lockText = s.locked ? RlyStepFiles.lockText(rel) : null;
        s.canAttach = RlyStepFiles.stepRefusal(rel) == null;
        s.files = files;
        for (RlyStepFiles.FileRow f : files) {
            f.canRemove = s.canAttach;
        }
    }

    // Proof rows carry their org's name.
    private static List<RlyStepFiles.FileRow> named(List<RlyStepFiles.FileRow> files, String orgName) {
        for (RlyStepFiles.FileRow f : files) {
            f.orgName = orgName;
        }
        return files;
    }

    // A run's proof: the deployment team adds it; who added it (or an admin) removes it.
    private static void fillRun(RlyManualSteps.RunRow r, List<RlyStepFiles.FileRow> files, Boolean proofer) {
        r.canAddProof = proofer;
        r.proof = files;
        for (RlyStepFiles.FileRow f : files) {
            f.canRemove = proofer && RlyStepFiles.proofRemoveRefusal(f.ownerId) == null;
        }
    }

    /**
     * @description Removes a file from a step or a run (RlyStepFileGuard checks again and writes History). The file
     * itself is deleted too when the current user owns it and no other record holds it.
     * @param recordId the step or run
     * @param docId the file
     */
    public static void remove(Id recordId, Id docId) {
        List<ContentDocumentLink> allLinks = RlyStepFileStore.linksOfDocs(new Set<Id>{ docId });
        List<ContentDocumentLink> mine = linksTo(allLinks, recordId);
        if (mine.isEmpty()) {
            throw new RlyReleaseException(NOT_ON_STEP);
        }
        String refusal = refusalToRemove(recordId, mine[0].ContentDocument.OwnerId);
        if (refusal != null) {
            throw new RlyReleaseException(refusal);
        }
        RlyStepFileStore.deleteLinks(mine);
        if (mine[0].ContentDocument.OwnerId == UserInfo.getUserId() && recordLinks(allLinks) == mine.size()) {
            RlyStepFileStore.deleteDocs(new List<ContentDocument>{ new ContentDocument(Id = docId) });
        }
    }

    private static List<ContentDocumentLink> linksTo(List<ContentDocumentLink> links, Id recordId) {
        List<ContentDocumentLink> out = new List<ContentDocumentLink>();
        for (ContentDocumentLink l : links) {
            if (l.LinkedEntityId == recordId) {
                out.add(l);
            }
        }
        return out;
    }

    // How many records (not people's libraries) hold the file.
    private static Integer recordLinks(List<ContentDocumentLink> links) {
        Integer n = 0;
        for (ContentDocumentLink l : links) {
            n += l.LinkedEntityId.getSObjectType() == User.SObjectType ? 0 : 1;
        }
        return n;
    }

    // The same rules the guard applies, checked first so the page gets a plain message.
    private static String refusalToRemove(Id recordId, Id ownerId) {
        if (RlyStepFiles.isRun(recordId)) {
            return RlyStepFiles.proofRemoveRefusal(ownerId);
        }
        if (!RlyStepFiles.isStep(recordId)) {
            return NOT_ON_STEP;
        }
        RLY_Manual_Step__c step = RlyStepFileStore.stepsWithRelease(new Set<Id>{ recordId }).get(recordId);
        return RlyStepFiles.stepRefusal(step?.Release__r);
    }

    /**
     * @description Writes "Downloaded <file>" to a release's History (the card's Download button) and returns the address.
     * Downloads from Files home are not counted.
     * @param docId the file
     * @param releaseId the release whose page it was downloaded from
     * @param orgId the org tab it was downloaded in, or null
     * @return the download address
     */
    public static String logDownload(Id docId, Id releaseId, Id orgId) {
        String title;
        for (ContentDocumentLink l : RlyStepFileStore.linksOfDocs(new Set<Id>{ docId })) {
            if (RlyStepFiles.isStep(l.LinkedEntityId) || RlyStepFiles.isRun(l.LinkedEntityId)) {
                title = RlyStepFiles.nameOf(l.ContentDocument.Title, l.ContentDocument.FileExtension);
            }
        }
        if (title == null || releaseId == null) {
            throw new RlyReleaseException(NOT_ON_STEP);
        }
        RlyReleaseLog.addFor(releaseId, RlyStepFiles.EVENT_DOWNLOADED, 'Downloaded ' + title).inOrg(orgId)
            .byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(docId);
        RlyReleaseLog.flush();
        return RlyStepFiles.DOWNLOAD_PATH + docId;
    }

    /**
     * @description Whether a step still has files (a locked step with files can't be deleted).
     * @param stepId the step
     * @return true when it has files
     */
    public static Boolean hasFiles(Id stepId) {
        return RlyStepFileStore.rowsByRecord(new Set<Id>{ stepId }).containsKey(stepId);
    }
}
