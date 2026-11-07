/**
 * @description Checks one object of a data set (RlyDataSet.problemOf; the trigger bypass is checked there): plain API names,
 * a match key made of the object's own fields (no match key, no object), parents that are earlier objects, masks on the
 * object's fields with a known rule, a safe record filter.
 */
public with sharing class RlyDataSetCheck {

    /**
     * @description Why an object can't be used, or null.
     * @param i the object
     * @param earlier the objects before it (lower case)
     * @return the problem, or null
     */
    public static String itemProblem(RlyDataSet.Item i, Set<String> earlier) {
        if (i == null || !RlyDataSet.isApiName(i.objectName)) {
            return 'Each object needs its API name (for example Claim_Type__c).';
        }
        String name = i.objectName;
        if (earlier.contains(name.toLowerCase())) {
            return name + ' is in the data set twice.';
        }
        String fieldProblem = fieldsProblem(i);
        if (fieldProblem != null) {
            return fieldProblem;
        }
        if (!RlyDataSet.isSafeFilter(i.filter)) {
            return name + '\'s record filter must be one condition (no ";", LIMIT or ORDER BY), up to 2,000 characters.';
        }
        String parentProblem = parentsProblem(i, earlier);
        return parentProblem != null ? parentProblem : masksProblem(i);
    }

    // Fields: plain names, at most MAX_FIELDS; the match key: one or more of those fields.
    private static String fieldsProblem(RlyDataSet.Item i) {
        if (i.fields == null || i.fields.isEmpty() || i.fields.size() > RlyDataSet.MAX_FIELDS) {
            return i.objectName + ' needs 1 to ' + RlyDataSet.MAX_FIELDS + ' fields.';
        }
        Set<String> own = lowered(i.fields);
        for (String f : i.fields) {
            if (!RlyDataSet.isApiName(f)) {
                return i.objectName + ': "' + f + '" isn\'t a field API name.';
            }
        }
        return keyProblem(i, own);
    }

    // The match key: one or more of the object's own fields (no match key, no object).
    private static String keyProblem(RlyDataSet.Item i, Set<String> own) {
        if (i.matchKey == null || i.matchKey.isEmpty()) {
            return i.objectName + ' has no match key: pick an external ID field or a combination of fields, or leave the object out.';
        }
        for (String k : i.matchKey) {
            if (k == null || !own.contains(k.toLowerCase())) {
                return i.objectName + '\'s match key field ' + k + ' must be one of its fields.';
            }
        }
        return null;
    }

    // Parents: a lookup field of the object pointing at an earlier object.
    private static String parentsProblem(RlyDataSet.Item i, Set<String> earlier) {
        Set<String> own = lowered(i.fields);
        for (String f : (i.parents == null ? new Map<String, String>() : i.parents).keySet()) {
            String parent = i.parents.get(f);
            if (f == null || !own.contains(f.toLowerCase())) {
                return i.objectName + '\'s parent lookup ' + f + ' must be one of its fields.';
            }
            if (parent == null || !earlier.contains(parent.toLowerCase())) {
                return i.objectName + '.' + f + ' must point at an object earlier in the data set (parents load first).';
            }
        }
        return null;
    }

    // Masks: a field of the object, a known rule or fixed:<text>.
    private static String masksProblem(RlyDataSet.Item i) {
        Set<String> own = lowered(i.fields);
        Set<String> keys = new Set<String>();
        for (String k : i.matchKey) {
            keys.add(k.toLowerCase());
        }
        for (String f : (i.masks == null ? new Map<String, String>() : i.masks).keySet()) {
            String rule = i.masks.get(f);
            Boolean known = rule != null && (RlyDataSet.MASK_RULES.contains(rule) || (rule.startsWith('fixed:') && rule.length() <= 206));
            if (f == null || !own.contains(f.toLowerCase()) || !known) {
                return i.objectName + ': mask ' + f + ' needs one of its fields and a rule (email, phone, name, blank or fixed:<text>).';
            }
            if (keys.contains(f.toLowerCase())) {
                return i.objectName + ': ' + f + ' is in the match key, so it can\'t be masked (records wouldn\'t match).';
            }
        }
        return null;
    }

    private static Set<String> lowered(List<String> values) {
        Set<String> out = new Set<String>();
        for (String s : values == null ? new List<String>() : values) {
            if (s != null) {
                out.add(s.toLowerCase());
            }
        }
        return out;
    }
}
