/**
 * @description The components the Profile access step offers under Add access (build 58.1): picked from the developer
 * org, never typed. One call per kind (a field list: one more per object): the org's object list (describe) for
 * objects, custom metadata types and custom settings, an object's fields that take field access, the PermissionSet
 * describe for system permissions, the tab list, and SOQL for classes, pages, record types, apps and custom permissions.
 */
public with sharing class RlyProfileAccessNames {

    private static final Integer MAX_NAMES = 2000;
    private static final String NAME = 'name';
    private static final String LABEL = 'label';
    private static final String PERMISSIONS = 'Permissions';

    /** @description One component to pick. */
    public class Pick {
        /** @description The row's key: Account.Region__c, Order__c, ApiEnabled… */
        @AuraEnabled public String key;
        /** @description Its label. */
        @AuraEnabled public String label;
        /** @description An object to open for its fields (field access only). */
        @AuraEnabled public Boolean opens = false;
    }

    /**
     * @description The components of a kind in the org.
     * @param org the developer org
     * @param section the kind (a profile section)
     * @param objectName for field access: the object whose fields to list; else null
     * @return the components, by key
     */
    public static List<Pick> find(RLY_Org__c org, String section, String objectName) {
        if (section == RlyProfileAccessRules.FIELDS) {
            return String.isBlank(objectName) ? objects(org, 'fields') : fields(org, objectName);
        }
        Map<String, List<String>> soql = new Map<String, List<String>>{
            RlyProfileAccessRules.CLASSES => new List<String>{ 'ApexClass', 'Name', 'Name', 'NamespacePrefix = null' },
            RlyProfileAccessRules.PAGES => new List<String>{ 'ApexPage', 'Name', 'MasterLabel', 'NamespacePrefix = null' },
            RlyProfileAccessRules.APPS => new List<String>{ 'AppMenuItem', 'Name', 'Label', 'Type = \'TabSet\'' },
            RlyProfileAccessRules.CUSTOM_PERMISSIONS => new List<String>{ 'CustomPermission', 'DeveloperName', 'MasterLabel', 'Id != null' } };
        if (soql.containsKey(section)) {
            return fromQuery(org, soql.get(section));
        }
        if (section == RlyProfileAccessRules.RECORD_TYPES || section == RlyProfileAccessRules.LAYOUTS) {
            return recordTypes(org, section == RlyProfileAccessRules.LAYOUTS);
        }
        if (section == RlyProfileAccessRules.TABS) {
            return tabs(org);
        }
        return section == RlyProfileAccessRules.SYSTEM_PERMISSIONS ? systemPermissions(org) : objects(org, section);
    }

    // [object, name field, label field, filter]: one query, ordered by name.
    private static List<Pick> fromQuery(RLY_Org__c org, List<String> q) {
        String columns = q[1] == q[2] ? q[1] : q[1] + ', ' + q[2];
        List<Pick> out = new List<Pick>();
        for (Object o : RlyChangeFinder.rowsOf(RlyOrgSession.getJson(org, RlyOrgSession.queryPath('SELECT ' + columns + ' FROM ' + q[0]
                + ' WHERE ' + q[3] + ' ORDER BY ' + q[1] + ' LIMIT ' + MAX_NAMES)))) {
            Map<String, Object> r = (Map<String, Object>) o;
            out.add(pick(String.valueOf(r.get(q[1])), String.valueOf(r.get(q[2]))));
        }
        return out;
    }

    // Objects from the org's object list: for objects, fields and master layouts the ones with page layouts; else
    // custom metadata types or custom settings.
    private static List<Pick> objects(RLY_Org__c org, String kind) {
        Map<String, Object> body = (Map<String, Object>) RlyOrgSession.getJson(org, '/services/data/v' + RlyOrgSession.API_VERSION + '/sobjects');
        List<Pick> out = new List<Pick>();
        for (Object o : (List<Object>) body.get('sobjects')) {
            Map<String, Object> s = (Map<String, Object>) o;
            String name = String.valueOf(s.get(NAME));
            if (RlyProfileAccessNameRules.objectFits(kind, name, s)) {
                Pick p = pick(name, String.valueOf(s.get(LABEL)));
                p.opens = kind == 'fields';
                out.add(p);
            }
        }
        return out;
    }

    // An object's fields that take field access (permissionable), as Object.Field.
    private static List<Pick> fields(RLY_Org__c org, String objectName) {
        if (!Pattern.matches('[A-Za-z][A-Za-z0-9_]{0,79}', objectName)) {
            throw new RlyReleaseException('"' + objectName.left(80) + '" isn\'t an object name.');
        }
        Map<String, Object> body = (Map<String, Object>) RlyOrgSession.getJson(org, '/services/data/v' + RlyOrgSession.API_VERSION
            + '/sobjects/' + objectName + '/describe');
        List<Pick> out = new List<Pick>();
        for (Object o : (List<Object>) body.get('fields')) {
            Map<String, Object> f = (Map<String, Object>) o;
            if (Boolean.valueOf(f.get('permissionable')) == true) {
                out.add(pick(objectName + '.' + f.get(NAME), String.valueOf(f.get(LABEL))));
            }
        }
        return out;
    }

    // Record types as Object.DeveloperName; for page layouts also each object (its master layout).
    private static List<Pick> recordTypes(RLY_Org__c org, Boolean withObjects) {
        List<Pick> out = new List<Pick>();
        for (Object o : RlyChangeFinder.rowsOf(RlyOrgSession.getJson(org, RlyOrgSession.queryPath(
                'SELECT SobjectType, DeveloperName, Name FROM RecordType WHERE IsActive = true ORDER BY SobjectType, DeveloperName LIMIT ' + MAX_NAMES)))) {
            Map<String, Object> r = (Map<String, Object>) o;
            out.add(pick(r.get('SobjectType') + '.' + r.get('DeveloperName'), r.get('SobjectType') + ': ' + r.get('Name')));
        }
        if (withObjects) {
            out.addAll(objects(org, 'layouts'));
        }
        return out;
    }

    private static List<Pick> tabs(RLY_Org__c org) {
        List<Pick> out = new List<Pick>();
        for (Object o : (List<Object>) RlyOrgSession.getJson(org, '/services/data/v' + RlyOrgSession.API_VERSION + '/tabs')) {
            Map<String, Object> t = (Map<String, Object>) o;
            String name = String.valueOf(t.get(NAME));
            if (RlyProfileAccessNameRules.TAB.matcher(name).matches()) {
                out.add(pick(name, String.valueOf(t.get(LABEL))));
            }
        }
        return out;
    }

    // System permissions: the Permissions… fields of PermissionSet, without the prefix.
    private static List<Pick> systemPermissions(RLY_Org__c org) {
        Map<String, Object> body = (Map<String, Object>) RlyOrgSession.getJson(org, '/services/data/v' + RlyOrgSession.API_VERSION
            + '/sobjects/PermissionSet/describe');
        List<Pick> out = new List<Pick>();
        for (Object o : (List<Object>) body.get('fields')) {
            Map<String, Object> f = (Map<String, Object>) o;
            String name = String.valueOf(f.get(NAME));
            if (name.startsWith(PERMISSIONS) && String.valueOf(f.get('type')) == 'boolean') {
                out.add(pick(name.removeStart(PERMISSIONS), String.valueOf(f.get(LABEL))));
            }
        }
        return out;
    }

    private static Pick pick(String key, String label) {
        Pick p = new Pick();
        p.key = key;
        p.label = String.isBlank(label) || label == 'null' ? key : label;
        return p;
    }
}
