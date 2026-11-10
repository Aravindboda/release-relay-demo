/**
 * @description A developer org's records for a data run (RlyDataRuns): the pipeline has no sign-in to a developer org,
 * so the page sends its records a page at a time: each call reads one page of one object through the org's REST API
 * (the run's own export query, then the org's next-page cursor) and commits it to the results branch as
 * data-inbox/DAT-…/<object index>-<page>.json, the same file the pipeline's export job writes. Callouts only (no DML),
 * so the page can call it again and again; RlyDataRuns.runExported starts the dry run after the last page.
 */
public with sharing class RlyDataExport {

    private static final Pattern CURSOR_PATTERN = Pattern.compile('^/services/data/v\\d{1,3}\\.\\d{1,2}/query/[A-Za-z0-9-]{1,80}$');
    private static final Integer PAGE_SIZE = 2000;

    /** @description What the page asks for. */
    public class Ask {
        /** @description The run. */
        public String runId;
        /** @description The object's position in the data set (from 0). */
        public Integer index;
        /** @description The page's number for this object (from 1). */
        public Integer pageNo;
        /** @description The next page's address from the last call, or blank for the first page. */
        public String cursor;
    }

    /** @description One sent page of records. */
    public class Part {
        /** @description The next page's address, or null when the object is done. */
        @AuraEnabled public String nextCursor;
        /** @description Records in this page. */
        @AuraEnabled public Integer count = 0;
    }

    /**
     * @description Sends one page of one object's records from a developer org to the results branch.
     * @param p which object and page
     * @return the sent part
     */
    public static Part send(Ask p) {
        RLY_Data_Run__c run = RlyDataRules.requireStatus(p == null ? null : p.runId, RlyDataStore.EXPORTING);
        RlyDataRules.requireRequester(run);
        RlyDataSet.Definition d = RlyDataSet.parse(run.Data_Set__r.Definition__c);
        if (!isValid(p, d.objects.size())) {
            throw new RlyReleaseException('That part of the export isn\'t valid.');
        }
        RlyDataSet.Item item = d.objects[p.index];
        String path = String.isBlank(p.cursor) ? RlyOrgSession.queryPath(RlyDataSet.queryOf(item)) : checkedCursor(p.cursor);
        Map<String, Object> res = (Map<String, Object>) RlyOrgSession.getJson(RlyReleaseStore.org(run.Source_Org__c), path);
        List<Object> records = withoutAttributes(res.get('records'));
        Part part = new Part();
        part.count = records.size();
        part.nextCursor = res.get('done') == true || p.pageNo * PAGE_SIZE >= RlyDataRuns.MAX_RECORDS ? null : (String) res.get('nextRecordsUrl');
        String body = JSON.serialize(new Map<String, Object>{ 'objectName' => item.objectName, 'index' => p.index, 'records' => records });
        RlyComparePipelineInput.gitHub().putFile(new RlyGitFile(RlyDataRuns.INBOX + p.runId + '/' + String.valueOf(p.index).leftPad(2, '0')
            + '-' + String.valueOf(p.pageNo).leftPad(3, '0') + '.json', RlyPipelineRun.RESULTS_BRANCH)
            .withContent(EncodingUtil.base64Encode(Blob.valueOf(body)), p.runId + ': ' + item.objectName + ' part ' + p.pageNo));
        return part;
    }

    /**
     * @description A query's next page address, checked: only the org's own REST query cursors.
     * @param cursor nextRecordsUrl
     * @return the address
     */
    public static String checkedCursor(String cursor) {
        String c = cursor.trim();
        if (!CURSOR_PATTERN.matcher(c).matches()) {
            throw new RlyReleaseException('That page of records isn\'t valid any more: start the run again.');
        }
        return c;
    }

    /**
     * @description Records without their "attributes" entry.
     * @param records the REST answer's records
     * @return the records
     */
    public static List<Object> withoutAttributes(Object records) {
        List<Object> out = new List<Object>();
        for (Object o : records instanceof List<Object> ? (List<Object>) records : new List<Object>()) {
            if (o instanceof Map<String, Object>) {
                Map<String, Object> m = ((Map<String, Object>) o).clone();
                m.remove('attributes');
                out.add(m);
            }
        }
        return out;
    }

    // An object of the set, and a page within the most records sent per object.
    private static Boolean isValid(Ask p, Integer objectCount) {
        Boolean indexOk = p.index != null && p.index >= 0 && p.index < objectCount;
        return indexOk && p.pageNo != null && p.pageNo >= 1 && p.pageNo <= RlyDataRuns.MAX_RECORDS / PAGE_SIZE;
    }
}
