/**
 * @description Work items (build 40): checks the tickets sent with a release: trimmed, upper-cased, without repeats,
 * each in one of the admin's ticket formats (space-separated regular expressions; any ticket when there are none), up
 * to RlyWorkItems.MAX_TICKETS, and at least one when the admin made tickets required.
 */
public with sharing class RlyWorkFormat {

    private static final Pattern SAFE_TICKET = Pattern.compile('^[A-Za-z0-9][A-Za-z0-9#._:/-]{0,79}$');

    /**
     * @description The tickets as sent: trimmed, upper-cased, without repeats, checked against the format.
     * @param tickets the tickets
     * @param settings the work tracking settings, or null
     * @return the tickets
     */
    public static List<String> ticketsChecked(List<String> tickets, RLY_Work_Tracking__c settings) {
        List<String> out = new List<String>();
        for (String t : tickets == null ? new List<String>() : tickets) {
            String ticket = ticketOf(t, settings);
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

    // One ticket trimmed and upper-cased, or null when blank; refused when it isn't in the format.
    private static String ticketOf(String value, RLY_Work_Tracking__c settings) {
        String ticket = value == null ? '' : value.trim().toUpperCase();
        if (String.isBlank(ticket)) {
            return null;
        }
        if (!SAFE_TICKET.matcher(ticket).matches() || !matchesFormat(ticket, settings)) {
            throw new RlyReleaseException('"' + value.trim().left(RlyWorkItems.MAX_LENGTH) + '" isn\'t a ticket number' + formatHint(settings) + '.');
        }
        return ticket;
    }

    // Matches one of the admin's formats (space separated regular expressions), or any when there are none.
    private static Boolean matchesFormat(String ticket, RLY_Work_Tracking__c settings) {
        String formats = settings == null ? null : settings.Ticket_Pattern__c;
        if (String.isBlank(formats)) {
            return true;
        }
        for (String f : formats.trim().split('\\s+')) {
            try {
                if (Pattern.compile('(?i)^(?:' + f + ')$').matcher(ticket).matches()) {
                    return true;
                }
            } catch (Exception e) {
                continue; // a format that isn't a valid expression is skipped (the settings check refuses it on save)
            }
        }
        return false;
    }

    private static String formatHint(RLY_Work_Tracking__c settings) {
        return settings == null || String.isBlank(settings.Ticket_Pattern__c) ? '' : ' (expected: ' + settings.Ticket_Pattern__c.trim() + ')';
    }
}
