/**
 * @description Reads and writes for files on manual steps (RlyStepFiles): the links of steps and runs, the files
 * themselves, the steps with their release's lock fields and the runs with their org. Files, steps and runs are shared
 * hub records like the releases they belong to: read and written in system mode in the private inner without sharing
 * class. Callers check the rules first (RlyStepFiles, RlyStepFileGuard).
 */
public with sharing class RlyStepFileStore {

    private static final Set<String> PREVIEWABLE = new Set<String>{ 'pdf', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'svg', 'webp' };

    /**
     * @description The files linked to these steps and runs, per record.
     * @param recordIds the steps and runs
     * @return the rows by step or run (missing means none)
     */
    public static Map<Id, List<RlyStepFiles.FileRow>> rowsByRecord(Set<Id> recordIds) {
        Map<Id, List<RlyStepFiles.FileRow>> out = new Map<Id, List<RlyStepFiles.FileRow>>();
        List<ContentDocumentLink> links = recordIds.isEmpty() ? new List<ContentDocumentLink>() : new SystemAccess().linksOf(recordIds);
        for (ContentDocumentLink l : links) {
            RlyStepFiles.FileRow f = rowOf(l.ContentDocument);
            f.recordId = l.LinkedEntityId;
            if (!out.containsKey(f.recordId)) {
                out.put(f.recordId, new List<RlyStepFiles.FileRow>());
            }
            out.get(f.recordId).add(f);
        }
        return out;
    }

    /**
     * @description A record's rows from rowsByRecord, or an empty list.
     * @param byRecord the rows by record
     * @param recordId the record
     * @return the rows
     */
    public static List<RlyStepFiles.FileRow> rowsOf(Map<Id, List<RlyStepFiles.FileRow>> byRecord, Id recordId) {
        return byRecord.containsKey(recordId) ? byRecord.get(recordId) : new List<RlyStepFiles.FileRow>();
    }

    /**
     * @description One file as a row.
     * @param d the file, with Title, FileExtension, ContentSize, OwnerId, CreatedBy.Name and CreatedDate
     * @return the row
     */
    public static RlyStepFiles.FileRow rowOf(ContentDocument d) {
        RlyStepFiles.FileRow f = new RlyStepFiles.FileRow();
        f.documentId = d.Id;
        f.extension = String.isBlank(d.FileExtension) ? '' : d.FileExtension.toLowerCase();
        f.title = RlyStepFiles.nameOf(d.Title, d.FileExtension);
        f.sizeBytes = d.ContentSize;
        f.sizeText = RlyStepFiles.sizeText(d.ContentSize);
        f.createdBy = d.CreatedBy?.Name;
        f.createdOn = d.CreatedDate;
        f.ownerId = d.OwnerId;
        f.previewable = PREVIEWABLE.contains(f.extension);
        f.downloadUrl = RlyStepFiles.DOWNLOAD_PATH + d.Id;
        return f;
    }

    /**
     * @description Steps with their release's lock and owner fields.
     * @param stepIds the steps
     * @return the steps by Id, with Release__r
     */
    public static Map<Id, RLY_Manual_Step__c> stepsWithRelease(Set<Id> stepIds) {
        return stepIds.isEmpty() ? new Map<Id, RLY_Manual_Step__c>() : new SystemAccess().steps(stepIds);
    }

    /**
     * @description Runs with their org, step and release.
     * @param runIds the runs
     * @return the runs by Id
     */
    public static Map<Id, RLY_Manual_Step_Run__c> runsById(Set<Id> runIds) {
        return runIds.isEmpty() ? new Map<Id, RLY_Manual_Step_Run__c>() : new SystemAccess().runs(runIds);
    }

    /**
     * @description The runs of some releases' deploys, by org and order.
     * @param releaseIds the releases
     * @return the runs, with Org__r.Name and Step__r.Title__c
     */
    public static List<RLY_Manual_Step_Run__c> runsOfReleases(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new List<RLY_Manual_Step_Run__c>() : new SystemAccess().runsOfReleases(releaseIds);
    }

    /**
     * @description Files by Id.
     * @param docIds the files
     * @return the files, with Title, FileExtension, ContentSize and OwnerId
     */
    public static Map<Id, ContentDocument> docsById(Set<Id> docIds) {
        return docIds.isEmpty() ? new Map<Id, ContentDocument>() : new SystemAccess().docs(docIds);
    }

    /**
     * @description The current user's own files among these.
     * @param docIds the files
     * @return the files the current user owns, by Id
     */
    public static Map<Id, ContentDocument> ownDocs(Set<Id> docIds) {
        Map<Id, ContentDocument> out = new Map<Id, ContentDocument>();
        for (ContentDocument d : docsById(docIds).values()) {
            if (d.OwnerId == UserInfo.getUserId()) {
                out.put(d.Id, d);
            }
        }
        return out;
    }

    /**
     * @description The links of some files (to any record).
     * @param docIds the files
     * @return the links, with ContentDocument.Title, FileExtension and OwnerId
     */
    public static List<ContentDocumentLink> linksOfDocs(Set<Id> docIds) {
        return docIds.isEmpty() ? new List<ContentDocumentLink>() : new SystemAccess().linksOfDocs(docIds);
    }

    /**
     * @description A viewer link to a step or run for all internal users (not saved).
     * @param docId the file
     * @param recordId the step or run
     * @return the link
     */
    public static ContentDocumentLink viewerLink(Id docId, Id recordId) {
        return new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = recordId, ShareType = 'V', Visibility = 'AllUsers');
    }

    /**
     * @description Saves links (RlyStepFileGuard checks them).
     * @param links the links
     */
    public static void insertLinks(List<ContentDocumentLink> links) {
        if (!links.isEmpty()) {
            new SystemAccess().insertLinks(links);
        }
    }

    /**
     * @description Deletes links (RlyStepFileGuard checks them).
     * @param links the links
     */
    public static void deleteLinks(List<ContentDocumentLink> links) {
        new SystemAccess().deleteLinks(links);
    }

    /**
     * @description Deletes files.
     * @param docs the files
     */
    public static void deleteDocs(List<ContentDocument> docs) {
        new SystemAccess().deleteDocs(docs);
    }

    /** @description Files, steps and runs are shared hub records: read and written in system mode, after the checks. */
    private without sharing class SystemAccess {

        /**
         * @description The links of some steps and runs, with the file's fields.
         * @param recordIds the steps and runs
         * @return the links
         */
        public List<ContentDocumentLink> linksOf(Set<Id> recordIds) {
            return [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Id, ContentDocument.Title, ContentDocument.FileExtension,
                           ContentDocument.ContentSize, ContentDocument.OwnerId, ContentDocument.CreatedBy.Name, ContentDocument.CreatedDate
                    FROM ContentDocumentLink WHERE LinkedEntityId IN :recordIds WITH SYSTEM_MODE LIMIT 2000];
        }

        /**
         * @description See RlyStepFileStore.linksOfDocs.
         * @param docIds the files
         * @return the links
         */
        public List<ContentDocumentLink> linksOfDocs(Set<Id> docIds) {
            return [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.OwnerId
                    FROM ContentDocumentLink WHERE ContentDocumentId IN :docIds WITH SYSTEM_MODE LIMIT 2000];
        }

        /**
         * @description See RlyStepFileStore.docsById.
         * @param docIds the files
         * @return the files by Id
         */
        public Map<Id, ContentDocument> docs(Set<Id> docIds) {
            return new Map<Id, ContentDocument>([SELECT Id, Title, FileExtension, ContentSize, OwnerId, CreatedBy.Name, CreatedDate
                                                 FROM ContentDocument WHERE Id IN :docIds WITH SYSTEM_MODE LIMIT 2000]);
        }

        /**
         * @description See RlyStepFileStore.stepsWithRelease.
         * @param stepIds the steps
         * @return the steps by Id
         */
        public Map<Id, RLY_Manual_Step__c> steps(Set<Id> stepIds) {
            return new Map<Id, RLY_Manual_Step__c>([SELECT Id, Title__c, Release__c, Release__r.Name, Release__r.Status__c,
                    Release__r.Approval_Status__c, Release__r.Approved_By__r.Name, Release__r.Approved_On__c, Release__r.CreatedById
                FROM RLY_Manual_Step__c WHERE Id IN :stepIds WITH SYSTEM_MODE LIMIT 2000]);
        }

        /**
         * @description See RlyStepFileStore.runsById.
         * @param runIds the runs
         * @return the runs by Id
         */
        public Map<Id, RLY_Manual_Step_Run__c> runs(Set<Id> runIds) {
            return new Map<Id, RLY_Manual_Step_Run__c>([SELECT Id, Release__c, Org__c, Org__r.Name, Step__c, Step__r.Title__c
                FROM RLY_Manual_Step_Run__c WHERE Id IN :runIds WITH SYSTEM_MODE LIMIT 2000]);
        }

        /**
         * @description See RlyStepFileStore.runsOfReleases.
         * @param releaseIds the releases
         * @return the runs
         */
        public List<RLY_Manual_Step_Run__c> runsOfReleases(Set<Id> releaseIds) {
            return [SELECT Id, Release__c, Org__c, Org__r.Name, Step__c, Step__r.Title__c
                    FROM RLY_Manual_Step_Run__c WHERE Release__c IN :releaseIds
                    WITH SYSTEM_MODE ORDER BY Org__r.Name, Order__c ASC NULLS LAST, Name ASC LIMIT 5000];
        }

        /**
         * @description See RlyStepFileStore.insertLinks.
         * @param links the links
         */
        public void insertLinks(List<ContentDocumentLink> links) {
            insert as system links;
        }

        /**
         * @description See RlyStepFileStore.deleteLinks.
         * @param links the links
         */
        public void deleteLinks(List<ContentDocumentLink> links) {
            delete as system links;
        }

        /**
         * @description See RlyStepFileStore.deleteDocs.
         * @param docs the files
         */
        public void deleteDocs(List<ContentDocument> docs) {
            delete as system docs;
        }
    }
}
