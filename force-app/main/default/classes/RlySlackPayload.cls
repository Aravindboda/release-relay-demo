/**
 * @description Reads values out of a Slack interaction payload (parsed JSON) without failing on a missing key, and
 * the release a button or form names.
 */
public with sharing class RlySlackPayload {

    /**
     * @description A nested object.
     * @param m the object, or null
     * @param key the key
     * @return the nested object, or an empty one
     */
    public static Map<String, Object> child(Map<String, Object> m, String key) {
        Object o = m == null ? null : m.get(key);
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
    }

    /**
     * @description A value as text.
     * @param m the object, or null
     * @param key the key
     * @return the value, or null
     */
    public static String text(Map<String, Object> m, String key) {
        Object o = m == null ? null : m.get(key);
        return o == null ? null : String.valueOf(o);
    }

    /**
     * @description The release a button value or form names.
     * @param releaseId the release Id as text
     * @return the release, or null when it isn't one
     */
    public static RLY_Release__c release(String releaseId) {
        if (String.isBlank(releaseId)) {
            return null;
        }
        try {
            return RlyReleaseStore.release(Id.valueOf(releaseId));
        } catch (StringException e) {
            return null;
        }
    }
}
