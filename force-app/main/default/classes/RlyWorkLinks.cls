/**
 * @description Work items (build 40): tickets as links, from the admin's link pattern (https://…{id}): one ticket's
 * address, and a release's ticket list with links for the CSV, the evidence PDF and Slack messages.
 */
public with sharing class RlyWorkLinks {

    /**
     * @description A ticket's link from the admin's pattern ({id}), or null.
     * @param ticket the ticket
     * @param settings the settings, or null
     * @return the address
     */
    public static String linkOf(String ticket, RLY_Work_Tracking__c settings) {
        String pattern = settings == null ? null : settings.Link_Pattern__c;
        if (String.isBlank(pattern) || !pattern.startsWith('https://') || !pattern.contains('{id}')) {
            return null;
        }
        return pattern.replace('{id}', EncodingUtil.urlEncode(ticket, 'UTF-8'));
    }

    /**
     * @description A release's ticket list with each ticket's link, for exports: CLAIMS-412 (https://…), CLAIMS-418.
     * @param joined the release's Work_Items__c
     * @return the text, or null
     */
    public static String withLinks(String joined) {
        if (String.isBlank(joined)) {
            return null;
        }
        List<String> out = new List<String>();
        for (String t : joined.split(',\\s*')) {
            String link = linkOf(t.trim(), RlyWorkStore.trackingSettings());
            out.add(link == null ? t.trim() : t.trim() + ' (' + link + ')');
        }
        return String.join(out, ', ');
    }

    /**
     * @description A release's ticket list as Slack links (<https://…|CLAIMS-412>), or escaped text without a link.
     * @param joined the release's Work_Items__c
     * @return the Slack text, or null
     */
    public static String slackLinks(String joined) {
        if (String.isBlank(joined)) {
            return null;
        }
        List<String> out = new List<String>();
        for (String t : joined.split(',\\s*')) {
            String link = linkOf(t.trim(), RlyWorkStore.trackingSettings());
            String label = RlySlackMessage.esc(t.trim());
            out.add(link == null ? label : '<' + link + '|' + label + '>');
        }
        return String.join(out, ', ');
    }
}
