/**
 * @description Reads the values the pipeline posts to the run endpoint (RlyRunMonitorInbound): the JSON body as a map,
 * text trimmed and cut to the field's length, the run status in the words GitHub and the pipeline use, ISO date-times,
 * whole numbers, https addresses, a release number and the jobs list (kept as compact JSON). A value of the wrong
 * shape reads as null; unknown keys are never read.
 */
public with sharing class RlyRunMonitorInput {

    /** @description Queued. */
    public static final String QUEUED = 'Queued';
    /** @description In progress. */
    public static final String IN_PROGRESS = 'In progress';
    /** @description Succeeded. */
    public static final String SUCCEEDED = 'Succeeded';
    /** @description Failed. */
    public static final String FAILED = 'Failed';
    /** @description Cancelled. */
    public static final String CANCELLED = 'Cancelled';

    private static final Integer MAX_STEPS = 50;
    private static final Pattern RELEASE_NUMBER = Pattern.compile('^REL-\\d{5,10}$');
    private static final Map<String, String> STATUS_WORDS = new Map<String, String>{
        'queued' => QUEUED, 'waiting' => QUEUED, 'pending' => QUEUED, 'requested' => QUEUED,
        'in progress' => IN_PROGRESS, 'in_progress' => IN_PROGRESS, 'in-progress' => IN_PROGRESS, 'running' => IN_PROGRESS,
        'started' => IN_PROGRESS,
        'succeeded' => SUCCEEDED, 'success' => SUCCEEDED, 'passed' => SUCCEEDED, 'completed' => SUCCEEDED,
        'failed' => FAILED, 'failure' => FAILED, 'timed_out' => FAILED, 'error' => FAILED,
        'cancelled' => CANCELLED, 'canceled' => CANCELLED
    };

    /**
     * @description The body as a map; a blank body, bad JSON or anything but an object is an empty map.
     * @param body the request body
     * @return the values by key
     */
    public static Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object o = JSON.deserializeUntyped(body);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        } catch (JSONException e) {
            return new Map<String, Object>();
        }
    }

    /**
     * @description Trimmed text cut to a length, or null for blank or a value that isn't text or a number.
     * @param o the value
     * @param maxLength the field's length
     * @return the text, or null
     */
    public static String text(Object o, Integer maxLength) {
        String s;
        if (o instanceof String) {
            s = (String) o;
        } else if (o instanceof Integer || o instanceof Long || o instanceof Decimal) {
            s = String.valueOf(o);
        }
        s = s == null ? null : s.normalizeSpace();
        return String.isBlank(s) ? null : s.left(maxLength);
    }

    /**
     * @description The run status from GitHub's or the pipeline's word, or null when it isn't one.
     * @param o the value
     * @return Queued, In progress, Succeeded, Failed, Cancelled or null
     */
    public static String status(Object o) {
        String s = text(o, 40);
        return s == null ? null : STATUS_WORDS.get(s.toLowerCase());
    }

    /**
     * @description Whether a status is final.
     * @param status the status
     * @return true for Succeeded, Failed and Cancelled
     */
    public static Boolean isFinal(String status) {
        return status == SUCCEEDED || status == FAILED || status == CANCELLED;
    }

    /**
     * @description An ISO 8601 date-time (2026-11-06T14:05:00Z, with or without milliseconds or an offset), or null.
     * @param o the value
     * @return the moment, or null
     */
    public static Datetime moment(Object o) {
        String s = text(o, 40);
        if (s == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + s.replace('"', '') + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description A whole number from a number or digits, or null.
     * @param o the value
     * @return the number, or null
     */
    public static Long whole(Object o) {
        if (o instanceof Integer || o instanceof Long) {
            return Long.valueOf(String.valueOf(o));
        }
        if (o instanceof Decimal) {
            return ((Decimal) o).round(System.RoundingMode.HALF_UP);
        }
        String s = text(o, 20);
        return s != null && s.isNumeric() ? Long.valueOf(s) : null;
    }

    /**
     * @description An https address cut to 255 characters, or null.
     * @param o the value
     * @return the address, or null
     */
    public static String url(Object o) {
        String s = text(o, 255);
        return s != null && s.startsWith('https://') && !s.containsWhitespace() ? s : null;
    }

    /**
     * @description A release number such as REL-00031 (upper-cased), or null.
     * @param o the value
     * @return the number, or null
     */
    public static String releaseNumber(Object o) {
        String s = text(o, 40);
        s = s == null ? null : s.toUpperCase();
        return s != null && RELEASE_NUMBER.matcher(s).matches() ? s : null;
    }

    /**
     * @description The jobs list ([{name, outcome, seconds}], or the same as a JSON text) as compact JSON with at most
     * 50 entries and only those three keys, or null when there are none.
     * @param o the value
     * @return the JSON, or null
     */
    public static String steps(Object o) {
        Object list = o instanceof String ? parseList((String) o) : o;
        if (!(list instanceof List<Object>)) {
            return null;
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Object item : (List<Object>) list) {
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
        String name = text(m.get('name'), 120);
        if (name == null) {
            return null;
        }
        Long seconds = whole(m.get('seconds'));
        return new Map<String, Object>{ 'name' => name, 'outcome' => text(m.get('outcome'), 20), 'seconds' => seconds };
    }

    private static Object parseList(String s) {
        try {
            return JSON.deserializeUntyped(s);
        } catch (JSONException e) {
            return null;
        }
    }
}
