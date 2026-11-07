/**
 * @description Evidence for change requests and audits. saveEvidence builds a release's evidence document
 * (RlyEvidenceHtml), turns it into a PDF and saves it to the release's Files (ContentVersion linked to the release,
 * visible to all users), returning its download address. exportCsvPart returns the Releases tab's filtered list (the
 * same filter as RlyReleasesController.listReleasesFor) as CSV text a part at a time (RlyEvidenceCsv: approval, deploy
 * and rollback details and the files on its manual steps, listed, not embedded); exportCsv returns it whole. Both only read
 * releases, so they work in a sandbox copy of the hub too. Files are created in system mode: every Release Relay user
 * may save evidence of a release they can open.
 */
public with sharing class RlyEvidenceController {

    /** @description The saved evidence file. */
    public class EvidenceFile {
        /** @description The file (ContentDocument). */
        @AuraEnabled public Id contentDocumentId;
        /** @description Where the page downloads it. */
        @AuraEnabled public String downloadUrl;
        /** @description Its title, for example "REL-00012 evidence 2026-10-31 14:05". */
        @AuraEnabled public String title;
    }

    /**
     * @description Builds the release's evidence PDF and saves it to the release's Files.
     * @param releaseId the release
     * @return the file, with its download address
     */
    @AuraEnabled
    public static EvidenceFile saveEvidence(Id releaseId) {
        try {
            RlyEvidenceHtml.Source src = new RlyEvidenceHtml.Source();
            src.rel = RlyReleaseStore.release(releaseId);
            if (src.rel == null) {
                throw new RlyReleaseException('Release not found.');
            }
            SystemAccess access = new SystemAccess();
            src.items = RlyReleaseStore.items(releaseId);
            src.runs = access.runs(releaseId);
            src.events = RlyReleaseLog.eventsOf(new Set<Id>{ releaseId });
            src.files = RlyStepFileEvidence.evidenceRows(src.rel, src.events);
            EvidenceFile f = new EvidenceFile();
            f.title = src.rel.Name + ' evidence ' + src.madeOn.format('yyyy-MM-dd HH:mm');
            f.contentDocumentId = access.saveFile(releaseId, f.title, Blob.toPdf(RlyEvidenceHtml.build(src)));
            f.downloadUrl = '/sfc/servlet.shepherd/document/download/' + f.contentDocumentId;
            return f;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The Releases tab's filtered list as CSV text, whole (RlyEvidenceCsv.whole).
     * @param filterJson {"raisedById", "state", "searchText"} as for RlyReleasesController.listReleasesFor
     * @return the CSV (a header line, then one line per release)
     */
    @AuraEnabled
    public static String exportCsv(String filterJson) {
        try {
            return RlyEvidenceCsv.whole(filterJson);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description One part of the Releases tab's CSV (RlyEvidenceCsv.PART_SIZE releases); the page joins the parts.
     * @param filterJson the filter, as for exportCsv
     * @param offset where the part starts (0 for the first, then the last part's nextOffset)
     * @return the part's text (the first starts with the header), the next offset (null at the end) and the total
     */
    @AuraEnabled
    public static RlyEvidenceCsv.CsvPart exportCsvPart(String filterJson, Integer offset) {
        try {
            return RlyEvidenceCsv.part(filterJson, offset);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description One CSV line: every value quoted, quotes doubled; a value starting with = + - @ gets a leading
     * apostrophe so a spreadsheet doesn't run it as a formula.
     * @param values the values (null is empty)
     * @return the line
     */
    public static String csvLine(List<String> values) {
        List<String> out = new List<String>();
        for (String v : values) {
            String text = v == null ? '' : v;
            if (text.length() > 0 && '=+-@'.contains(text.left(1))) {
                text = '\'' + text;
            }
            out.add('"' + text.replace('"', '""') + '"');
        }
        return String.join(out, ',');
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }

    /** @description Releases, their manual step runs and Files are shared hub records: read and saved in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description A release's manual step runs, by org and order.
         * @param releaseId the release
         * @return the runs
         */
        public List<RLY_Manual_Step_Run__c> runs(Id releaseId) {
            return [SELECT Id, Org__r.Name, Step__r.Title__c, Step__r.Timing__c, Status__c, Done_By__r.Name, Done_On__c, Note__c
                    FROM RLY_Manual_Step_Run__c WHERE Release__c = :releaseId
                    WITH SYSTEM_MODE ORDER BY Org__r.Name, Order__c ASC NULLS LAST, Name ASC LIMIT 2000];
        }

        /**
         * @description Saves a PDF to a release's Files, visible to all users.
         * @param releaseId the release
         * @param title the file's title
         * @param pdf the PDF
         * @return the file's ContentDocument Id
         */
        public Id saveFile(Id releaseId, String title, Blob pdf) {
            ContentVersion v = new ContentVersion(Title = title, PathOnClient = title + '.pdf', VersionData = pdf);
            insert as system v;
            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id WITH SYSTEM_MODE].ContentDocumentId;
            insert as system new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = releaseId, ShareType = 'V',
                Visibility = 'AllUsers');
            return docId;
        }
    }
}
