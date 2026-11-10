/**
 * @description Which objects of the org's object list each Add access kind offers (RlyProfileAccessNames): objects,
 * fields and master layouts the ones with page layouts (custom metadata types, custom settings and platform events
 * left out), custom metadata types the __mdt ones, custom settings the ones the list marks customSetting.
 */
public with sharing class RlyProfileAccessNameRules {

    /** @description A tab name a profile file can hold. */
    public static final Pattern TAB = Pattern.compile('^[A-Za-z][A-Za-z0-9_-]{0,79}$');

    /**
     * @description Whether an object of the org's object list fits a kind.
     * @param kind fields, layouts, or a profile section (objectPermissions, customMetadataTypeAccesses, customSettingAccesses)
     * @param name the object's API name
     * @param s its entry in the object list
     * @return true when it's offered
     */
    public static Boolean objectFits(String kind, String name, Map<String, Object> s) {
        Boolean setting = Boolean.valueOf(s.get('customSetting')) == true;
        if (kind == RlyProfileAccessRules.METADATA_TYPES) {
            return name.endsWith('__mdt');
        }
        if (kind == RlyProfileAccessRules.SETTINGS) {
            return setting;
        }
        return Boolean.valueOf(s.get('layoutable')) == true && !setting && !name.endsWith('__mdt') && !name.endsWith('__e');
    }
}
