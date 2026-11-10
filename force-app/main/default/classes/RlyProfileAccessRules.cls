/**
 * @description Profile access sent with a new release (New Release, step Profile access): which rows of which
 * profiles to change, kept as JSON in RLY_Release__c.Profile_Access__c and committed to the release branch as
 * .relay-inbox/<REL>-access.json. The pipeline writes each row into the profile's file and deploys only the rows a
 * release changes, so the rest of each profile stays as it is in the target org.
 *
 * A row is one entry of a profile file: a section (its XML element, for example fieldPermissions), the component it
 * is about (its key: Account.Region__c) and the values to send (readable, editable…: "true" or "false"; a tab's
 * visibility; a layout's name). A row with no value isn't sent.
 */
public with sharing class RlyProfileAccessRules {

    /** @description The most profiles a release can change. */
    public static final Integer MAX_PROFILES = 20;
    /** @description The most rows a release can carry, over every profile. */
    public static final Integer MAX_ROWS = 1000;
    /** @description Most characters Profile_Access__c holds. */
    public static final Integer MAX_LENGTH = 131072;
    /** @description Section: field permissions (key Object.Field__c). */
    public static final String FIELDS = 'fieldPermissions';
    /** @description Section: object permissions (key the object). */
    public static final String OBJECTS = 'objectPermissions';
    /** @description Section: Apex class access. */
    public static final String CLASSES = 'classAccesses';
    /** @description Section: Visualforce page access. */
    public static final String PAGES = 'pageAccesses';
    /** @description Section: tab settings. */
    public static final String TABS = 'tabVisibilities';
    /** @description Section: record type visibility (key Object.RecordType). */
    public static final String RECORD_TYPES = 'recordTypeVisibilities';
    /** @description Section: page layout assignment (key Object.RecordType, or the object for its master layout). */
    public static final String LAYOUTS = 'layoutAssignments';
    /** @description Section: app visibility. */
    public static final String APPS = 'applicationVisibilities';
    /** @description Section: custom permissions. */
    public static final String CUSTOM_PERMISSIONS = 'customPermissions';
    /** @description Section: custom metadata type access. */
    public static final String METADATA_TYPES = 'customMetadataTypeAccesses';
    /** @description Section: custom setting access. */
    public static final String SETTINGS = 'customSettingAccesses';
    /** @description Section: system permissions (key the permission's API name, for example ApiEnabled). */
    public static final String SYSTEM_PERMISSIONS = 'userPermissions';
    /** @description The tab settings a tab row can send. */
    public static final Set<String> TAB_VISIBILITIES = new Set<String>{ 'DefaultOn', 'DefaultOff', 'Hidden' };

    private static final String ENABLED = 'enabled';
    private static final Pattern PROFILE = Pattern.compile('^[^<>&"/\\\\:*?|]{1,80}$');

    /** @description The values each section can send (all "true" or "false", except a tab's visibility and a layout). */
    public static final Map<String, List<String>> VALUES_OF = new Map<String, List<String>>{
        FIELDS => new List<String>{ 'readable', 'editable' },
        OBJECTS => new List<String>{ 'allowCreate', 'allowRead', 'allowEdit', 'allowDelete', 'viewAllRecords', 'modifyAllRecords' },
        CLASSES => new List<String>{ ENABLED }, PAGES => new List<String>{ ENABLED },
        TABS => new List<String>{ 'visibility' },
        RECORD_TYPES => new List<String>{ 'visible', 'default' },
        LAYOUTS => new List<String>{ 'layout' },
        APPS => new List<String>{ 'visible', 'default' },
        CUSTOM_PERMISSIONS => new List<String>{ ENABLED }, METADATA_TYPES => new List<String>{ ENABLED },
        SETTINGS => new List<String>{ ENABLED }, SYSTEM_PERMISSIONS => new List<String>{ ENABLED } };

    /** @description One row of a profile: a section, the component it's about and the values to send. */
    public class Row {
        /** @description The section (its XML element), for example fieldPermissions. */
        @AuraEnabled public String section;
        /** @description The component: Account.Region__c, Order__c, ApiEnabled… */
        @AuraEnabled public String key;
        /** @description The values to send, by name: "true"/"false", a tab's visibility or a layout's name. */
        @AuraEnabled public Map<String, String> values;
    }

    /** @description One profile's rows. */
    public class ProfileRows {
        /** @description The profile's metadata name (its file name: Admin for System Administrator). */
        @AuraEnabled public String profile;
        /** @description The profile's name as Setup shows it. */
        @AuraEnabled public String label;
        /** @description Its rows. */
        @AuraEnabled public List<Row> rows;
    }

    /**
     * @description Checks the profile access sent with a new release: known sections, valid names and values, each
     * profile and row once, within the limits. Rows without a value and profiles without rows are left out.
     * @param sent the profiles and their rows, or null
     * @return the checked profiles, in the order sent
     */
    public static List<ProfileRows> checked(List<ProfileRows> sent) {
        List<ProfileRows> out = new List<ProfileRows>();
        Set<String> seen = new Set<String>();
        for (ProfileRows p : sent == null ? new List<ProfileRows>() : sent) {
            ProfileRows kept = checkedProfile(p, seen);
            if (!kept.rows.isEmpty()) {
                out.add(kept);
            }
        }
        if (out.size() > MAX_PROFILES) {
            throw new RlyReleaseException('A release can change up to ' + MAX_PROFILES + ' profiles.');
        }
        Integer total = rowCount(out);
        if (total > MAX_ROWS) {
            throw new RlyReleaseException('A release can carry up to ' + MAX_ROWS + ' profile access rows (this one has ' + total + ').');
        }
        return out;
    }

    private static ProfileRows checkedProfile(ProfileRows p, Set<String> seen) {
        String name = p == null || p.profile == null ? '' : p.profile.trim();
        if (!PROFILE.matcher(name).matches() || name.contains('..')) {
            throw new RlyReleaseException('"' + name.left(80) + '" isn\'t a profile name Release Relay can send.');
        }
        if (!seen.add(name.toLowerCase())) {
            throw new RlyReleaseException('Profile ' + name + ' is listed twice.');
        }
        ProfileRows kept = new ProfileRows();
        kept.profile = name;
        kept.label = String.isBlank(p.label) ? name : p.label.trim().left(80);
        kept.rows = RlyProfileAccessRowCheck.checkedRows(name, p.rows);
        return kept;
    }

    /**
     * @description A section's name in the page's words.
     * @param section the section, for example fieldPermissions
     * @return for example "field access"
     */
    public static String sectionLabel(String section) {
        Map<String, String> labels = new Map<String, String>{ FIELDS => 'field access', OBJECTS => 'object access',
            CLASSES => 'Apex class access', PAGES => 'Visualforce page access', TABS => 'tab settings',
            RECORD_TYPES => 'record types', LAYOUTS => 'page layouts', APPS => 'apps', CUSTOM_PERMISSIONS => 'custom permissions',
            METADATA_TYPES => 'custom metadata types', SETTINGS => 'custom settings', SYSTEM_PERMISSIONS => 'system permissions' };
        return labels.containsKey(section) ? labels.get(section) : section;
    }

    /**
     * @description How many rows the profiles carry.
     * @param profiles the checked profiles
     * @return the number of rows
     */
    public static Integer rowCount(List<ProfileRows> profiles) {
        Integer n = 0;
        for (ProfileRows p : profiles == null ? new List<ProfileRows>() : profiles) {
            n += p.rows.size();
        }
        return n;
    }

    /**
     * @description The value of Profile_Access__c.
     * @param profiles the checked profiles
     * @return the JSON, or null when there are none
     */
    public static String toField(List<ProfileRows> profiles) {
        if (profiles == null || profiles.isEmpty()) {
            return null;
        }
        String json = JSON.serialize(profiles, true);
        if (json.length() > MAX_LENGTH) {
            throw new RlyReleaseException('The profile access is too large to send in one release: split it over two releases.');
        }
        return json;
    }

    /**
     * @description The profiles kept in Profile_Access__c.
     * @param value the field's value
     * @return the profiles (empty when blank)
     */
    public static List<ProfileRows> fromField(String value) {
        return String.isBlank(value) ? new List<ProfileRows>() : (List<ProfileRows>) JSON.deserialize(value, List<ProfileRows>.class);
    }

    /**
     * @description The words for a release's profile access, for its log: "3 profile access rows".
     * @param count the number of rows
     * @return the words
     */
    public static String rowWords(Integer count) {
        return count + (count == 1 ? ' profile access row' : ' profile access rows');
    }
}
