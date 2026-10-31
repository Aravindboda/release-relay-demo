/**
 * @description Checks the Slack settings an admin saves: the webhook URL must be a Slack incoming webhook
 * (https://hooks.slack.com/services/...), and only known events can be selected.
 */
public with sharing class RlySlackRules {

    private static final Integer MAX_URL = 175;

    /**
     * @description A new webhook URL, checked.
     * @param webhookUrl what the admin typed (blank keeps the saved URL)
     * @return the URL, trimmed, or null when blank
     */
    public static String webhook(String webhookUrl) {
        if (String.isBlank(webhookUrl)) {
            return null;
        }
        String url = webhookUrl.trim();
        if (!url.startsWith(RlySlack.WEBHOOK_PREFIX) || url.length() == RlySlack.WEBHOOK_PREFIX.length()
                || url.length() > MAX_URL || url.containsWhitespace()) {
            throw RlySlackController.auraError('The webhook URL must start with ' + RlySlack.WEBHOOK_PREFIX
                + ' (Slack app > Incoming Webhooks > copy the URL).');
        }
        return url;
    }

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
                throw RlySlackController.auraError(e + ' isn\'t an event Release Relay sends.');
            }
            out.add(e);
        }
        return out.isEmpty() ? null : String.join(out, ';');
    }
}
