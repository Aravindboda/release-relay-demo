/**
 * @description The pipeline's validate.json when the release conflicts with the target branch
 * ({"status":"Conflict","conflicts":[{"file","merged","mine","theirs","truncated"}]}): recognising it, reading its
 * files, and fitting it into Validation_Result__c (shortening the file texts, and marking them truncated, when
 * the whole result is too long).
 */
public with sharing class RlyConflictResult {

    /** @description The status validate.json has when the release conflicts with the target. */
    public static final String CONFLICT = 'Conflict';
    /** @description Longest result Validation_Result__c holds. */
    public static final Integer MAX_LENGTH = 131072;

    private static final List<String> TEXTS = new List<String>{ 'merged', 'mine', 'theirs' };
    private static final Integer SHORTEST = 500;

    /**
     * @description Whether a validate.json result is a conflict.
     * @param result the parsed result
     * @return true when its status is Conflict
     */
    public static Boolean isConflict(Map<String, Object> result) {
        return result != null && String.valueOf(result.get('status')) == CONFLICT;
    }

    /**
     * @description The conflicting files of a saved validation result.
     * @param resultJson Validation_Result__c
     * @return the files by path (empty when the result isn't a conflict)
     */
    public static Map<String, Map<String, Object>> filesOf(String resultJson) {
        Map<String, Map<String, Object>> out = new Map<String, Map<String, Object>>();
        Map<String, Object> result = parse(resultJson);
        if (!isConflict(result)) {
            return out;
        }
        for (Map<String, Object> c : conflicts(result)) {
            if (c.get('file') != null) {
                out.put(String.valueOf(c.get('file')), c);
            }
        }
        return out;
    }

    /**
     * @description The result as JSON that fits Validation_Result__c: the conflict file texts are shortened (and
     * marked truncated) until it fits.
     * @param result the parsed result (changed when shortened)
     * @return the JSON
     */
    public static String fit(Map<String, Object> result) {
        String json = JSON.serialize(result);
        Integer cap = 15000;
        while (json.length() > MAX_LENGTH && cap > SHORTEST) {
            cap = cap / 2;
            shorten(conflicts(result), cap);
            json = JSON.serialize(result);
        }
        return json.left(MAX_LENGTH);
    }

    private static void shorten(List<Map<String, Object>> files, Integer cap) {
        for (Map<String, Object> c : files) {
            for (String key : TEXTS) {
                shortenText(c, key, cap);
            }
        }
    }

    private static void shortenText(Map<String, Object> c, String key, Integer cap) {
        Object text = c.get(key);
        if (text != null && String.valueOf(text).length() > cap) {
            c.put(key, String.valueOf(text).left(cap));
            c.put('truncated', true);
        }
    }

    private static List<Map<String, Object>> conflicts(Map<String, Object> result) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        Object files = result == null ? null : result.get('conflicts');
        if (files instanceof List<Object>) {
            for (Object o : (List<Object>) files) {
                addFile(o, out);
            }
        }
        return out;
    }

    private static void addFile(Object o, List<Map<String, Object>> out) {
        if (o instanceof Map<String, Object>) {
            out.add((Map<String, Object>) o);
        }
    }

    private static Map<String, Object> parse(String resultJson) {
        if (String.isBlank(resultJson)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(resultJson);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (Exception e) {
            return null;
        }
    }
}
