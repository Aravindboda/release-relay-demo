/**
 * Finds what changed in a registered org, for the New Release Select screen.
 *   tracked      source tracking (SourceMember): exact changes and deletions, one query
 *   listed       Metadata API listMetadata for the given types, changed since a date
 *   inFolders    the same for a folder type (Report, Dashboard, EmailTemplate, Document)
 *   testClasses  which Apex classes are tests (@IsTest in the body)
 * Each change is tagged Custom or Standard. Managed-package components are left out.
 */
public with sharing class RlyChangeFinder {

    public static final Integer MAX_ITEMS = 3000;
    private static final Integer MAX_FOLDERS = 60;
    private static final Integer NAMES_PER_QUERY = 100;
    private static final Set<String> MANAGED = new Set<String>{ 'installed', 'installedEditable', 'released', 'deleted', 'deprecated', 'deprecatedEditable' };

    public class Change {
        @AuraEnabled public String key;
        @AuraEnabled public String type;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean standard;
        @AuraEnabled public Boolean deleted;
        @AuraEnabled public String modifiedBy;
        @AuraEnabled public Datetime modifiedOn;
    }

    /** Changes from source tracking since the date (all tracked changes when null). */
    public static List<Change> tracked(RLY_Org__c org, Datetime since) {
        String soql = 'SELECT MemberName, MemberType, IsNameObsolete, LastModifiedDate, LastModifiedById FROM SourceMember'
            + (since == null ? '' : ' WHERE LastModifiedDate >= ' + since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))
            + ' ORDER BY LastModifiedDate DESC LIMIT ' + MAX_ITEMS;
        List<Object> rows = records(RlyOrgSession.getJson(org, RlyOrgSession.queryPath(soql, true)));
        Set<String> userIds = new Set<String>();
        for (Object o : rows) {
            userIds.add(String.valueOf(((Map<String, Object>) o).get('LastModifiedById')));
        }
        Map<String, String> names = userNames(org, userIds);
        List<Change> out = new List<Change>();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            Change c = makeChange(String.valueOf(r.get('MemberType')), String.valueOf(r.get('MemberName')),
                names.get(String.valueOf(r.get('LastModifiedById'))), parseTime(r.get('LastModifiedDate')));
            c.deleted = r.get('IsNameObsolete') == true;
            out.add(c);
        }
        return out;
    }

    /** Changes of these types since the date (everything when null). */
    public static List<Change> listed(RLY_Org__c org, List<String> types, Datetime since) {
        List<RlyMetadata.Query> queries = new List<RlyMetadata.Query>();
        for (String t : types) {
            queries.add(new RlyMetadata.Query(t, null));
        }
        return toChanges(RlyMetadata.listFiles(org, queries), since);
    }

    /** Changes of a folder type: its folders, then the items in each folder. */
    public static List<Change> inFolders(RLY_Org__c org, String type, Datetime since) {
        String folderType = RlyMetadata.FOLDER_TYPE.get(type);
        if (folderType == null) {
            throw new RlyMetadata.MetadataException(type + ' isn\'t a folder type.');
        }
        List<RlyMetadata.FileProp> folders = RlyMetadata.listFiles(org, new List<RlyMetadata.Query>{ new RlyMetadata.Query(folderType, null) });
        List<RlyMetadata.Query> queries = new List<RlyMetadata.Query>();
        Integer count = 0;
        for (RlyMetadata.FileProp f : folders) {
            if (MANAGED.contains(f.manageableState) || count++ >= MAX_FOLDERS) {
                continue;
            }
            queries.add(new RlyMetadata.Query(type, f.fullName));
        }
        List<Change> out = toChanges(folders, since);
        out.addAll(toChanges(RlyMetadata.listFiles(org, queries), since));
        return out;
    }

    private static List<Change> toChanges(List<RlyMetadata.FileProp> props, Datetime since) {
        List<Change> out = new List<Change>();
        for (RlyMetadata.FileProp p : props) {
            if (MANAGED.contains(p.manageableState) || String.isNotBlank(p.namespacePrefix)) {
                continue;
            }
            if (since != null && (p.lastModifiedDate == null || p.lastModifiedDate < since)) {
                continue;
            }
            Change c = makeChange(p.type, p.fullName, p.lastModifiedByName, p.lastModifiedDate);
            c.deleted = false;
            out.add(c);
            if (out.size() >= MAX_ITEMS) {
                break;
            }
        }
        return out;
    }

    private static Change makeChange(String type, String name, String byName, Datetime modifiedOn) {
        Change c = new Change();
        c.type = type;
        c.name = name;
        c.key = type + ':' + name;
        c.standard = isStandard(type, name);
        c.modifiedBy = byName;
        c.modifiedOn = modifiedOn;
        return c;
    }

    /** Standard objects (Account), standard fields (Account.Industry) and standard picklists. */
    @TestVisible
    private static Boolean isStandard(String type, String name) {
        if (type == 'StandardValueSet') {
            return true;
        }
        if (type == 'CustomObject') {
            return !name.contains('__');
        }
        if (type == 'CustomField' && name.contains('.')) {
            return !name.substringAfter('.').contains('__');
        }
        return false;
    }

    /** Names of the given classes that are tests (@IsTest in the class body). */
    public static List<String> testClasses(RLY_Org__c org, List<String> classNames) {
        List<String> out = new List<String>();
        Pattern testMark = Pattern.compile('(?i)@istest\\b');
        for (Integer i = 0; i < classNames.size(); i += NAMES_PER_QUERY) {
            List<String> quoted = new List<String>();
            for (Integer j = i; j < Math.min(i + NAMES_PER_QUERY, classNames.size()); j++) {
                quoted.add('\'' + String.escapeSingleQuotes(classNames[j]) + '\'');
            }
            String soql = 'SELECT Name, Body FROM ApexClass WHERE NamespacePrefix = null AND Name IN (' + String.join(quoted, ',') + ')';
            for (Object o : records(RlyOrgSession.getJson(org, RlyOrgSession.queryPath(soql, true)))) {
                Map<String, Object> r = (Map<String, Object>) o;
                if (testMark.matcher(String.valueOf(r.get('Body'))).find()) {
                    out.add(String.valueOf(r.get('Name')));
                }
            }
        }
        return out;
    }

    private static Map<String, String> userNames(RLY_Org__c org, Set<String> ids) {
        Map<String, String> out = new Map<String, String>();
        ids.remove(null);
        ids.remove('null');
        if (ids.isEmpty()) {
            return out;
        }
        List<String> quoted = new List<String>();
        for (String i : ids) {
            quoted.add('\'' + String.escapeSingleQuotes(i) + '\'');
        }
        String soql = 'SELECT Id, Name FROM User WHERE Id IN (' + String.join(quoted, ',') + ')';
        for (Object o : records(RlyOrgSession.getJson(org, RlyOrgSession.queryPath(soql, false)))) {
            Map<String, Object> r = (Map<String, Object>) o;
            out.put(String.valueOf(r.get('Id')), String.valueOf(r.get('Name')));
            out.put(String.valueOf(r.get('Id')).left(15), String.valueOf(r.get('Name')));
        }
        return out;
    }

    private static List<Object> records(Object body) {
        Object rows = ((Map<String, Object>) body).get('records');
        return rows == null ? new List<Object>() : (List<Object>) rows;
    }

    private static Datetime parseTime(Object value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).replace('+0000', 'Z');
        return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
    }
}
