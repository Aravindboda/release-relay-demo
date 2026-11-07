/**
 * @description Sync status: reads the values of a check's result (drift.json, route.json) for RlySyncResult.
 */
public with sharing class RlySyncParse {

    /**
     * @description An org check's components and counts into the view.
     * @param v the view
     * @param result drift.json
     */
    public static void readComponents(RlySyncResult.View v, Map<String, Object> result) {
        for (Object o : asList(result.get('components'))) {
            v.components.add(component(asMap(o)));
        }
        Map<String, Object> counts = asMap(result.get('counts'));
        for (String k : new List<String>{ 'onlyInOrg', 'onlyOnBranch', 'different' }) {
            v.counts.put(k, toInt(counts.get(k)));
        }
    }

    /**
     * @description A route check's pairs (and their counts) into the view.
     * @param v the view
     * @param result route.json
     */
    public static void readPairs(RlySyncResult.View v, Map<String, Object> result) {
        for (Object o : asList(result.get('pairs'))) {
            Map<String, Object> m = asMap(o);
            RlySyncResult.SyncPair p = new RlySyncResult.SyncPair();
            p.higher = text(m.get('higher'));
            p.lower = text(m.get('lower'));
            for (Object c : asList(m.get('components'))) {
                p.components.add(component(asMap(c)));
            }
            p.count = m.get('count') == null ? p.components.size() : toInt(m.get('count'));
            v.pairs.add(p);
            v.counts.put(p.higher + '>' + p.lower, p.count);
        }
    }

    /**
     * @description One component from a result.
     * @param m its values
     * @return the component
     */
    public static RlySyncResult.SyncComponent component(Map<String, Object> m) {
        RlySyncResult.SyncComponent c = new RlySyncResult.SyncComponent();
        c.key = text(m.get('key'));
        c.type = m.get('type') != null ? text(m.get('type')) : (c.key == null ? null : c.key.substringBefore(':'));
        c.name = c.key == null ? null : c.key.substringAfter(':');
        c.status = text(m.get('status'));
        c.lastChangedBy = text(m.get('lastChangedBy'));
        c.lastChangedAt = text(m.get('lastChangedAt'));
        c.lowerChangedToo = m.get('lowerChangedToo') == true;
        c.cameFrom = text(m.get('cameFrom'));
        for (Object o : asList(m.get('files'))) {
            Map<String, Object> f = asMap(o);
            RlySyncResult.SyncFile x = new RlySyncResult.SyncFile();
            x.path = text(f.get('path'));
            x.status = text(f.get('status'));
            x.n = f.get('n') == null ? null : toInt(f.get('n'));
            x.kind = text(f.get('kind'));
            x.reason = text(f.get('reason'));
            c.files.add(x);
        }
        return c;
    }

    /**
     * @description Reads a JSON object, or null.
     * @param raw the text
     * @return the values, or null
     */
    public static Map<String, Object> parsed(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            Object o = JSON.deserializeUntyped(raw);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
        } catch (JSONException e) {
            return null;
        }
    }

    /**
     * @description Reads a whole number (0 when not one).
     * @param o the value
     * @return the number
     */
    public static Integer toInt(Object o) {
        if (o == null) {
            return 0;
        }
        String s = String.valueOf(o);
        return s.isNumeric() ? Integer.valueOf(s) : 0;
    }

    /**
     * @description Reads a list (empty when not one).
     * @param o the value
     * @return the list
     */
    public static List<Object> asList(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    /**
     * @description Reads a map (empty when not one).
     * @param o the value
     * @return the map
     */
    public static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
    }

    /**
     * @description Reads text, or null.
     * @param o the value
     * @return the text
     */
    public static String text(Object o) {
        return o == null ? null : String.valueOf(o);
    }
}
