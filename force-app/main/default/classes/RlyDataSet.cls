/**
 * @description A data set's definition (RLY_Data_Set__c.Definition__c, edited on the Sync status tab, Data): the objects
 * in load order, each with its fields, a record filter, its match key (an external ID field or a combination of fields:
 * an object without one can't be included), its parent lookups (a lookup to an earlier object, matched by that object's
 * key so the parent's key stands in for the lookup), its masked fields (applied when copying down) and the target org's
 * trigger bypass (a hierarchy custom setting field or a permission set switched on for the pipeline's user during the
 * load). parse() reads and checks the JSON; problems are refused with one clear message.
 */
public with sharing class RlyDataSet {

    /** @description Most objects in one data set. */
    public static final Integer MAX_OBJECTS = 20;
    /** @description Most fields per object. */
    public static final Integer MAX_FIELDS = 200;
    /** @description The mask rules. */
    public static final Set<String> MASK_RULES = new Set<String>{ 'email', 'phone', 'name', 'blank' };
    /** @description The bypass kinds. */
    public static final Set<String> BYPASS_KINDS = new Set<String>{ 'setting', 'permissionSet' };

    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Integer MAX_FILTER = 2000;

    /** @description The definition. */
    public class Definition {
        /** @description The objects, parents before children. */
        @AuraEnabled public List<Item> objects = new List<Item>();
        /** @description The target org's trigger bypass, or null. */
        @AuraEnabled public Bypass bypass;
    }

    /** @description One object of the set. */
    public class Item {
        /** @description The object's API name. */
        @AuraEnabled public String objectName;
        /** @description The fields moved (the match key's fields among them). */
        @AuraEnabled public List<String> fields = new List<String>();
        /** @description The record filter (a SOQL WHERE condition), or blank for all records. */
        @AuraEnabled public String filter;
        /** @description The match key: one external ID field or a combination of fields. */
        @AuraEnabled public List<String> matchKey = new List<String>();
        /** @description Parent lookups: field => an earlier object of the set. */
        @AuraEnabled public Map<String, String> parents = new Map<String, String>();
        /** @description Masked fields: field => email, phone, name, blank or fixed:<text>. */
        @AuraEnabled public Map<String, String> masks = new Map<String, String>();
    }

    /** @description The trigger bypass in the target org. */
    public class Bypass {
        /** @description setting (a hierarchy custom setting's checkbox field) or permissionSet. */
        @AuraEnabled public String kind;
        /** @description The custom setting or permission set API name. */
        @AuraEnabled public String name;
        /** @description The custom setting's checkbox field (setting only). */
        @AuraEnabled public String field;
    }

    /**
     * @description Reads and checks a definition.
     * @param definitionJson the definition JSON
     * @return the definition
     */
    public static Definition parse(String definitionJson) {
        Definition d;
        try {
            d = String.isBlank(definitionJson) ? null : (Definition) JSON.deserialize(definitionJson, Definition.class);
        } catch (JSONException e) {
            throw new RlyReleaseException('The data set\'s definition isn\'t valid JSON.');
        }
        String problem = problemOf(d);
        if (problem != null) {
            throw new RlyReleaseException(problem);
        }
        return d;
    }

    /**
     * @description Why a definition can't be used, or null.
     * @param d the definition
     * @return the problem, or null
     */
    public static String problemOf(Definition d) {
        if (d == null || d.objects == null || d.objects.isEmpty()) {
            return 'Add at least one object to the data set.';
        }
        if (d.objects.size() > MAX_OBJECTS) {
            return 'A data set takes at most ' + MAX_OBJECTS + ' objects.';
        }
        Set<String> earlier = new Set<String>();
        for (Item i : d.objects) {
            String problem = RlyDataSetCheck.itemProblem(i, earlier);
            if (problem != null) {
                return problem;
            }
            earlier.add(i.objectName.toLowerCase());
        }
        return bypassProblem(d.bypass);
    }

    /**
     * @description Whether a name is a plain API name (an object or a field, no relationship path).
     * @param name the name
     * @return true when it is
     */
    public static Boolean isApiName(String name) {
        return String.isNotBlank(name) && API_NAME_PATTERN.matcher(name).matches();
    }

    /**
     * @description Whether a record filter is safe to put after WHERE: short, one statement.
     * @param filter the filter
     * @return true when it is
     */
    public static Boolean isSafeFilter(String filter) {
        return String.isBlank(filter) || (filter.length() <= MAX_FILTER && !filter.contains(';') && !filter.containsIgnoreCase(' limit ')
            && !filter.containsIgnoreCase(' order by '));
    }

    /**
     * @description The export query of one object.
     * @param i the object
     * @return SELECT … FROM … [WHERE …]
     */
    public static String queryOf(Item i) {
        Map<String, String> fields = new Map<String, String>{ 'id' => 'Id' };
        for (String f : i.fields) {
            fields.put(f.toLowerCase(), f);
        }
        return 'SELECT ' + String.join(fields.values(), ', ') + ' FROM ' + i.objectName
            + (String.isBlank(i.filter) ? '' : ' WHERE ' + i.filter.normalizeSpace());
    }

    /**
     * @description Why the trigger bypass can't be used, or null (no bypass is fine).
     * @param b the bypass
     * @return the problem, or null
     */
    public static String bypassProblem(Bypass b) {
        if (b == null || String.isBlank(b.kind)) {
            return null;
        }
        if (!BYPASS_KINDS.contains(b.kind) || !isApiName(b.name)) {
            return 'The trigger bypass needs a kind (custom setting or permission set) and its API name.';
        }
        if (b.kind == 'setting' && !isApiName(b.field)) {
            return 'A custom setting bypass needs its checkbox field.';
        }
        return null;
    }
}
