/**
 * @description Turns the rows an org's queries answer (FieldPermissions, ObjectPermissions, PermissionSetTabSetting,
 * the profile's own PermissionSet, the Id lookups for SetupEntityAccess) into profile access values, in the names a
 * profile file uses (readable, allowCreate, visibility, enabled…). Used by RlyProfileAccessReader.
 */
public with sharing class RlyProfileAccessRows {

    /** @description Sections whose components are found by Id first, then read through SetupEntityAccess. */
    public static final Set<String> ID_KINDS = new Set<String>{ RlyProfileAccessRules.CLASSES, RlyProfileAccessRules.PAGES,
        RlyProfileAccessRules.CUSTOM_PERMISSIONS, RlyProfileAccessRules.APPS };
    /** @description Every section read through SetupEntityAccess. */
    public static final Set<String> ID_SECTIONS = new Set<String>{ RlyProfileAccessRules.CLASSES, RlyProfileAccessRules.PAGES,
        RlyProfileAccessRules.CUSTOM_PERMISSIONS, RlyProfileAccessRules.APPS, RlyProfileAccessRules.METADATA_TYPES,
        RlyProfileAccessRules.SETTINGS };

    private static final String ENABLED = 'enabled';
    private static final String TRUE_TEXT = 'true';
    private static final String FALSE_TEXT = 'false';

    /**
     * @description The Id an Id lookup found.
     * @param kind the section asked
     * @param r the row
     * @return the Id (an app's ApplicationId)
     */
    public static String idOf(String kind, Map<String, Object> r) {
        Object id = kind == RlyProfileAccessRules.APPS ? r.get('ApplicationId') : r.get('Id');
        return id == null ? null : String.valueOf(id);
    }

    /**
     * @description The name an Id lookup found.
     * @param kind the section asked
     * @param r the row
     * @return the name (a custom permission's DeveloperName)
     */
    public static String nameOf(String kind, Map<String, Object> r) {
        return String.valueOf(kind == RlyProfileAccessRules.CUSTOM_PERMISSIONS ? r.get('DeveloperName') : r.get('Name'));
    }

    /**
     * @description The profile name of a row of a permission set object (Parent.Profile.Name) or of PermissionSet (Profile.Name).
     * @param r the row
     * @return the profile's name as Setup shows it, or null
     */
    public static String profileName(Map<String, Object> r) {
        Map<String, Object> parent = r.get('Parent') instanceof Map<String, Object> ? (Map<String, Object>) r.get('Parent') : r;
        Object profile = parent.get('Profile');
        return profile instanceof Map<String, Object> ? String.valueOf(((Map<String, Object>) profile).get('Name')) : null;
    }

    /**
     * @description Puts one answered row's values: field, object, tab or system permissions.
     * @param rd the read
     * @param s the query it answers
     * @param r the row
     */
    public static void put(RlyProfileAccessRead rd, RlyProfileAccessQueries.Sub s, Map<String, Object> r) {
        String profile = rd.profileByLabel.get(profileName(r));
        if (profile == null) {
            return;
        }
        if (s.kind == RlyProfileAccessRules.SYSTEM_PERMISSIONS) {
            for (String n : s.names) {
                rd.out.rows.put(rowKey(profile, s.kind, n), new Map<String, String>{ ENABLED => flag(r.get('Permissions' + n)) });
            }
            return;
        }
        Map<String, String> fieldOf = new Map<String, String>{ RlyProfileAccessRules.FIELDS => 'Field',
            RlyProfileAccessRules.OBJECTS => 'SobjectType', RlyProfileAccessRules.TABS => 'Name' };
        rd.out.rows.put(rowKey(profile, s.kind, String.valueOf(r.get(fieldOf.get(s.kind)))), valuesOf(s.kind, r));
    }

    // A field, object or tab row's values, in the profile file's names.
    private static Map<String, String> valuesOf(String section, Map<String, Object> r) {
        if (section == RlyProfileAccessRules.TABS) {
            return new Map<String, String>{ 'visibility' => String.valueOf(r.get('Visibility')) };
        }
        Map<String, String> columns = section == RlyProfileAccessRules.FIELDS
            ? new Map<String, String>{ 'readable' => 'PermissionsRead', 'editable' => 'PermissionsEdit' }
            : new Map<String, String>{ 'allowCreate' => 'PermissionsCreate', 'allowRead' => 'PermissionsRead', 'allowEdit' => 'PermissionsEdit',
                'allowDelete' => 'PermissionsDelete', 'viewAllRecords' => 'PermissionsViewAllRecords', 'modifyAllRecords' => 'PermissionsModifyAllRecords' };
        Map<String, String> out = new Map<String, String>();
        for (String name : columns.keySet()) {
            out.put(name, flag(r.get(columns.get(name))));
        }
        return out;
    }

    /**
     * @description The values of a row the org has nothing for: no access, a tab Hidden.
     * @param section the section
     * @return the values
     */
    public static Map<String, String> noAccess(String section) {
        if (section == RlyProfileAccessRules.TABS) {
            return new Map<String, String>{ 'visibility' => 'Hidden' };
        }
        Map<String, String> out = new Map<String, String>();
        for (String name : RlyProfileAccessRules.VALUES_OF.get(section)) {
            if (name != 'layout') {
                out.put(name, FALSE_TEXT);
            }
        }
        return out;
    }

    /**
     * @description The values of a component the profile has through SetupEntityAccess: enabled (an app: visible).
     * @param section the section
     * @return the values
     */
    public static Map<String, String> granted(String section) {
        return section == RlyProfileAccessRules.APPS ? new Map<String, String>{ 'visible' => TRUE_TEXT }
            : new Map<String, String>{ ENABLED => TRUE_TEXT };
    }

    /**
     * @description The key of a row: profile|section|key, the key in lower case.
     * @param profile the profile's metadata name
     * @param section the section
     * @param key the component
     * @return the key
     */
    public static String rowKey(String profile, String section, String key) {
        return profile + '|' + section + '|' + String.valueOf(key).toLowerCase();
    }

    private static String flag(Object value) {
        return value instanceof Boolean && (Boolean) value ? TRUE_TEXT : FALSE_TEXT;
    }
}
