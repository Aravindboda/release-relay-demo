/**
 * @description Release window freezes (build 39): whole days in the window's time zone, both ends included, kept on the
 * org as JSON [{from: yyyy-MM-dd, to: yyyy-MM-dd, reason}]. Reads them (rows that aren't dates in order are left out),
 * writes them back, and finds the one covering a day or the next one. No DML, no callouts.
 */
public with sharing class RlyWindowFreezes {

    private static final Integer MAX_FREEZES = 50;
    /** @description The longest reason kept. */
    public static final Integer MAX_REASON = 120;

    /** @description One freeze. */
    public class Freeze {
        /** @description The first day (in the window's time zone). */
        @AuraEnabled public Date fromDate;
        /** @description The last day, included. */
        @AuraEnabled public Date toDate;
        /** @description Why. */
        @AuraEnabled public String reason;
    }

    /**
     * @description Reads freezes, leaving out rows that aren't dates in order; earliest first, at most MAX_FREEZES.
     * @param value [{from, to, reason}]
     * @return the freezes
     */
    public static List<Freeze> parse(String value) {
        List<Freeze> out = new List<Freeze>();
        for (Object o : rowsOf(value)) {
            Freeze f = freezeOf(o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>());
            if (f != null && out.size() < MAX_FREEZES) {
                out.add(f);
            }
        }
        sortByStart(out);
        return out;
    }

    /**
     * @description The freezes as the org field keeps them.
     * @param freezeRows the freezes
     * @return JSON, or null when there are none
     */
    public static String toJson(List<Freeze> freezeRows) {
        if (freezeRows == null || freezeRows.isEmpty()) {
            return null;
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Freeze f : freezeRows) {
            rows.add(new Map<String, Object>{ 'from' => String.valueOf(f.fromDate), 'to' => String.valueOf(f.toDate),
                'reason' => f.reason });
        }
        return JSON.serialize(rows);
    }

    /**
     * @description The freeze covering a day.
     * @param freezes the freezes
     * @param day the local day
     * @return the freeze, or null
     */
    public static Freeze covering(List<Freeze> freezes, Date day) {
        for (Freeze f : freezes) {
            if (day >= f.fromDate && day <= f.toDate) {
                return f;
            }
        }
        return null;
    }

    /**
     * @description The first freeze not over on a day (running, or the next to start).
     * @param freezes the freezes, earliest first
     * @param day the local day
     * @return the freeze, or null
     */
    public static Freeze notOver(List<Freeze> freezes, Date day) {
        for (Freeze f : freezes) {
            if (f.toDate >= day) {
                return f;
            }
        }
        return null;
    }

    private static List<Object> rowsOf(String value) {
        try {
            Object parsed = String.isBlank(value) ? null : JSON.deserializeUntyped(value);
            return parsed instanceof List<Object> ? (List<Object>) parsed : new List<Object>();
        } catch (JSONException e) {
            return new List<Object>();
        }
    }

    private static Freeze freezeOf(Map<String, Object> m) {
        Date fromDate = dateOf(m.get('from'));
        Date toDate = dateOf(m.get('to'));
        if (fromDate == null || toDate == null || toDate < fromDate) {
            return null;
        }
        Freeze f = new Freeze();
        f.fromDate = fromDate;
        f.toDate = toDate;
        f.reason = m.get('reason') == null ? null : String.valueOf(m.get('reason')).normalizeSpace().left(MAX_REASON);
        return f;
    }

    private static Date dateOf(Object value) {
        String v = value == null ? '' : String.valueOf(value).trim().left(10);
        if (!Pattern.matches('\\d{4}-\\d{2}-\\d{2}', v)) {
            return null;
        }
        try {
            return Date.valueOf(v);
        } catch (Exception e) {
            return null;
        }
    }

    // Earliest start first (a short list: insertion sort).
    private static void sortByStart(List<Freeze> rows) {
        for (Integer i = 1; i < rows.size(); i++) {
            Freeze cur = rows[i];
            Integer j = i - 1;
            while (j >= 0 && rows[j].fromDate > cur.fromDate) {
                rows[j + 1] = rows[j];
                j--;
            }
            rows[j + 1] = cur;
        }
    }
}
