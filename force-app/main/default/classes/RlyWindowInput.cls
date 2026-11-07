/**
 * @description A release window as the Pipeline tab sends it (build 39), checked and turned into the org's fields: days
 * in week order (unknown ones left out), From and To as HH:mm (both or neither), a time zone Salesforce knows, and
 * freezes with both dates in order and a reason. No DML, no callouts.
 */
public with sharing class RlyWindowInput {

    /** @description The org. */
    public Id orgId;
    /** @description The chosen days (none: no window, deploys any time). */
    public List<String> days;
    /** @description From, HH:mm (blank with To: all day). */
    public String fromTime;
    /** @description To, HH:mm. */
    public String toTime;
    /** @description The time zone id. */
    public String timeZone;
    /** @description The freezes ({fromDate, toDate, reason}). */
    public List<RlyWindowFreezes.Freeze> freezes;

    /**
     * @description Reads what the page sent.
     * @param inputJson the window, as JSON
     * @return the input, or null when blank
     */
    public static RlyWindowInput parse(String inputJson) {
        return String.isBlank(inputJson) ? null : (RlyWindowInput) JSON.deserialize(inputJson, RlyWindowInput.class);
    }

    /**
     * @description The org's window fields, checked (throws RlyReleaseException with a line for the page).
     * @param org the org's Id
     * @return the org row to save
     */
    public RLY_Org__c rowFor(Id org) {
        List<String> chosen = dayList();
        return new RLY_Org__c(Id = org, Window_Days__c = chosen.isEmpty() ? null : String.join(chosen, ','),
            Window_From__c = timeOrNull(fromTime), Window_To__c = timeOrNull(toTime), Window_Time_Zone__c = zoneName(),
            Window_Freezes__c = RlyWindowFreezes.toJson(checked(freezes)));
    }

    // The chosen days in week order.
    private List<String> dayList() {
        Set<String> picked = new Set<String>(days == null ? new List<String>() : days);
        List<String> out = new List<String>();
        for (String d : RlyReleaseWindow.DAYS) {
            if (picked.contains(d)) {
                out.add(d);
            }
        }
        return out;
    }

    // HH:mm, or null for none; a value that isn't a time, or only one of From and To, is refused.
    private String timeOrNull(String value) {
        Boolean fromSet = RlyReleaseWindow.minuteOf(fromTime) != null;
        Boolean toSet = RlyReleaseWindow.minuteOf(toTime) != null;
        Boolean unreadable = (String.isNotBlank(fromTime) && !fromSet) || (String.isNotBlank(toTime) && !toSet);
        if (unreadable || fromSet != toSet) {
            throw new RlyReleaseException('Give both From and To as times (HH:mm), or neither for the whole day.');
        }
        return fromSet ? value.trim().left(5) : null;
    }

    private String zoneName() {
        String z = String.isBlank(timeZone) ? RlyReleaseWindow.DEFAULT_ZONE : timeZone.trim();
        if (TimeZone.getTimeZone(z).getID() != z) {
            throw new RlyReleaseException('"' + z + '" isn\'t a time zone Salesforce knows (for example America/Chicago).');
        }
        return z;
    }

    // Each freeze needs both dates in order and a reason; the reason is trimmed.
    private static List<RlyWindowFreezes.Freeze> checked(List<RlyWindowFreezes.Freeze> rows) {
        List<RlyWindowFreezes.Freeze> out = new List<RlyWindowFreezes.Freeze>();
        for (RlyWindowFreezes.Freeze f : rows == null ? new List<RlyWindowFreezes.Freeze>() : rows) {
            Boolean dated = f != null && f.fromDate != null && f.toDate != null && f.toDate >= f.fromDate;
            if (!dated) {
                throw new RlyReleaseException('Each freeze needs a start and an end on or after it.');
            }
            if (String.isBlank(f.reason)) {
                throw new RlyReleaseException('Say why each freeze is there (for example Year-end close).');
            }
            f.reason = f.reason.normalizeSpace().left(RlyWindowFreezes.MAX_REASON);
            out.add(f);
        }
        return out;
    }
}
