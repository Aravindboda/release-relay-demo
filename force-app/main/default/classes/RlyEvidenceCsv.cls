/**
 * @description The Releases tab's CSV (RlyEvidenceController.exportCsvPart), built PART_SIZE releases at a
 * time so a big list never holds every release's check and deploy results at once: the list itself is the light rows
 * of RlyReleaseQuery (up to 200), and for each part only the CSV's fields are read. The deploy ids come from the
 * validation and deploy results, each read in its own query for the part's releases and scanned for "deployId" (not
 * parsed), so at most one long field per release of the part is in memory. Columns: approval, deploy and rollback
 * details (a release rolled back in an org has Status "Rolled back" and the org and time in their own columns) and,
 * last, the files on its manual steps.
 */
public with sharing class RlyEvidenceCsv {

    /** @description Releases per part. */
    public static final Integer PART_SIZE = 20;

    private static final List<String> CSV_HEADER = new List<String>{ 'REL', 'Title', 'Tickets', 'Route', 'Raised by', 'Raised on', 'Status',
        'Approved by', 'Approved on', 'Via', 'Comment', 'Second approver', 'Deployed to', 'Deploy ids', 'PR url', 'Rolled back in', 'Rolled back on', 'Files' };
    private static final String DEPLOY_ID_KEY = '"deployId"';

    /** @description One part of the CSV. */
    public class CsvPart {
        /** @description The part's lines (the first part starts with the header line), joined with CRLF. */
        @AuraEnabled public String text;
        /** @description Where the next part starts, or null after the last one. */
        @AuraEnabled public Integer nextOffset;
        /** @description How many releases the CSV has. */
        @AuraEnabled public Integer total;
    }

    /**
     * @description One part of the CSV.
     * @param filterJson {"raisedById", "state", "searchText"} as for RlyReleasesController.listReleasesFor
     * @param offset where the part starts (0 for the first)
     * @return the part
     */
    public static CsvPart part(String filterJson, Integer offset) {
        List<RLY_Release__c> listed = RlyReleaseQuery.releasesFor(RlyReleaseQuery.parse(filterJson));
        Integer start = offset == null || offset < 0 ? 0 : offset;
        CsvPart p = new CsvPart();
        p.total = listed.size();
        List<Id> ids = new List<Id>();
        for (Integer i = start; i < Math.min(start + PART_SIZE, listed.size()); i++) {
            ids.add(listed[i].Id);
        }
        p.nextOffset = start + PART_SIZE < listed.size() ? start + PART_SIZE : null;
        List<String> lines = start == 0 ? new List<String>{ RlyEvidenceController.csvLine(CSV_HEADER) } : new List<String>();
        lines.addAll(lines(ids));
        p.text = String.join(lines, '\r\n');
        return p;
    }

    /**
     * @description The deploy id in a check or deploy result, found by scanning (the result isn't parsed).
     * @param resultJson Validation_Result__c or Deploy_Result__c
     * @return the id, or null
     */
    public static String deployIdIn(String resultJson) {
        if (String.isBlank(resultJson)) {
            return null;
        }
        Integer key = resultJson.indexOf(DEPLOY_ID_KEY);
        Integer colon = key < 0 ? -1 : resultJson.indexOf(':', key + DEPLOY_ID_KEY.length());
        if (colon < 0) {
            return null;
        }
        String after = resultJson.substring(colon + 1).left(80).trim();
        if (!after.startsWith('"')) {
            return null;
        }
        Integer close = after.indexOf('"', 1);
        String value = close < 0 ? null : after.substring(1, close);
        return String.isBlank(value) ? null : value;
    }

    // The part's lines, in list order.
    private static List<String> lines(List<Id> ids) {
        List<String> out = new List<String>();
        if (ids.isEmpty()) {
            return out;
        }
        Set<Id> idSet = new Set<Id>(ids);
        SystemAccess access = new SystemAccess();
        Map<Id, RLY_Release__c> details = access.details(idSet);
        Map<Id, String> checked = access.validationDeployIds(idSet);
        Map<Id, String> deployed = access.deployDeployIds(idSet);
        Map<Id, String> files = RlyStepFileEvidence.csvFiles(details.values());
        for (Id i : ids) {
            List<String> cells = columns(details.get(i), checked.get(i), deployed.get(i));
            cells.add(files.get(i));
            out.add(RlyEvidenceController.csvLine(cells));
        }
        return out;
    }

    private static List<String> columns(RLY_Release__c r, String checkId, String deployId) {
        List<String> deployIds = new List<String>();
        for (String one : new List<String>{ checkId, deployId }) {
            if (String.isNotBlank(one)) {
                deployIds.add(one);
            }
        }
        List<String> out = new List<String>{ r.Name, r.Title__c, RlyWorkLinks.withLinks(r.Work_Items__c), nameOf(r.Source_Org__r) + ' → ' + nameOf(r.Target_Org__r),
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

    private static String stamp(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd HH:mm');
    }

    private static String nameOf(RLY_Org__c org) {
        return org == null ? '' : org.Name;
    }

    /** @description Releases are shared hub records: the CSV's fields are read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description The CSV's short fields of some releases (not the long results).
         * @param ids the releases
         * @return the releases by Id
         */
        public Map<Id, RLY_Release__c> details(Set<Id> ids) {
            return new Map<Id, RLY_Release__c>([SELECT Id, Name, Title__c, Work_Items__c, Status__c, Source_Org__r.Name, Target_Org__r.Name,
                    CreatedBy.Name, CreatedDate, Approved_By__r.Name, Approved_On__c, Approved_Via__c, Approval_Comment__c,
                    Second_Approved_By__r.Name, PR_URL__c, Rollback_Status__c, Rollback_Org__r.Name, Rollback_On__c,
                    Carried_Releases__c
                FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]);
        }

        /**
         * @description The check-only deploy's id of each release.
         * @param ids the releases
         * @return release Id to deploy id (only those that have one)
         */
        public Map<Id, String> validationDeployIds(Set<Id> ids) {
            Map<Id, String> out = new Map<Id, String>();
            for (RLY_Release__c r : [SELECT Id, Validation_Result__c FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]) {
                putIfFound(out, r.Id, deployIdIn(r.Validation_Result__c));
            }
            return out;
        }

        /**
         * @description The deploy's id of each release.
         * @param ids the releases
         * @return release Id to deploy id (only those that have one)
         */
        public Map<Id, String> deployDeployIds(Set<Id> ids) {
            Map<Id, String> out = new Map<Id, String>();
            for (RLY_Release__c r : [SELECT Id, Deploy_Result__c FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]) {
                putIfFound(out, r.Id, deployIdIn(r.Deploy_Result__c));
            }
            return out;
        }

        private void putIfFound(Map<Id, String> out, Id key, String value) {
            if (value != null) {
                out.put(key, value);
            }
        }
    }
}
