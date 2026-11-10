/**
 * @description The server check behind files on manual steps (RlyStepFiles), called by the one-line triggers
 * RlyContentDocumentLink (before insert, after insert, before delete) and RlyContentVersion (before insert). Only links
 * to an RLY_Manual_Step__c (step files) or an RLY_Manual_Step_Run__c (proof) are looked at; every other file is left
 * alone. Before insert: a step file needs the release not approved yet and the raiser or an admin; proof needs the
 * deployment team or an admin; allowed links become viewer links for all internal users (ShareType V, Visibility
 * AllUsers). After insert: History "Attached" or "Proof added". Before delete: the same rules (proof: the person who
 * added it or an admin), then History "Removed". A new version of a file that sits on a locked step is refused too.
 * Deleting the whole file from Files home does not run these triggers (Salesforce does not fire link triggers for it).
 * Reads go through RlyStepFileStore (system mode, its private inner without sharing class); History rows through
 * RlyReleaseLog. Synchronous, no async Apex.
 */
public with sharing class RlyStepFileGuard {

    // Event type for a step file, for proof, then the words for each: when a link is added, when it is removed.
    private static final List<String> ADDED = new List<String>{ RlyStepFiles.EVENT_ATTACHED, RlyStepFiles.EVENT_PROOF, 'Attached ', 'Proof added' };
    private static final List<String> REMOVED = new List<String>{ RlyStepFiles.EVENT_REMOVED, RlyStepFiles.EVENT_REMOVED, 'Removed ', 'Removed proof' };

    /** @description What the link rules need: the steps (with their release), the runs and the files. */
    private class Context {
        /** @description The steps linked, with Release__r. */
        public Map<Id, RLY_Manual_Step__c> steps = new Map<Id, RLY_Manual_Step__c>();
        /** @description The runs linked, with Org__r.Name and Step__r.Title__c. */
        public Map<Id, RLY_Manual_Step_Run__c> runs = new Map<Id, RLY_Manual_Step_Run__c>();
        /** @description The files, with Title, FileExtension and OwnerId. */
        public Map<Id, ContentDocument> docs = new Map<Id, ContentDocument>();
    }

    /**
     * @description The ContentDocumentLink trigger.
     * @param op the trigger operation
     * @param fresh Trigger.new (insert)
     * @param old Trigger.old (delete)
     */
    public static void onLinks(TriggerOperation op, List<ContentDocumentLink> fresh, List<ContentDocumentLink> old) {
        List<ContentDocumentLink> ours = ours(op == TriggerOperation.BEFORE_DELETE ? old : fresh);
        if (ours.isEmpty()) {
            return;
        }
        Context c = load(ours);
        if (op == TriggerOperation.BEFORE_INSERT) {
            beforeInsert(ours, c);
        } else if (op == TriggerOperation.AFTER_INSERT) {
            log(ours, c, false);
        } else if (op == TriggerOperation.BEFORE_DELETE) {
            log(refuse(ours, c, true), c, true);
        }
    }

    /**
     * @description The ContentVersion trigger (before insert): a new version of a file on a locked step is refused.
     * @param fresh Trigger.new
     */
    public static void onVersions(List<ContentVersion> fresh) {
        Set<Id> docIds = new Set<Id>();
        for (ContentVersion v : fresh) {
            docIds.add(v.ContentDocumentId);
        }
        docIds.remove(null);
        Set<Id> locked = lockedDocs(docIds);
        for (ContentVersion v : fresh) {
            if (locked.contains(v.ContentDocumentId)) {
                v.addError(RlyStepFiles.LOCK_MESSAGE);
            }
        }
    }

    // The files among these that sit on a step whose release is approved or later.
    private static Set<Id> lockedDocs(Set<Id> docIds) {
        Map<Id, Id> stepToDoc = new Map<Id, Id>();
        for (ContentDocumentLink l : RlyStepFileStore.linksOfDocs(docIds)) {
            if (RlyStepFiles.isStep(l.LinkedEntityId)) {
                stepToDoc.put(l.LinkedEntityId, l.ContentDocumentId);
            }
        }
        Set<Id> out = new Set<Id>();
        for (RLY_Manual_Step__c s : RlyStepFileStore.stepsWithRelease(stepToDoc.keySet()).values()) {
            if (RlyStepFiles.isLocked(s.Release__r)) {
                out.add(stepToDoc.get(s.Id));
            }
        }
        return out;
    }

    // Links to a step or a run; any other link is not ours.
    private static List<ContentDocumentLink> ours(List<ContentDocumentLink> rows) {
        List<ContentDocumentLink> out = new List<ContentDocumentLink>();
        for (ContentDocumentLink l : rows) {
            if (RlyStepFiles.isStep(l.LinkedEntityId) || RlyStepFiles.isRun(l.LinkedEntityId)) {
                out.add(l);
            }
        }
        return out;
    }

    private static Context load(List<ContentDocumentLink> links) {
        Set<Id> stepIds = new Set<Id>();
        Set<Id> runIds = new Set<Id>();
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
            if (RlyStepFiles.isStep(l.LinkedEntityId)) {
                stepIds.add(l.LinkedEntityId);
            } else {
                runIds.add(l.LinkedEntityId);
            }
        }
        Context c = new Context();
        c.steps = RlyStepFileStore.stepsWithRelease(stepIds);
        c.runs = RlyStepFileStore.runsById(runIds);
        c.docs = RlyStepFileStore.docsById(docIds);
        return c;
    }

    // Refuses what the rules don't allow; the allowed ones become viewer links for all internal users.
    private static void beforeInsert(List<ContentDocumentLink> links, Context c) {
        for (ContentDocumentLink l : refuse(links, c, false)) {
            l.ShareType = 'V';
            l.Visibility = 'AllUsers';
        }
    }

    // Adds an error to each link the rules refuse; returns the others.
    private static List<ContentDocumentLink> refuse(List<ContentDocumentLink> links, Context c, Boolean removing) {
        List<ContentDocumentLink> allowed = new List<ContentDocumentLink>();
        for (ContentDocumentLink l : links) {
            String refusal = refusalFor(l, c, removing);
            if (refusal == null) {
                allowed.add(l);
            } else {
                l.addError(refusal);
            }
        }
        return allowed;
    }

    private static String refusalFor(ContentDocumentLink l, Context c, Boolean removing) {
        if (RlyStepFiles.isStep(l.LinkedEntityId)) {
            RLY_Manual_Step__c step = c.steps.get(l.LinkedEntityId);
            return step == null ? null : RlyStepFiles.stepRefusal(step.Release__r);
        }
        return removing ? RlyStepFiles.proofRemoveRefusal(c.docs.get(l.ContentDocumentId)?.OwnerId) : RlyStepFiles.proofAddRefusal();
    }

    // History: Attached / Proof added (after insert) or Removed (before delete), on the step's or the run's release.
    private static void log(List<ContentDocumentLink> links, Context c, Boolean removing) {
        List<String> v = removing ? REMOVED : ADDED;
        for (ContentDocumentLink l : links) {
            ContentDocument d = c.docs.get(l.ContentDocumentId);
            String name = RlyStepFiles.nameOf(d.Title, d.FileExtension);
            RLY_Manual_Step__c s = c.steps.get(l.LinkedEntityId);
            RlyReleaseLog.Entry e = s != null ? stepEvent(s, name, v) : runEvent(c.runs.get(l.LinkedEntityId), name, v);
            e.byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(l.ContentDocumentId);
        }
        RlyReleaseLog.flush();
    }

    private static RlyReleaseLog.Entry stepEvent(RLY_Manual_Step__c s, String name, List<String> v) {
        return RlyReleaseLog.addFor(s.Release__c, v[0], v[2] + name + ' · ' + s.Title__c);
    }

    private static RlyReleaseLog.Entry runEvent(RLY_Manual_Step_Run__c r, String name, List<String> v) {
        return RlyReleaseLog.addFor(r.Release__c, v[1], v[3] + ' in ' + r.Org__r.Name + ' · ' + name + ' · ' + r.Step__r.Title__c)
            .inOrg(r.Org__c);
    }
}
