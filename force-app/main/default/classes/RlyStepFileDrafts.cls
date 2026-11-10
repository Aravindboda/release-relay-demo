/**
 * @description New Release's files on manual steps (RlyStepFiles). A step there has no Id yet: its files wait in the
 * raiser's own library (the upload's record-id is the raiser's user record: the builder's draft record) and Raise links
 * them to the saved steps in the same transaction (linkDrafts, synchronous). Until then the raiser lists them
 * (draftFiles) and removes them (removeDraft). RlyStepFileGuard checks every link again on the server and writes History.
 */
public with sharing class RlyStepFileDrafts {

    /**
     * @description Raise: links the files each New Release step carried (StepInput.files, in the raiser's own library)
     * to the step just saved. Only files the raiser owns; each file once per step.
     * @param steps the saved steps, in the order sent (flow steps after them)
     * @param inputs the steps as sent, or null
     */
    public static void linkDrafts(List<RLY_Manual_Step__c> steps, List<RlyManualSteps.StepInput> inputs) {
        List<Set<Id>> perStep = draftIds(steps, inputs);
        Set<Id> docIds = new Set<Id>();
        for (Set<Id> ids : perStep) {
            docIds.addAll(ids);
        }
        Map<Id, ContentDocument> mine = RlyStepFileStore.ownDocs(docIds);
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Integer i = 0; i < perStep.size(); i++) {
            for (Id docId : perStep[i]) {
                if (!mine.containsKey(docId)) {
                    throw new RlyReleaseException('A file on manual step ' + (i + 1) + ' isn\'t in your files any more. Remove it and attach it again.');
                }
                links.add(RlyStepFileStore.viewerLink(docId, steps[i].Id));
            }
        }
        RlyStepFileStore.insertLinks(links);
    }

    // The files each sent step carried, once each.
    private static List<Set<Id>> draftIds(List<RLY_Manual_Step__c> steps, List<RlyManualSteps.StepInput> inputs) {
        List<Set<Id>> out = new List<Set<Id>>();
        Integer n = inputs == null ? 0 : Math.min(inputs.size(), steps.size());
        for (Integer i = 0; i < n; i++) {
            out.add(inputs[i].files == null ? new Set<Id>() : new Set<Id>(inputs[i].files));
        }
        return out;
    }

    /**
     * @description New Release: the draft files the current user uploaded (in their own library).
     * @param docIds the files
     * @return the rows
     */
    public static List<RlyStepFiles.FileRow> draftFiles(List<Id> docIds) {
        List<RlyStepFiles.FileRow> out = new List<RlyStepFiles.FileRow>();
        Set<Id> asked = docIds == null ? new Set<Id>() : new Set<Id>(docIds);
        for (ContentDocument d : RlyStepFileStore.ownDocs(asked).values()) {
            RlyStepFiles.FileRow f = RlyStepFileStore.rowOf(d);
            f.canRemove = true;
            out.add(f);
        }
        return out;
    }

    /**
     * @description New Release: deletes a draft file the current user uploaded and no saved step or run holds.
     * @param docId the file
     */
    public static void removeDraft(Id docId) {
        Map<Id, ContentDocument> mine = RlyStepFileStore.ownDocs(new Set<Id>{ docId });
        if (!mine.containsKey(docId)) {
            throw new RlyReleaseException('Only the person who uploaded this file can remove it.');
        }
        if (onStepOrRun(RlyStepFileStore.linksOfDocs(new Set<Id>{ docId }))) {
            throw new RlyReleaseException('This file is on a saved manual step: remove it on the release page.');
        }
        RlyStepFileStore.deleteDocs(mine.values());
    }

    private static Boolean onStepOrRun(List<ContentDocumentLink> links) {
        for (ContentDocumentLink l : links) {
            if (RlyStepFiles.isStep(l.LinkedEntityId) || RlyStepFiles.isRun(l.LinkedEntityId)) {
                return true;
            }
        }
        return false;
    }

}
