/**
 * @description Custom fields of a developer org read one page at a time through the Tooling API (CustomField), for
 * when listMetadata of CustomField fails or its answer is too large (orgs with thousands of fields, managed packages
 * included). Each call reads one page (the org's batch, up to 2,000 rows); the next page's address (nextRecordsUrl)
 * goes back to the page as the cursor, so no call grows with the org.
 *
 * Object names: the query asks for EntityDefinition.QualifiedApiName (the object's full API name, suffix included:
 * __c, __mdt, __e, __b, __x). If the org refuses that relationship, it asks again without it and names the object
 * from TableEnumOrId: a standard object's name as it is, a custom object's Id (01I…) through Tooling CustomObject,
 * whose DeveloperName has no suffix, so __c is assumed there (fields of custom metadata types, platform events, big
 * objects and external objects then carry __c; Find deleted components compares objects without their suffix).
 */
public with sharing class RlyFieldPages {

    private static final String COLUMNS = 'Id, DeveloperName, NamespacePrefix, TableEnumOrId, LastModifiedDate, LastModifiedById';
    private static final String OBJECT_COLUMN = ', EntityDefinition.QualifiedApiName';
    private static final String CUSTOM_OBJECT_PREFIX = '01I';
    private static final Integer IDS_PER_QUERY = 100;

    /** @description One custom field. */
    public class Field {
        /** @description Object.Field__c (namespace included). */
        public String fullName;
        /** @description Its namespace, or null. */
        public String namespacePrefix;
        /** @description Its last change. */
        public Datetime modifiedOn;
        /** @description Who changed it last (Id). */
        public String modifiedById;
    }

    /** @description One page of fields and the cursor to the next. */
    public class Batch {
        /** @description The fields. */
        public List<Field> fields = new List<Field>();
        /** @description The next page's address, or null after the last page. */
        public String nextCursor;
    }

    /**
     * @description One page of unmanaged custom fields changed since a moment (the change listing's fallback).
     * @param org the developer org
     * @param since the earliest change, or null for any time
     * @param cursor the page to read (from the last answer), or blank for the first
     * @return the page
     */
    public static Batch changedSince(RLY_Org__c org, Datetime since, String cursor) {
        String filter = ' WHERE NamespacePrefix = null'
            + (since == null ? '' : ' AND LastModifiedDate >= ' + since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        return read(org, filter, cursor);
    }

    /**
     * @description One page of every custom field, managed ones included (Find deleted components).
     * @param org the developer org
     * @param cursor the page to read (from the last answer), or blank for the first
     * @return the page
     */
    public static Batch every(RLY_Org__c org, String cursor) {
        return read(org, '', cursor);
    }

    // One page: the first (with the filter) or the one the cursor names.
    private static Batch read(RLY_Org__c org, String filter, String cursor) {
        Map<String, Object> body = String.isBlank(cursor) ? firstPage(org, filter)
            : (Map<String, Object>) RlyOrgSession.getJson(org, RlyChangePages.checkedCursor(cursor));
        List<Object> rows = RlyChangeFinder.rowsOf(body);
        Map<String, String> objectNames = customObjectNames(org, unnamedObjectIds(rows));
        Batch b = new Batch();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            String objectName = objectOf(r, objectNames);
            if (String.isBlank(objectName)) {
                continue;
            }
            Field f = new Field();
            f.namespacePrefix = r.get('NamespacePrefix') == null ? null : String.valueOf(r.get('NamespacePrefix'));
            f.fullName = objectName + '.' + (String.isBlank(f.namespacePrefix) ? '' : f.namespacePrefix + '__')
                + String.valueOf(r.get('DeveloperName')) + '__c';
            f.modifiedOn = RlyChangeFinder.timeOf(r.get('LastModifiedDate'));
            f.modifiedById = r.get('LastModifiedById') == null ? null : String.valueOf(r.get('LastModifiedById'));
            b.fields.add(f);
        }
        b.nextCursor = body.get('done') == true || body.get('nextRecordsUrl') == null ? null : String.valueOf(body.get('nextRecordsUrl'));
        return b;
    }

    // The first page, with the object's full name; again without it when the org doesn't take that relationship.
    private static Map<String, Object> firstPage(RLY_Org__c org, String filter) {
        try {
            return (Map<String, Object>) RlyOrgSession.getJson(org,
                RlyOrgSession.toolingQueryPath('SELECT ' + COLUMNS + OBJECT_COLUMN + ' FROM CustomField' + filter));
        } catch (RlyOrgSession.SignInException e) {
            return (Map<String, Object>) RlyOrgSession.getJson(org, RlyOrgSession.toolingQueryPath('SELECT ' + COLUMNS + ' FROM CustomField' + filter));
        }
    }

    // The object a field row belongs to: its EntityDefinition's name, a standard object's name, or a custom object's.
    private static String objectOf(Map<String, Object> r, Map<String, String> objectNames) {
        Object entity = r.get('EntityDefinition');
        if (entity instanceof Map<String, Object> && ((Map<String, Object>) entity).get('QualifiedApiName') != null) {
            return String.valueOf(((Map<String, Object>) entity).get('QualifiedApiName'));
        }
        String table = r.get('TableEnumOrId') == null ? '' : String.valueOf(r.get('TableEnumOrId'));
        return table.startsWith(CUSTOM_OBJECT_PREFIX) ? objectNames.get(table.left(15)) : table;
    }

    // The custom object Ids (01I…, quoted) of rows without EntityDefinition, each once.
    private static List<String> unnamedObjectIds(List<Object> rows) {
        List<String> ids = new List<String>();
        Set<String> seen = new Set<String>();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            String table = r.get('TableEnumOrId') == null ? '' : String.valueOf(r.get('TableEnumOrId'));
            if (r.get('EntityDefinition') == null && table.startsWith(CUSTOM_OBJECT_PREFIX) && seen.add(table.left(15))) {
                ids.add('\'' + String.escapeSingleQuotes(table) + '\'');
            }
        }
        return ids;
    }

    // Names of custom objects by their 15-character Id (Tooling CustomObject: no suffix there, so __c), IDS_PER_QUERY per query.
    private static Map<String, String> customObjectNames(RLY_Org__c org, List<String> ids) {
        Map<String, String> out = new Map<String, String>();
        for (Integer i = 0; i < ids.size(); i += IDS_PER_QUERY) {
            List<String> part = new List<String>();
            for (Integer j = i; j < Math.min(i + IDS_PER_QUERY, ids.size()); j++) {
                part.add(ids[j]);
            }
            String soql = 'SELECT Id, DeveloperName, NamespacePrefix FROM CustomObject WHERE Id IN (' + String.join(part, ',') + ')';
            for (Object o : RlyChangeFinder.rowsOf(RlyOrgSession.getJson(org, RlyOrgSession.toolingQueryPath(soql)))) {
                Map<String, Object> c = (Map<String, Object>) o;
                String ns = c.get('NamespacePrefix') == null ? '' : String.valueOf(c.get('NamespacePrefix')) + '__';
                out.put(String.valueOf(c.get('Id')).left(15), ns + String.valueOf(c.get('DeveloperName')) + '__c');
            }
        }
        return out;
    }
}
