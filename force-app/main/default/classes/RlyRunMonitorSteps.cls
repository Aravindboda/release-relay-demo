/**
 * @description Reads the jobs list a pipeline run sends ([{name, outcome, seconds}], or the same as JSON text) and keeps
 * it as compact JSON for RLY_Pipeline_Run__c.Steps__c.
 */
public with sharing class RlyRunMonitorSteps {
    private static final Integer MAX_STEPS = 50;

    /**
     * @description The jobs list ([{name, outcome, seconds}], or the same as a JSON text) as compact JSON with at most
     * 50 entries and only those three keys, or null when there are none.
     * @param o the value
     * @return the JSON, or null
     */
    public static String steps(Object o) {
        Object parsed = o instanceof String ? parseList((String) o) : o;
        if (!(parsed instanceof List<Object>)) {
            return null;
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Object item : (List<Object>) parsed) {
            Map<String, Object> row = stepRow(item);
            if (row != null && out.size() < MAX_STEPS) {
                out.add(row);
            }
        }
        return out.isEmpty() ? null : JSON.serialize(out).left(32768);
    }

    private static Map<String, Object> stepRow(Object item) {
        if (!(item instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> m = (Map<String, Object>) item;
        String name = RlyRunMonitorInput.text(m.get('name'), 120);
        if (name == null) {
            return null;
        }
        Long seconds = RlyRunMonitorInput.whole(m.get('seconds'));
        return new Map<String, Object>{ 'name' => name, 'outcome' => RlyRunMonitorInput.text(m.get('outcome'), 20), 'seconds' => seconds };
    }

    private static Object parseList(String s) {
        try {
            return JSON.deserializeUntyped(s);
        } catch (JSONException e) {
            return null;
        }
    }
}
