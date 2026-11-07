/**
 * @description The change listing of New Release step 2 in pages, so no call grows with the org (RlyChangePartsController):
 *   tracked  source tracking, one page of the query per call (the next page's address is the cursor)
 *   folders  a folder type (Report…): FOLDERS_PER_CALL folders per call (the next folder's position is the cursor), so
 *            none is skipped
 *   fields   custom fields through the Tooling API (RlyFieldPages), for when listMetadata of CustomField fails
 * Callouts only.
 */
public with sharing class RlyChangePages {

    /** @description Folders read per call. */
    public static final Integer FOLDERS_PER_CALL = 30;

    private static final Pattern CURSOR = Pattern.compile('^/services/data/v\\d{1,3}\\.\\d{1,2}/(tooling/)?query/[A-Za-z0-9-]{1,80}$');
    private static final Pattern OFFSET = Pattern.compile('^\\d{1,5}$');

    /** @description What a page call reads: the org, since when, and which page. */
    public class Ask {
        /** @description The developer org. */
        public RLY_Org__c org;
        /** @description The earliest change, or null. */
        public Datetime since;
        /** @description The page to read (from the last answer), or blank for the first. */
        public String cursor;

        /**
         * @description What to read.
         * @param org the developer org
         * @param since the earliest change, or null
         * @param cursor the page to read, or blank for the first
         */
        public Ask(RLY_Org__c org, Datetime since, String cursor) {
            this.org = org;
            this.since = since;
            this.cursor = cursor;
        }
    }

    /** @description One page of changes and the cursor to the next. */
    public class ChangePage {
        /** @description The changes. */
        @AuraEnabled public List<RlyChangeFinder.Change> changes = new List<RlyChangeFinder.Change>();
        /** @description Pass it back for the next page; null after the last one. */
        @AuraEnabled public String nextCursor;
    }

    /**
     * @description A query's next page address, checked: only the org's own query cursors are read.
     * @param cursor nextRecordsUrl from the last page
     * @return the address
     */
    public static String checkedCursor(String cursor) {
        String c = cursor == null ? '' : cursor.trim();
        if (!CURSOR.matcher(c).matches()) {
            throw new RlyReleaseException('That page of results isn\'t valid any more: read the org again.');
        }
        return c;
    }

    /**
     * @description One page of source tracking changes.
     * @param ask the org, since when and which page
     * @return the page
     */
    public static ChangePage tracked(Ask ask) {
        String path = String.isBlank(ask.cursor) ? RlyOrgSession.toolingQueryPath(trackedSoql(ask.since)) : checkedCursor(ask.cursor);
        Map<String, Object> body = (Map<String, Object>) RlyOrgSession.getJson(ask.org, path);
        ChangePage p = new ChangePage();
        p.changes = trackedChanges(ask.org, RlyChangeFinder.rowsOf(body));
        p.nextCursor = nextOf(body);
        return p;
    }

    /**
     * @description The changes in one run of FOLDERS_PER_CALL folders of a folder type (and the folders themselves on
     * the first page).
     * @param ask the org, since when and the first folder's position (blank: 0)
     * @param type a folder-based type such as Report
     * @return the page
     */
    public static ChangePage folders(Ask ask, String type) {
        String folderType = RlyMetadata.FOLDER_TYPE.get(type);
        if (folderType == null) {
            throw new RlyMetadata.MetadataException(type + ' isn\'t a folder type.');
        }
        Integer offset = String.isBlank(ask.cursor) ? 0 : offsetOf(ask.cursor);
        List<RlyMetadata.FileProp> unmanaged = new List<RlyMetadata.FileProp>();
        List<RlyMetadata.FileProp> listed = RlyMetadata.listFiles(ask.org, new List<RlyMetadata.Query>{ new RlyMetadata.Query(folderType, null) });
        for (RlyMetadata.FileProp f : listed) {
            if (!RlyChangeFinder.isManaged(f)) {
                unmanaged.add(f);
            }
        }
        List<RlyMetadata.Query> queries = new List<RlyMetadata.Query>();
        for (Integer i = offset; i < Math.min(offset + FOLDERS_PER_CALL, unmanaged.size()); i++) {
            queries.add(new RlyMetadata.Query(type, unmanaged[i].fullName));
        }
        ChangePage p = new ChangePage();
        if (offset == 0) {
            p.changes.addAll(RlyChangeFinder.changesOf(unmanaged, ask.since));
        }
        p.changes.addAll(RlyChangeFinder.changesOf(RlyMetadata.listFiles(ask.org, queries), ask.since));
        p.nextCursor = offset + FOLDERS_PER_CALL < unmanaged.size() ? String.valueOf(offset + FOLDERS_PER_CALL) : null;
        return p;
    }

    /**
     * @description One page of custom field changes through the Tooling API (managed-package fields left out).
     * @param ask the org, since when and which page
     * @return the page
     */
    public static ChangePage fields(Ask ask) {
        RlyFieldPages.Batch b = RlyFieldPages.changedSince(ask.org, ask.since, ask.cursor);
        Set<String> userIds = new Set<String>();
        for (RlyFieldPages.Field f : b.fields) {
            userIds.add(f.modifiedById);
        }
        Map<String, String> names = RlyChangeFinder.userNamesOf(ask.org, userIds);
        ChangePage p = new ChangePage();
        for (RlyFieldPages.Field f : b.fields) {
            RlyChangeFinder.Change c = RlyChangeFinder.changeOf('CustomField', f.fullName);
            c.modifiedOn = f.modifiedOn;
            c.modifiedBy = names.get(f.modifiedById);
            c.deleted = false;
            p.changes.add(c);
        }
        p.nextCursor = b.nextCursor;
        return p;
    }

    /**
     * @description The source tracking query: changes since the date, newest first, at most RlyChangeFinder.MAX_ITEMS.
     * @param since the earliest change, or null
     * @return the SOQL
     */
    private static String trackedSoql(Datetime since) {
        return 'SELECT MemberName, MemberType, IsNameObsolete, LastModifiedDate, LastModifiedById FROM SourceMember'
            + (since == null ? '' : ' WHERE LastModifiedDate >= ' + since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))
            + ' ORDER BY LastModifiedDate DESC LIMIT ' + RlyChangeFinder.MAX_ITEMS;
    }

    /**
     * @description SourceMember rows as changes, with who changed each.
     * @param org the developer org
     * @param rows the query's records
     * @return the changes
     */
    private static List<RlyChangeFinder.Change> trackedChanges(RLY_Org__c org, List<Object> rows) {
        Set<String> userIds = new Set<String>();
        for (Object o : rows) {
            userIds.add(String.valueOf(((Map<String, Object>) o).get('LastModifiedById')));
        }
        Map<String, String> names = RlyChangeFinder.userNamesOf(org, userIds);
        List<RlyChangeFinder.Change> out = new List<RlyChangeFinder.Change>();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            RlyChangeFinder.Change c = RlyChangeFinder.changeOf(String.valueOf(r.get('MemberType')), String.valueOf(r.get('MemberName')));
            c.modifiedBy = names.get(String.valueOf(r.get('LastModifiedById')));
            c.modifiedOn = RlyChangeFinder.timeOf(r.get('LastModifiedDate'));
            c.deleted = r.get('IsNameObsolete') == true;
            out.add(c);
        }
        return out;
    }

    private static Integer offsetOf(String cursor) {
        if (!OFFSET.matcher(cursor.trim()).matches()) {
            throw new RlyReleaseException('That page of results isn\'t valid any more: read the org again.');
        }
        return Integer.valueOf(cursor.trim());
    }

    private static String nextOf(Map<String, Object> body) {
        return body.get('done') == true || body.get('nextRecordsUrl') == null ? null : String.valueOf(body.get('nextRecordsUrl'));
    }
}
