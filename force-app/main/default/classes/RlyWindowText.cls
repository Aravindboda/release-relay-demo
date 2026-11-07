/**
 * @description Release windows in words (build 39): the org card's summary ("Mon–Thu 6:00 PM–10:00 PM CST · next freeze
 * 16 Nov 2026"), what happens now ("Open now", "Closed: deploys Mon 16 Nov, 6:00 PM CST", "Frozen until …"), days,
 * hours, moments in the window's time zone and dates. No DML, no callouts.
 */
public with sharing class RlyWindowText {

    /** @description How many days ahead the Home tab warns of a freeze. */
    public static final Integer SOON_DAYS = 7;

    /**
     * @description The window in a few words, for the org card.
     * @param w the window
     * @param now the moment (for the next freeze)
     * @return the summary, or null when the org has no window or freeze
     */
    public static String summary(RlyReleaseWindow w, Datetime now) {
        if (!w.isSet()) {
            return null;
        }
        List<String> parts = new List<String>();
        if (!w.days.isEmpty()) {
            parts.add(dayText(w) + ' ' + hoursText(w) + ' ' + now.format('z', w.zoneId));
        }
        RlyWindowFreezes.Freeze current = w.freezeAt(now);
        RlyWindowFreezes.Freeze next = w.nextFreeze(now);
        if (current != null) {
            parts.add('frozen until ' + dateText(current.toDate));
        } else if (next != null) {
            parts.add('next freeze ' + dateText(next.fromDate));
        }
        return String.join(parts, ' · ');
    }

    /**
     * @description What happens to a deploy now.
     * @param w the window
     * @param now the moment
     * @return the line
     */
    public static String state(RlyReleaseWindow w, Datetime now) {
        if (!w.isSet()) {
            return 'No window: deploys run any time';
        }
        RlyWindowFreezes.Freeze f = w.freezeAt(now);
        if (f != null) {
            return 'Frozen until ' + dateText(f.toDate) + (String.isBlank(f.reason) ? '' : ': ' + f.reason);
        }
        if (w.isOpen(now)) {
            return 'Open now';
        }
        Datetime next = w.nextOpen(now);
        return 'Closed' + (next == null ? '' : ': deploys ' + momentText(w, next));
    }

    /**
     * @description A freeze running now or starting within SOON_DAYS, for the Home tab: "PROD is frozen until 2 Jan
     * 2027: Year-end close." or "PROD freeze starts in 3 days (16 Nov 2026): Go-live week."
     * @param orgName the org's name
     * @param w its window
     * @param now the moment
     * @return the line, or null when no freeze is that close
     */
    public static String soon(String orgName, RlyReleaseWindow w, Datetime now) {
        RlyWindowFreezes.Freeze f = w.nextFreeze(now);
        if (f == null) {
            return null;
        }
        String why = String.isBlank(f.reason) ? '.' : ': ' + f.reason + '.';
        if (w.freezeAt(now) != null) {
            return orgName + ' is frozen until ' + dateText(f.toDate) + why;
        }
        Integer inDays = w.localDate(now).daysBetween(f.fromDate);
        if (inDays > SOON_DAYS) {
            return null;
        }
        return orgName + ' freeze starts ' + (inDays <= 1 ? 'tomorrow' : 'in ' + inDays + ' days') + ' ('
            + dateText(f.fromDate) + ')' + why;
    }

    /**
     * @description The days in short: "Mon–Thu", "Mon, Wed, Fri", "Every day".
     * @param w the window
     * @return the text
     */
    public static String dayText(RlyReleaseWindow w) {
        List<Integer> idx = new List<Integer>();
        for (Integer i = 0; i < RlyReleaseWindow.DAY_CODES.size(); i++) {
            if (w.days.contains(RlyReleaseWindow.DAY_CODES[i])) {
                idx.add(i);
            }
        }
        if (idx.size() == RlyReleaseWindow.DAY_CODES.size()) {
            return 'Every day';
        }
        if (idx.size() > 2 && idx[idx.size() - 1] - idx[0] == idx.size() - 1) {
            return RlyReleaseWindow.DAY_CODES[idx[0]] + '–' + RlyReleaseWindow.DAY_CODES[idx[idx.size() - 1]];
        }
        List<String> names = new List<String>();
        for (Integer i : idx) {
            names.add(RlyReleaseWindow.DAY_CODES[i]);
        }
        return String.join(names, ', ');
    }

    /**
     * @description The hours: "6:00 PM–10:00 PM", or "all day".
     * @param w the window
     * @return the text
     */
    public static String hoursText(RlyReleaseWindow w) {
        return w.startMinute == null ? 'all day' : clock(w.startMinute) + '–' + clock(w.endMinute);
    }

    /**
     * @description A moment in the window's time zone: "Mon 16 Nov, 6:00 PM CST".
     * @param w the window
     * @param moment the moment
     * @return the text
     */
    public static String momentText(RlyReleaseWindow w, Datetime moment) {
        return moment == null ? '' : moment.format('EEE d MMM, h:mm a z', w.zoneId);
    }

    /**
     * @description A date: "16 Nov 2026".
     * @param d the date
     * @return the text
     */
    public static String dateText(Date d) {
        return d == null ? '' : Datetime.newInstanceGmt(d, Time.newInstance(12, 0, 0, 0)).formatGmt('d MMM yyyy');
    }

    private static String clock(Integer minute) {
        Integer h = minute / 60;
        Integer h12 = Math.mod(h, 12) == 0 ? 12 : Math.mod(h, 12);
        return h12 + ':' + String.valueOf(Math.mod(minute, 60)).leftPad(2, '0') + ' ' + (h < 12 ? 'AM' : 'PM');
    }
}
