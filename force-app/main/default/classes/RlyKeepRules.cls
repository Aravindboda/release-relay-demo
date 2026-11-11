/**
 * @description Build 60 (D40): lines a release keeps or takes out. On Review the page lists the items the target branch's
 * copy of a component has and the developer org's copy lacks (a layout field, a permission, a picklist value, a label);
 * the release keeps them unless the developer ticks Remove on purpose. Those choices are kept in
 * RLY_Release__c.Remove_On_Purpose__c as JSON [{component, item}] and committed as .relay-inbox/REL-x-keep.json; the
 * pipeline (version 34) puts every other missing item back. An item is element:key, for example layoutItems:Fax or
 * fieldPermissions:Account.Industry.
 */
public with sharing class RlyKeepRules {

    /** @description Most lines one release takes out on purpose. */
    public static final Integer MAX_ITEMS = 1000;
    /** @description Longest component or item. */
    public static final Integer MAX_LENGTH = 300;
    /** @description Most characters Remove_On_Purpose__c holds. */
    public static final Integer MAX_CHARS = 32768;
    /** @description The types whose lines are kept (profiles go through Profile access). */
    public static final Set<String> TYPES = new Set<String>{
        'Layout', 'PermissionSet', 'CustomField', 'CustomLabels', 'GlobalValueSet', 'StandardValueSet' };
    /** @description The elements an item can name. */
    public static final Set<String> ELEMENTS = new Set<String>{
        'layoutItems', 'relatedLists', 'quickActionListItems', 'platformActionListItems', 'fieldPermissions',
        'objectPermissions', 'classAccesses', 'pageAccesses', 'tabSettings', 'recordTypeVisibilities',
        'applicationVisibilities', 'customPermissions', 'userPermissions', 'customMetadataTypeAccesses',
        'customSettingAccesses', 'flowAccesses', 'externalDataSourceAccesses', 'layoutAssignments', 'value', 'labels',
        'customValue', 'standardValue' };

    /** @description One line taken out on purpose. */
    public class KeepItem {
        /** @description The component, Type:Name. */
        public String component;
        /** @description The line, element:key. */
        public String item;
    }

    /**
     * @description Checks the lines sent with a raise: each names a component the release brings, of a type whose lines
     * are kept, and a known element.
     * @param items the lines, or null
     * @param brought the components the release brings, Type:Name
     * @return the lines, trimmed (empty when none)
     */
    public static List<KeepItem> checked(List<KeepItem> items, Set<String> brought) {
        List<KeepItem> out = new List<KeepItem>();
        if (items == null || items.isEmpty()) {
            return out;
        }
        if (items.size() > MAX_ITEMS) {
            throw new RlyReleaseException('Take out up to ' + MAX_ITEMS + ' lines on purpose in one release.');
        }
        Set<String> lower = new Set<String>();
        for (String k : brought) {
            lower.add(k.toLowerCase());
        }
        for (KeepItem i : items) {
            out.add(checkedItem(i, lower));
        }
        return out;
    }

    private static KeepItem checkedItem(KeepItem i, Set<String> brought) {
        KeepItem sent = i == null ? new KeepItem() : i;
        String component = String.isBlank(sent.component) ? '' : sent.component.trim();
        String item = String.isBlank(sent.item) ? '' : sent.item.trim();
        if (!isLine(item)) {
            throw new RlyReleaseException('"' + item.left(80) + '" isn\'t a line Release Relay can take out.');
        }
        if (!isBrought(component, brought)) {
            throw new RlyReleaseException(component.left(80) + ' isn\'t in this release, so nothing can be taken out of it.');
        }
        KeepItem k = new KeepItem();
        k.component = component;
        k.item = item;
        return k;
    }

    // A component of a kept type that the release brings.
    private static Boolean isBrought(String component, Set<String> brought) {
        return component.length() <= MAX_LENGTH && TYPES.contains(component.substringBefore(':')) && brought.contains(component.toLowerCase());
    }

    // element:key with a known element and a key.
    private static Boolean isLine(String item) {
        return item.length() <= MAX_LENGTH && ELEMENTS.contains(item.substringBefore(':')) && String.isNotBlank(item.substringAfter(':'));
    }

    /**
     * @description The value of Remove_On_Purpose__c.
     * @param items the checked lines
     * @return the JSON, or null when none
     */
    public static String toField(List<KeepItem> items) {
        if (items == null || items.isEmpty()) {
            return null;
        }
        String json = JSON.serialize(items, true);
        if (json.length() > MAX_CHARS) {
            throw new RlyReleaseException('Too many lines taken out on purpose to keep with the release: raise fewer components.');
        }
        return json;
    }

    /**
     * @description The lines kept in Remove_On_Purpose__c.
     * @param value the field's value
     * @return the lines (empty when none or unreadable)
     */
    public static List<KeepItem> fromField(String value) {
        if (String.isBlank(value)) {
            return new List<KeepItem>();
        }
        try {
            List<KeepItem> items = (List<KeepItem>) JSON.deserialize(value, List<KeepItem>.class);
            return items == null ? new List<KeepItem>() : items;
        } catch (JSONException e) {
            return new List<KeepItem>();
        }
    }
}
