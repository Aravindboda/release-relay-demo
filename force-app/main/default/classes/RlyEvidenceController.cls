/**
 * @description Evidence for change requests and audits. saveEvidence builds a release's evidence document
 * (RlyEvidenceHtml), turns it into a PDF and saves it to the release's Files (ContentVersion linked to the release,
 * visible to all users), returning its download address. exportCsv returns the Releases tab's filtered list (the same
 * filter as RlyReleasesController.listReleasesFor) as CSV text with the approval, deploy and rollback details (a release
 * rolled back in an org has Status "Rolled back" and the org and time in their own columns). Both only read
 * releases, so they work in a sandbox copy of the hub too. Files are created in system mode: every Release Relay user
 * may save evidence of a release they can open.
 */
public with sharing class RlyEvidenceController {

    private static final List<String> CSV_HEADER = new List<String>{ 'REL', 'Title', 'Route', 'Raised by', 'Raised on', 'Status',
        'Approved by', 'Approved on', 'Via', 'Comment', 'Second approver', 'Deployed to', 'Deploy ids', 'PR url', 'Rolled back in', 'Rolled back on' };

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
     * @description The Releases tab's filtered list as CSV text.
     * @param filterJson {"raisedById", "state", "searchText"} as for RlyReleasesController.listReleasesFor
     * @return the CSV (a header line, then one line per release)
     */
    @AuraEnabled
    public static String exportCsv(String filterJson) {
        try {
            List<RLY_Release__c> listed = RlyReleaseQuery.releasesFor(RlyReleaseQuery.parse(filterJson));
            Map<Id, RLY_Release__c> details = new SystemAccess().details(new Map<Id, RLY_Release__c>(listed).keySet());
            List<String> lines = new List<String>{ csvLine(CSV_HEADER) };
            for (RLY_Release__c r : listed) {
                lines.add(csvLine(columns(details.get(r.Id))));
            }
            return String.join(lines, '\r\n');
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static List<String> columns(RLY_Release__c r) {
        List<String> deployIds = new List<String>();
        for (String deployId : new List<String>{ RlyEvidenceText.validationOf(r.Validation_Result__c).deployId,
                RlyEvidenceText.deployOf(r.Deploy_Result__c).deployId }) {
            if (String.isNotBlank(deployId)) {
                deployIds.add(deployId);
            }
        }
        List<String> out = new List<String>{ r.Name, r.Title__c, nameOf(r.Source_Org__r) + ' → ' + nameOf(r.Target_Org__r),
            r.CreatedBy == null ? null : r.CreatedBy.Name, stamp(r.CreatedDate), rolledBack(r) ? 'Rolled back' : r.Status__c,
            r.Approved_By__r == null ? null : r.Approved_By__r.Name, stamp(r.Approved_On__c), r.Approved_Via__c, r.Approval_Comment__c,
            r.Second_Approved_By__r == null ? null : r.Second_Approved_By__r.Name,
            r.Status__c == 'Deployed' ? nameOf(r.Target_Org__r) : null, String.join(deployIds, ' '), r.PR_URL__c };
        out.addAll(rolledBack(r) ? new List<String>{ nameOf(r.Rollback_Org__r), stamp(r.Rollback_On__c) } : new List<String>{ null, null });
        return out;
    }

    private static Boolean rolledBack(RLY_Release__c r) {
        return r.Rollback_Status__c == RlyRollbackState.ROLLED_BACK;
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

    private static String stamp(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd HH:mm');
    }

    private static String nameOf(RLY_Org__c org) {
        return org == null ? '' : org.Name;
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
         * @description The CSV's fields of some releases.
         * @param ids the releases
         * @return the releases by Id
         */
        public Map<Id, RLY_Release__c> details(Set<Id> ids) {
            return new Map<Id, RLY_Release__c>([SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name,
                    CreatedBy.Name, CreatedDate, Approved_By__r.Name, Approved_On__c, Approved_Via__c, Approval_Comment__c,
                    Second_Approved_By__r.Name, Validation_Result__c, Deploy_Result__c, PR_URL__c, Rollback_Status__c,
                    Rollback_Org__r.Name, Rollback_On__c
                FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]);
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
