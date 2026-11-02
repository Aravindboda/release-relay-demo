/**
 * @description Files on manual steps (build 34): the rules and the words. Standard Salesforce Files, no objects of our
 * own. A step file is a ContentDocumentLink whose LinkedEntityId is the RLY_Manual_Step__c (the instructions: a CSV to
 * load, a PDF of steps); it shows in every org on the route, in promotions (their runs point back at the step) and in
 * back promote orgs, and it locks once the step's release is approved (isLocked). Proof is a link to an
 * RLY_Manual_Step_Run__c: one org's run, so each org has its own, and it stays open after approval. Who: the raiser or an
 * admin adds and removes step files before approval (stepRefusal); the deployment team or an admin adds proof, the
 * person who added it or an admin removes it (proofAddRefusal, proofRemoveRefusal); anyone who can see the release
 * downloads. Links are viewer links (ShareType V, Visibility AllUsers). Reads and writes: RlyStepFileStore; the page's
 * actions: RlyStepFileActions; the server check and History: RlyStepFileGuard; evidence: RlyStepFileEvidence.
 */
public with sharing class RlyStepFiles {

    /** @description Why a step file can't be added, removed or replaced. */
    public static final String LOCK_MESSAGE = 'Files on this step are locked: the release is approved.';
    /** @description Event_Type__c of a step file attached. */
    public static final String EVENT_ATTACHED = 'File_Attached';
    /** @description Event_Type__c of a step file or proof removed. */
    public static final String EVENT_REMOVED = 'File_Removed';
    /** @description Event_Type__c of proof added to a run. */
    public static final String EVENT_PROOF = 'Proof_Added';
    /** @description Event_Type__c of a file downloaded from the Manual steps card. */
    public static final String EVENT_DOWNLOADED = 'File_Downloaded';
    /** @description Where a file downloads (plus its ContentDocument Id). */
    public static final String DOWNLOAD_PATH = '/sfc/servlet.shepherd/document/download/';

    private static final String STEP_RIGHTS = 'Step files can be added or removed by the person who raised the release, or an admin, until it is approved.';
    private static final String PROOF_RIGHTS = 'Only the deployment team or an admin can add proof.';
    private static final String PROOF_REMOVE = 'Only the person who added this proof, or an admin, can remove it.';
    private static final Set<String> APPROVED_OR_LATER = new Set<String>{
        'Approved', 'Merging', 'Merged', 'Deploying', 'Deployed', 'Deploy failed', 'Closed' };
    private static final Integer KB = 1024;

    /** @description One file on a step or a run, as the Manual steps card and the evidence list it. */
    public class FileRow {
        /** @description The file (ContentDocument). */
        @AuraEnabled public Id documentId;
        /** @description The step or run it is linked to (null for a New Release draft file). */
        @AuraEnabled public Id recordId;
        /** @description Its name, with its extension. */
        @AuraEnabled public String title;
        /** @description Its extension, lower case (csv, pdf…), or empty. */
        @AuraEnabled public String extension;
        /** @description Its size in bytes. */
        @AuraEnabled public Integer sizeBytes;
        /** @description Its size in words: 12 KB, 1.4 MB. */
        @AuraEnabled public String sizeText;
        /** @description Who uploaded it. */
        @AuraEnabled public String createdBy;
        /** @description When. */
        @AuraEnabled public Datetime createdOn;
        /** @description The org a proof file belongs to, or null for a step file. */
        @AuraEnabled public String orgName;
        /** @description The current user may remove it. */
        @AuraEnabled public Boolean canRemove = false;
        /** @description PDF or an image: the standard file preview opens it. */
        @AuraEnabled public Boolean previewable = false;
        /** @description Where it downloads. */
        @AuraEnabled public String downloadUrl;
        /** @description Who owns it (not sent to the page). */
        public transient Id ownerId;
    }

    /**
     * @description Whether a release's step files are locked: it is approved or later (merging, deployed, closed).
     * @param rel the release, with Status__c and Approval_Status__c
     * @return true when locked
     */
    public static Boolean isLocked(RLY_Release__c rel) {
        return rel != null && (rel.Approval_Status__c == 'Approved' || APPROVED_OR_LATER.contains(rel.Status__c));
    }

    /**
     * @description The lock's tooltip: "These are the files Priya Shah approved on Oct 31. To change them, reject the
     * release or raise a new one."
     * @param rel the release, with Approved_By__r.Name and Approved_On__c
     * @return the words
     */
    public static String lockText(RLY_Release__c rel) {
        RLY_Release__c r = rel == null ? new RLY_Release__c() : rel;
        String who = r.Approved_By__r == null ? 'the approver' : r.Approved_By__r.Name;
        String day = r.Approved_On__c == null ? '' : ' on ' + r.Approved_On__c.format('MMM d');
        return 'These are the files ' + who + ' approved' + day + '. To change them, reject the release or raise a new one.';
    }

    /**
     * @description Why the current user may not add or remove a file on a step of this release, or null when allowed.
     * @param rel the step's release, with Status__c, Approval_Status__c and CreatedById
     * @return the refusal, or null
     */
    public static String stepRefusal(RLY_Release__c rel) {
        if (isLocked(rel)) {
            return LOCK_MESSAGE;
        }
        return rel != null && (rel.CreatedById == UserInfo.getUserId() || RlyOrgController.isAdmin()) ? null : STEP_RIGHTS;
    }

    /**
     * @description Why the current user may not add proof to a run, or null when allowed.
     * @return the refusal, or null
     */
    public static String proofAddRefusal() {
        return RlyManualSteps.canCheck() ? null : PROOF_RIGHTS;
    }

    /**
     * @description Why the current user may not remove proof from a run, or null when allowed.
     * @param ownerId who owns the file
     * @return the refusal, or null
     */
    public static String proofRemoveRefusal(Id ownerId) {
        return ownerId == UserInfo.getUserId() || RlyOrgController.isAdmin() ? null : PROOF_REMOVE;
    }

    /**
     * @description Whether a record is a manual step.
     * @param recordId the record
     * @return true for an RLY_Manual_Step__c
     */
    public static Boolean isStep(Id recordId) {
        return recordId != null && recordId.getSObjectType() == RLY_Manual_Step__c.SObjectType;
    }

    /**
     * @description Whether a record is a manual step run.
     * @param recordId the record
     * @return true for an RLY_Manual_Step_Run__c
     */
    public static Boolean isRun(Id recordId) {
        return recordId != null && recordId.getSObjectType() == RLY_Manual_Step_Run__c.SObjectType;
    }

    /**
     * @description A file's name with its extension: "usa-contacts.csv".
     * @param title ContentDocument.Title
     * @param extension ContentDocument.FileExtension
     * @return the name
     */
    public static String nameOf(String title, String extension) {
        String t = String.isBlank(title) ? '' : title;
        if (String.isBlank(extension) || t.toLowerCase().endsWith('.' + extension.toLowerCase())) {
            return t;
        }
        return t + '.' + extension;
    }

    /**
     * @description A size in words: 900 B, 12 KB, 1.4 MB.
     * @param bytes the size
     * @return the words
     */
    public static String sizeText(Integer bytes) {
        Integer b = bytes == null ? 0 : bytes;
        if (b < KB) {
            return b + ' B';
        }
        if (b < KB * KB) {
            return Math.max(1, Math.round(b / 1024.0)) + ' KB';
        }
        return (Decimal.valueOf(b) / (KB * KB)).setScale(1) + ' MB';
    }
}
