/**
 * @description Work items (build 40): the tickets on a release. Raising checks them against the admin's ticket format
 * (and that there is one when tickets are required) and saves one RLY_Work_Item__c row per ticket, plus the comma list
 * on the release (Work_Items__c) for search, lists and exports. A promotion carries the tickets of the releases it
 * carries; a ticket can be added or removed on the release page until the release is deployed. With no settings saved,
 * tickets are optional and any text up to 80 characters is a ticket.
 */
public with sharing class RlyWorkItems {

    /** @description Most tickets on one release. */
    public static final Integer MAX_TICKETS = 20;
    /** @description Longest ticket. */
    public static final Integer MAX_LENGTH = 80;
    /** @description Refused when tickets are required and none came. */
    public static final String REQUIRED = 'Add the release\'s ticket (for example PROJ-123): your admin made tickets required.';
    /** @description Statuses after which tickets stay as they are. */
    public static final Set<String> CLOSED = new Set<String>{ 'Deployed', 'Rejected', 'Closed', 'Merged' };

    /**
     * @description The tickets as sent: trimmed, upper-cased, without repeats, checked against the format.
     * @param tickets the tickets
     * @param settings the work tracking settings, or null
     * @return the tickets
     */
    public static List<String> checked(List<String> tickets, RLY_Work_Tracking__c settings) {
        return RlyWorkFormat.ticketsChecked(tickets, settings);
    }

    /**
     * @description Saves a raised release's tickets (after the release is inserted).
     * @param rel the release
     * @param tickets the checked tickets
     */
    public static void attach(RLY_Release__c rel, List<String> tickets) {
        if (rel == null || rel.Id == null || tickets == null || tickets.isEmpty()) {
            return;
        }
        rel.Work_Items__c = joined(tickets);
        RlyWorkStore.save(rows(rel.Id, tickets, new List<RLY_Work_Item__c>()), null, rel);
    }

    /**
     * @description A promotion carries the tickets of the releases it carries.
     * @param promotion the saved promotion
     * @param carriedIds the carried releases
     */
    public static void carry(RLY_Release__c promotion, Set<Id> carriedIds) {
        if (promotion == null || promotion.Id == null) {
            return;
        }
        List<String> tickets = new List<String>();
        Set<String> seen = new Set<String>();
        for (RLY_Work_Item__c w : RlyWorkStore.forReleases(carriedIds)) {
            if (seen.add(w.Ticket__c) && tickets.size() < MAX_TICKETS) {
                tickets.add(w.Ticket__c);
            }
        }
        attach(promotion, tickets);
    }

    /**
     * @description Replaces a release's tickets (release page), until it is deployed, rejected or closed.
     * @param releaseId the release
     * @param tickets the tickets
     * @return the release's tickets as saved
     */
    public static List<String> replace(Id releaseId, List<String> tickets) {
        RLY_Release__c rel = RlyWorkStore.release(releaseId);
        if (rel == null) {
            throw new RlyReleaseException('Release not found.');
        }
        if (CLOSED.contains(rel.Status__c)) {
            throw new RlyReleaseException('The release is ' + rel.Status__c.toLowerCase() + ': its tickets stay as they are.');
        }
        List<String> wanted = checked(tickets, RlyWorkStore.trackingSettings());
        Set<String> keep = new Set<String>(wanted);
        List<RLY_Work_Item__c> existing = RlyWorkStore.forRelease(releaseId);
        List<RLY_Work_Item__c> gone = new List<RLY_Work_Item__c>();
        for (RLY_Work_Item__c w : existing) {
            if (!keep.contains(w.Ticket__c)) {
                gone.add(w);
            }
        }
        rel.Work_Items__c = wanted.isEmpty() ? null : joined(wanted);
        RlyWorkStore.save(rows(releaseId, wanted, existing), gone, rel);
        return wanted;
    }

    /**
     * @description The row key of a ticket on a release.
     * @param releaseId the release
     * @param ticket the ticket
     * @return the key
     */
    public static String keyOf(Id releaseId, String ticket) {
        return String.valueOf(releaseId) + ':' + ticket.toUpperCase();
    }

    /**
     * @description The tickets as one comma list (cut to the field's 255 characters at a whole ticket).
     * @param tickets the tickets
     * @return the list
     */
    public static String joined(List<String> tickets) {
        String out = '';
        for (String t : tickets) {
            String longer = out == '' ? t : out + ', ' + t;
            if (longer.length() > 255) {
                break;
            }
            out = longer;
        }
        return out == '' ? null : out;
    }

    // New rows for tickets not yet on the release (existing rows keep what was posted).
    private static List<RLY_Work_Item__c> rows(Id releaseId, List<String> tickets, List<RLY_Work_Item__c> existing) {
        Set<String> have = new Set<String>();
        for (RLY_Work_Item__c w : existing) {
            have.add(w.Ticket__c);
        }
        List<RLY_Work_Item__c> out = new List<RLY_Work_Item__c>();
        for (String t : tickets) {
            if (!have.contains(t)) {
                out.add(new RLY_Work_Item__c(Release__c = releaseId, Ticket__c = t, Key__c = keyOf(releaseId, t)));
            }
        }
        return out;
    }
}
