/**
 * @description Work items (build 40; several trackers in build 47): checks the tickets sent with a release: trimmed,
 * upper-cased, without repeats, each taken by a tracker (RlyWorkRouting: the first active tracker whose pattern
 * matches; any ticket when no tracker is active), up to RlyWorkItems.MAX_TICKETS, and at least one when the admin made
 * tickets required.
 */
public with sharing class RlyWorkFormat {

    private static final Pattern SAFE_TICKET = Pattern.compile('^[A-Za-z0-9][A-Za-z0-9#._:/-]{0,79}$');

    /**
     * @description The tickets as sent: trimmed, upper-cased, without repeats, each matched to a tracker.
     * @param tickets the tickets
     * @param settings the work tracking settings (tickets required), or null
     * @return the tickets
     */
    public static List<String> ticketsChecked(List<String> tickets, RLY_Work_Tracking__c settings) {
        return ticketsChecked(tickets, settings, new Set<String>());
    }

    /**
     * @description The tickets as sent, where tickets already on the release keep their tracker (not matched again:
     * a tracker turned off since doesn't refuse them).
     * @param tickets the tickets
     * @param settings the work tracking settings (tickets required), or null
     * @param known the tickets already on the release
     * @return the tickets
     */
    public static List<String> ticketsChecked(List<String> tickets, RLY_Work_Tracking__c settings, Set<String> known) {
        List<String> out = new List<String>();
        for (String t : tickets == null ? new List<String>() : tickets) {
            String ticket = ticketOf(t, known);
            if (ticket != null && !out.contains(ticket)) {
                out.add(ticket);
            }
        }
        checkCount(out, settings);
        return out;
    }

    // Up to RlyWorkItems.MAX_TICKETS, and at least one when the admin made tickets required.
    private static void checkCount(List<String> tickets, RLY_Work_Tracking__c settings) {
        if (tickets.size() > RlyWorkItems.MAX_TICKETS) {
            throw new RlyReleaseException('A release takes up to ' + RlyWorkItems.MAX_TICKETS + ' tickets.');
        }
        if (tickets.isEmpty() && settings != null && settings.Required__c == true) {
            throw new RlyReleaseException(RlyWorkItems.REQUIRED);
        }
    }

    // One ticket trimmed and upper-cased, or null when blank; refused when it isn't a ticket or no tracker takes it.
    private static String ticketOf(String value, Set<String> known) {
        String ticket = value == null ? '' : value.trim().toUpperCase();
        if (String.isBlank(ticket)) {
            return null;
        }
        if (!SAFE_TICKET.matcher(ticket).matches()) {
            throw new RlyReleaseException('"' + value.trim().left(RlyWorkItems.MAX_LENGTH) + '" isn\'t a ticket number' + formatHint() + '.');
        }
        if (!known.contains(ticket)) {
            RlyWorkRouting.routeChecked(ticket);
        }
        return ticket;
    }

    private static String formatHint() {
        String patterns = RlyWorkRouting.patternList();
        return String.isBlank(patterns) ? '' : ' (expected: ' + patterns + ')';
    }
}
