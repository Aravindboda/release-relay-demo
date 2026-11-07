/**
 * @description Work items (build 47): the format of each field of a tracker: ticket patterns that are valid
 * expressions, an https link with {id}, a Named Credential API name (needed to post), a ServiceNow table name and a
 * state map that is a JSON object.
 */
public with sharing class RlyWorkTrackerFields {

    private static final Pattern API_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Integer MAX_STATE_MAP = 2000;

    /**
     * @description Checks space-separated regular expressions (up to 255 characters).
     * @param patterns the patterns, or null
     * @param what what they are, for the message
     */
    public static void checkPatterns(String patterns, String what) {
        String p = trimmed(patterns);
        if (p == null) {
            return;
        }
        if (p.length() > 255) {
            throw new RlyReleaseException('The ' + what + ' is up to 255 characters.');
        }
        for (String f : p.split('\\s+')) {
            try {
                Pattern.compile(f);
            } catch (Exception e) {
                throw new RlyReleaseException('"' + f + '" in the ' + what + ' isn\'t a valid pattern.');
            }
        }
    }

    /**
     * @description The link, checked: https:// with {id}, up to 255 characters.
     * @param value the link, or blank
     * @return the link, or null
     */
    public static String linkOf(String value) {
        String link = trimmed(value);
        if (link != null && (!link.startsWith('https://') || !link.contains('{id}') || link.length() > 255)) {
            throw new RlyReleaseException('The link starts with https:// and has {id} where the ticket number goes.');
        }
        return link;
    }

    /**
     * @description The Named Credential's API name, checked.
     * @param value the name, or blank
     * @return the name, or null
     */
    public static String credentialOf(String value) {
        String credential = trimmed(value);
        if (credential != null && !API_NAME.matcher(credential).matches()) {
            throw new RlyReleaseException('The Named Credential is its API name, for example RLY_Work_Jira.');
        }
        return credential;
    }

    /**
     * @description The ServiceNow table's name, checked.
     * @param value the table, or blank
     * @return the table, or null
     */
    public static String tableOf(String value) {
        String table = trimmed(value);
        if (table != null && !API_NAME.matcher(table).matches()) {
            throw new RlyReleaseException('The ServiceNow table is its name, for example change_request.');
        }
        return table;
    }

    /**
     * @description The state map, checked: a JSON object up to 2000 characters.
     * @param value the map, or blank
     * @return the map, or null
     */
    public static String stateMapOf(String value) {
        String stateMap = trimmed(value);
        if (stateMap == null) {
            return null;
        }
        Boolean ok;
        try {
            ok = stateMap.length() <= MAX_STATE_MAP && JSON.deserializeUntyped(stateMap) instanceof Map<String, Object>;
        } catch (JSONException e) {
            ok = false;
        }
        if (!ok) {
            throw new RlyReleaseException('The state map is JSON like {"Deployed to SIT":"In QA"} (up to ' + MAX_STATE_MAP + ' characters).');
        }
        return stateMap;
    }

    /**
     * @description Trimmed text, or null when blank.
     * @param s the text
     * @return the text
     */
    public static String trimmed(String s) {
        return String.isBlank(s) ? null : s.trim();
    }
}
