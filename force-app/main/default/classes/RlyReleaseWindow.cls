/**
 * @description An org's release window (build 39): the days and hours deploys into it may run, in its own time zone, and
 * its freeze periods (whole days, both ends included) when no deploy runs. An org without days has no window: deploys
 * run any time. A window whose To is earlier than its From runs past midnight (Mon 22:00–02:00 is open Mon 22:00 to
 * Tue 02:00); without From and To it is the whole day. Words for people: RlyWindowText; freezes: RlyWindowFreezes.
 * No DML, no callouts.
 */
public with sharing class RlyReleaseWindow {

    /** @description The day codes, Monday first. */
    public static final List<String> DAYS = new List<String>{ 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' };
    /** @description The time zone when the org has none. */
    public static final String DEFAULT_ZONE = 'America/Chicago';
    private static final Integer LOOK_AHEAD_DAYS = 400;
    private TimeZone zone;

    /** @description The chosen days (Mon, Tue, …). */
    public Set<String> days { get; private set; }
    /** @description The window's start, in minutes after midnight (null: the whole day). */
    public Integer startMinute { get; private set; }
    /** @description The window's end, in minutes after midnight (earlier than the start: past midnight). */
    public Integer endMinute { get; private set; }
    /** @description The time zone id. */
    public String zoneId { get; private set; }
    /** @description The freezes, earliest first. */
    public List<RlyWindowFreezes.Freeze> freezes { get; private set; }

    /**
     * @description A window from an org's fields (unreadable values are left out).
     * @param org the org, with Window_Days__c, Window_From__c, Window_To__c, Window_Time_Zone__c, Window_Freezes__c
     */
    public RlyReleaseWindow(RLY_Org__c org) {
        RLY_Org__c o = org == null ? new RLY_Org__c() : org;
        days = new Set<String>();
        for (String d : (String.isBlank(o.Window_Days__c) ? '' : o.Window_Days__c).split(',')) {
            String code = d.trim().left(3).toLowerCase().capitalize();
            if (DAYS.contains(code)) {
                days.add(code);
            }
        }
        startMinute = minuteOf(o.Window_From__c);
        endMinute = minuteOf(o.Window_To__c);
        if (startMinute == null || endMinute == null || startMinute == endMinute) {
            startMinute = null; // the whole day
            endMinute = null;
        }
        zoneId = String.isBlank(o.Window_Time_Zone__c) ? DEFAULT_ZONE : o.Window_Time_Zone__c.trim();
        zone = TimeZone.getTimeZone(zoneId);
        freezes = RlyWindowFreezes.parse(o.Window_Freezes__c);
    }

    /**
     * @description Whether the org limits when deploys run (days chosen, or a freeze set).
     * @return true with a window or a freeze
     */
    public Boolean isSet() {
        return !days.isEmpty() || !freezes.isEmpty();
    }

    /**
     * @description Whether a deploy may run now: inside the window (or no window) and outside every freeze.
     * @param now the moment
     * @return true when open
     */
    public Boolean isOpen(Datetime now) {
        return freezeAt(now) == null && inWindow(now);
    }

    /**
     * @description The freeze a moment falls in.
     * @param now the moment
     * @return the freeze, or null
     */
    public RlyWindowFreezes.Freeze freezeAt(Datetime now) {
        return RlyWindowFreezes.covering(freezes, localDate(now));
    }

    /**
     * @description The freeze running now or the next one to start.
     * @param now the moment
     * @return the freeze, or null
     */
    public RlyWindowFreezes.Freeze nextFreeze(Datetime now) {
        return RlyWindowFreezes.notOver(freezes, localDate(now));
    }

    /**
     * @description The next moment a deploy may run: now when open, else the next window start or the end of a freeze
     * (local midnight) that falls in the window, within LOOK_AHEAD_DAYS.
     * @param now the moment
     * @return the moment, or null when there's none in sight
     */
    public Datetime nextOpen(Datetime now) {
        if (isOpen(now)) {
            return now;
        }
        Date today = localDate(now);
        for (Integer i = 0; i <= LOOK_AHEAD_DAYS; i++) {
            Datetime found = openOn(today.addDays(i), now);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    /**
     * @description The moment's date in the window's time zone.
     * @param now the moment
     * @return the local date
     */
    public Date localDate(Datetime now) {
        return now.addSeconds(zone.getOffset(now) / 1000).dateGmt();
    }

    /**
     * @description A time HH:mm as minutes after midnight.
     * @param value HH:mm (or HH:mm:ss…)
     * @return the minutes, or null when it isn't a time
     */
    public static Integer minuteOf(String value) {
        String v = value == null ? '' : value.trim().left(5);
        if (!Pattern.matches('([01]\\d|2[0-3]):[0-5]\\d', v)) {
            return null;
        }
        return Integer.valueOf(v.left(2)) * 60 + Integer.valueOf(v.right(2));
    }

    // The first open moment on a local day after now: its midnight (a freeze ending, a window past midnight) or its start.
    private Datetime openOn(Date d, Datetime now) {
        for (Datetime candidate : new List<Datetime>{ instantOf(d, 0), startMinute == null ? null : instantOf(d, startMinute) }) {
            if (candidate != null && candidate > now && isOpen(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private Boolean inWindow(Datetime now) {
        if (days.isEmpty()) {
            return true;
        }
        Date today = localDate(now);
        Integer minute = localMinute(now);
        Boolean todayChosen = days.contains(dayCode(today));
        if (startMinute == null) {
            return todayChosen;
        }
        if (startMinute < endMinute) {
            return todayChosen && minute >= startMinute && minute < endMinute;
        }
        // Past midnight: the evening part on a chosen day, or the morning part after a chosen day.
        return (todayChosen && minute >= startMinute) || (days.contains(dayCode(today.addDays(-1))) && minute < endMinute);
    }

    private Integer localMinute(Datetime now) {
        Datetime local = now.addSeconds(zone.getOffset(now) / 1000);
        return local.hourGmt() * 60 + local.minuteGmt();
    }

    // The moment a local date and minute stand for (the offset is checked twice, for days the clocks change).
    private Datetime instantOf(Date d, Integer minute) {
        Datetime asGmt = Datetime.newInstanceGmt(d, Time.newInstance(minute / 60, Math.mod(minute, 60), 0, 0));
        Datetime guess = asGmt.addSeconds(-zone.getOffset(asGmt) / 1000);
        return asGmt.addSeconds(-zone.getOffset(guess) / 1000);
    }

    /**
     * @description A date's day code (1 Jan 1900 was a Monday).
     * @param d the date
     * @return Mon … Sun
     */
    public static String dayCode(Date d) {
        Integer index = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7);
        return DAYS[index < 0 ? index + 7 : index];
    }
}
