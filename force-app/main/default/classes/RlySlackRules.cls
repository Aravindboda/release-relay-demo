/**
 * @description Checks the Slack values admins save: the events (only known ones), the signing secret, a channel
 * (#channel-name or a channel ID) and a Slack member ID (U… or W…).
 */
public with sharing class RlySlackRules {

    private static final Pattern SECRET = Pattern.compile('^[A-Za-z0-9]{16,175}$');
    private static final Pattern CHANNEL_NAME = Pattern.compile('^#?[A-Za-z0-9._-]{1,80}$');
    private static final Pattern MEMBER_ID = Pattern.compile('^[UW][A-Z0-9]{2,19}$');

    /**
     * @description The selected events, checked, as the multi-select picklist value.
     * @param events the events the admin ticked
     * @return the value (; separated), or null for none
     */
    public static String events(List<String> events) {
        List<String> out = new List<String>();
        Set<String> known = new Set<String>(RlySlack.EVENTS);
        for (String e : events == null ? new List<String>() : events) {
            if (!known.contains(e)) {
                throw RlySlackController.auraError(e + ' isn\'t an event ' + System.Label.RLY_App_Name + ' sends.');
            }
            out.add(e);
        }
        return out.isEmpty() ? null : String.join(out, ';');
    }

    /**
     * @description A new signing secret, checked.
     * @param secret what the admin pasted (blank keeps the saved one)
     * @return the secret, trimmed, or null when blank
     */
    public static String signingSecret(String secret) {
        if (String.isBlank(secret)) {
            return null;
        }
        if (!SECRET.matcher(secret.trim()).matches()) {
            throw RlySlackController.auraError('The signing secret is the letters and numbers under Slack app > Basic Information > Signing Secret.');
        }
        return secret.trim();
    }

    /**
     * @description Whether a value is a Slack channel name (#channel-name) or channel ID.
     * @param channel the value
     * @return true when it is
     */
    public static Boolean isChannel(String channel) {
        return String.isNotBlank(channel) && CHANNEL_NAME.matcher(channel.trim()).matches();
    }

    /**
     * @description A Slack member ID, checked.
     * @param memberId what the admin typed (blank clears the link)
     * @return the ID, trimmed and upper case, or null when blank
     */
    public static String memberId(String memberId) {
        if (String.isBlank(memberId)) {
            return null;
        }
        String value = memberId.trim().toUpperCase();
        if (!MEMBER_ID.matcher(value).matches()) {
            throw RlySlackController.auraError('A Slack member ID looks like U012AB3CD (Slack profile > ⋮ > Copy member ID).');
        }
        return value;
    }
}
