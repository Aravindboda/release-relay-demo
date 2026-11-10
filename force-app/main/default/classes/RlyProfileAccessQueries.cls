/**
 * @description The queries of a profile access read (RlyProfileAccessReader): field, object, tab and system
 * permissions of the profiles, the Ids of the classes, pages, custom permissions, apps, custom metadata types and
 * custom settings asked, then their SetupEntityAccess. Names go 100 to a query (system permissions 40).
 */
public with sharing class RlyProfileAccessQueries {

    private static final Integer NAMES_PER_QUERY = 100;
    private static final Integer PERMISSIONS_PER_QUERY = 40;
    private static final String OWNED = ' WHERE Parent.IsOwnedByProfile = true AND Parent.Profile.Name IN ';
    /** @description Kind of the query of custom metadata types and settings (EntityDefinition). */
    public static final String KIND_ENTITY = 'entity';
    /** @description Kind of the SetupEntityAccess query. */
    public static final String KIND_ACCESS = 'access';

    /** @description One query of a composite request and how to read its rows. */
    public class Sub {
        /** @description The query's path. */
        public String url;
        /** @description The section it reads, or entity / access. */
        public String kind;
        /** @description The names it asks (system permissions: the permissions). */
        public List<String> names;
    }

    /**
     * @description Field, object, tab and system permissions, and the Ids of everything SetupEntityAccess holds.
     * @param rd the read
     * @return the queries
     */
    public static List<Sub> first(RlyProfileAccessRead rd) {
        List<Sub> subs = new List<Sub>();
        String owned = OWNED + rd.profileList();
        Map<String, String> starts = new Map<String, String>{
            RlyProfileAccessRules.FIELDS => 'SELECT Parent.Profile.Name, Field, PermissionsRead, PermissionsEdit FROM FieldPermissions'
                + owned + ' AND Field IN ',
            RlyProfileAccessRules.OBJECTS => 'SELECT Parent.Profile.Name, SobjectType, PermissionsCreate, PermissionsRead, PermissionsEdit, '
                + 'PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions' + owned + ' AND SobjectType IN ',
            RlyProfileAccessRules.TABS => 'SELECT Parent.Profile.Name, Name, Visibility FROM PermissionSetTabSetting' + owned + ' AND Name IN ',
            RlyProfileAccessRules.CLASSES => 'SELECT Id, Name FROM ApexClass WHERE Name IN ',
            RlyProfileAccessRules.PAGES => 'SELECT Id, Name FROM ApexPage WHERE Name IN ',
            RlyProfileAccessRules.CUSTOM_PERMISSIONS => 'SELECT Id, DeveloperName FROM CustomPermission WHERE DeveloperName IN ',
            RlyProfileAccessRules.APPS => 'SELECT ApplicationId, Name FROM AppMenuItem WHERE Type = \'TabSet\' AND Name IN ' };
        for (String section : new List<String>{ RlyProfileAccessRules.FIELDS, RlyProfileAccessRules.OBJECTS, RlyProfileAccessRules.TABS,
                RlyProfileAccessRules.CLASSES, RlyProfileAccessRules.PAGES, RlyProfileAccessRules.CUSTOM_PERMISSIONS, RlyProfileAccessRules.APPS }) {
            for (List<String> chunk : chunks(rd.keysOf(section), NAMES_PER_QUERY)) {
                subs.add(sub(starts.get(section) + quoted(chunk), section, chunk));
            }
        }
        subs.addAll(permissionQueries(rd));
        for (List<String> chunk : chunks(entityNames(rd), NAMES_PER_QUERY)) {
            subs.add(sub('SELECT DurableId, QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN ' + quoted(chunk), KIND_ENTITY, chunk));
        }
        return subs;
    }

    // System permissions are fields of the profile's own permission set (Permissions + the name).
    private static List<Sub> permissionQueries(RlyProfileAccessRead rd) {
        List<Sub> subs = new List<Sub>();
        for (List<String> chunk : chunks(rd.keysOf(RlyProfileAccessRules.SYSTEM_PERMISSIONS), PERMISSIONS_PER_QUERY)) {
            String columns = '';
            for (String n : chunk) {
                columns += ', Permissions' + n;
            }
            subs.add(sub('SELECT Profile.Name' + columns + ' FROM PermissionSet WHERE IsOwnedByProfile = true AND Profile.Name IN '
                + rd.profileList(), RlyProfileAccessRules.SYSTEM_PERMISSIONS, chunk));
        }
        return subs;
    }

    private static List<String> entityNames(RlyProfileAccessRead rd) {
        List<String> names = new List<String>();
        for (List<String> rowKeys : rd.rowsByEntity.values()) {
            names.add(rowKeys[0].substringAfter('|'));
        }
        return names;
    }

    /**
     * @description SetupEntityAccess of the Ids the first queries found.
     * @param rd the read
     * @return the queries (none when nothing was found)
     */
    public static List<Sub> access(RlyProfileAccessRead rd) {
        List<Sub> subs = new List<Sub>();
        for (List<String> chunk : chunks(new List<String>(rd.rowsById.keySet()), NAMES_PER_QUERY)) {
            subs.add(sub('SELECT Parent.Profile.Name, SetupEntityId FROM SetupEntityAccess' + OWNED + rd.profileList()
                + ' AND SetupEntityId IN ' + quoted(chunk), KIND_ACCESS, chunk));
        }
        return subs;
    }

    private static Sub sub(String soql, String kind, List<String> names) {
        Sub s = new Sub();
        s.url = RlyOrgSession.queryPath(soql);
        s.kind = kind;
        s.names = names;
        return s;
    }

    private static List<List<String>> chunks(List<String> values, Integer size) {
        List<List<String>> out = new List<List<String>>();
        for (Integer i = 0; i < values.size(); i += size) {
            List<String> chunk = new List<String>();
            for (Integer j = i; j < Math.min(i + size, values.size()); j++) {
                chunk.add(values[j]);
            }
            out.add(chunk);
        }
        return out;
    }

    /**
     * @description Values quoted for SOQL: ('A', 'B').
     * @param values the values
     * @return the list
     */
    public static String quoted(List<String> values) {
        List<String> q = new List<String>();
        for (String v : values) {
            q.add('\'' + String.escapeSingleQuotes(v) + '\'');
        }
        return '(' + String.join(q, ', ') + ')';
    }
}
