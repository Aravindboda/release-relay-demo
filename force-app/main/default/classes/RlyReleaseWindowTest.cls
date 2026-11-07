/**
 * @description Tests for RlyReleaseWindow (build 39): open and closed moments in the window's own time zone, windows past
 * midnight, the change to daylight saving time, freezes that cover windows, the next moment a deploy may run, and the
 * summary for the org card (RlyWindowText) and freezes (RlyWindowFreezes). Pure arithmetic, no records. Each test
 * runs as an active System Administrator via System.runAs.
 */
@IsTest
private class RlyReleaseWindowTest {

    private static final String ZONE = 'America/Chicago';

    // A moment given in UTC: 'yyyy-MM-dd HH:mm'.
    private static Datetime utc(String value) {
        return Datetime.valueOfGmt(value + ':00');
    }

    // A window as an org keeps it, in Chicago; hours 'HH:mm-HH:mm'.
    private static RlyReleaseWindow window(String days, String hours, String freezes) {
        return new RlyReleaseWindow(new RLY_Org__c(Window_Days__c = days, Window_From__c = hours.substringBefore('-'),
            Window_To__c = hours.substringAfter('-'), Window_Time_Zone__c = ZONE, Window_Freezes__c = freezes));
    }

    @IsTest
    static void noWindowIsAlwaysOpen() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseWindow w = new RlyReleaseWindow(null);
            Test.startTest();
            Boolean open = w.isOpen(utc('2026-11-10 03:00'));
            Test.stopTest();
            System.assert(!w.isSet(), 'Nothing set');
            System.assert(open, 'No window: deploys any time');
            System.assertEquals(null, RlyWindowText.summary(w, utc('2026-11-10 03:00')), 'No summary');
            System.assertEquals(ZONE, w.zoneId, 'Default time zone');
        }
    }

    @IsTest
    static void weekdayEveningsInTheOrgsTimeZone() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseWindow w = window('Mon,Tue,Wed,Thu', '18:00-22:00', null);
            Test.startTest();
            Boolean tuesdayEvening = w.isOpen(utc('2026-11-11 01:00')); // Tue 7:00 PM CST
            Boolean tuesdayAfternoon = w.isOpen(utc('2026-11-10 23:00')); // Tue 5:00 PM CST
            Datetime nextFromAfternoon = w.nextOpen(utc('2026-11-10 23:00'));
            Datetime nextFromFriday = w.nextOpen(utc('2026-11-14 01:00')); // Fri 7:00 PM CST
            Test.stopTest();
            System.assert(tuesdayEvening, 'Tuesday 7 PM Chicago is in the window');
            System.assert(!tuesdayAfternoon, 'Tuesday 5 PM is before it');
            System.assertEquals(utc('2026-11-11 00:00'), nextFromAfternoon, 'Opens Tuesday 6 PM Chicago (midnight UTC)');
            System.assertEquals(utc('2026-11-17 00:00'), nextFromFriday, 'Friday is out: next is Monday 6 PM');
            System.assertEquals('Mon–Thu', RlyWindowText.dayText(w), 'Days in short');
            System.assertEquals('6:00 PM–10:00 PM', RlyWindowText.hoursText(w), 'Hours');
            System.assert(RlyWindowText.summary(w, utc('2026-11-10 23:00')).startsWith('Mon–Thu 6:00 PM–10:00 PM'), 'Summary: ' + RlyWindowText.summary(w, utc('2026-11-10 23:00')));
            System.assert(RlyWindowText.momentText(w, nextFromAfternoon).contains('6:00 PM'), 'In the org\'s time: ' + RlyWindowText.momentText(w, nextFromAfternoon));
        }
    }

    @IsTest
    static void aWindowPastMidnight() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseWindow w = window('Mon', '22:00-02:00', null);
            Test.startTest();
            Boolean mondayLate = w.isOpen(utc('2026-11-17 05:00')); // Mon 11:00 PM CST
            Boolean tuesdayEarly = w.isOpen(utc('2026-11-17 07:00')); // Tue 1:00 AM CST
            Boolean tuesdayLater = w.isOpen(utc('2026-11-17 09:00')); // Tue 3:00 AM CST
            Boolean sundayEarly = w.isOpen(utc('2026-11-16 07:00')); // Mon 1:00 AM: after Sunday, not chosen
            Test.stopTest();
            System.assert(mondayLate, 'Monday 11 PM is in');
            System.assert(tuesdayEarly, 'Tuesday 1 AM is still Monday\'s window');
            System.assert(!tuesdayLater, 'Tuesday 3 AM is past it');
            System.assert(!sundayEarly, 'Monday 1 AM belongs to Sunday\'s night, which isn\'t chosen');
        }
    }

    @IsTest
    static void theClocksGoForward() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseWindow w = window('Sun', '03:00-05:00', null);
            Test.startTest();
            Datetime next = w.nextOpen(utc('2026-03-08 05:00')); // Sat 11:00 PM CST
            Test.stopTest();
            System.assertEquals(utc('2026-03-08 08:00'), next, 'Sunday 3 AM CDT (UTC-5) on the day the clocks change');
        }
    }

    @IsTest
    static void freezesHoldWindowsAndEndAtMidnight() {
        System.runAs(RlyTestData.admin()) {
            String freezes = '[{"from":"2026-12-28","to":"2027-01-02","reason":"Year-end close"},{"from":"bad","to":"x"},'
                + '{"from":"2026-11-16","to":"2026-11-20","reason":"Go-live week"}]';
            RlyReleaseWindow weekdays = window('Mon,Tue,Wed,Thu,Fri', '18:00-22:00', freezes);
            RlyReleaseWindow nightly = window('Mon,Tue,Wed,Thu,Fri,Sat,Sun', '22:00-02:00',
                '[{"from":"2026-12-31","to":"2026-12-31","reason":"New year"}]');
            Test.startTest();
            Datetime inFreeze = utc('2026-12-30 01:00'); // Tue 29 Dec 7:00 PM CST
            Boolean open = weekdays.isOpen(inFreeze);
            RlyWindowFreezes.Freeze f = weekdays.freezeAt(inFreeze);
            Datetime afterFreeze = weekdays.nextOpen(inFreeze);
            Datetime midnight = nightly.nextOpen(utc('2027-01-01 05:00')); // Thu 31 Dec 11:00 PM CST
            Test.stopTest();
            System.assertEquals(2, weekdays.freezes.size(), 'The unreadable freeze is dropped');
            System.assertEquals(Date.newInstance(2026, 11, 16), weekdays.freezes[0].fromDate, 'Earliest first');
            System.assert(!open, 'Frozen');
            System.assertEquals('Year-end close', f.reason, 'Which freeze');
            System.assertEquals(utc('2027-01-05 00:00'), afterFreeze, 'Monday 4 Jan 6 PM, the first window after the freeze');
            System.assertEquals(utc('2027-01-01 06:00'), midnight, 'The freeze ends at midnight, inside the night window');
            System.assert(RlyWindowText.summary(weekdays, inFreeze).contains('frozen until 2 Jan 2027'), 'Summary: ' + RlyWindowText.summary(weekdays, inFreeze));
            System.assert(RlyWindowText.summary(weekdays, utc('2026-11-10 18:00')).contains('next freeze 16 Nov 2026'), 'Next freeze named');
        }
    }

    @IsTest
    static void valuesAreReadCarefully() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyReleaseWindow allDay = new RlyReleaseWindow(new RLY_Org__c(Window_Days__c = 'mon, Wed ,fri,xyz',
                Window_Time_Zone__c = 'Europe/London'));
            RlyReleaseWindow everyDay = window('Mon,Tue,Wed,Thu,Fri,Sat,Sun', '09:00-09:00', 'not json');
            Test.stopTest();
            System.assertEquals('Mon, Wed, Fri', RlyWindowText.dayText(allDay), 'Days read, unknown dropped');
            System.assertEquals('all day', RlyWindowText.hoursText(allDay), 'No hours: the whole day');
            System.assert(allDay.isOpen(utc('2026-11-11 12:00')), 'Wednesday noon London');
            System.assert(!allDay.isOpen(utc('2026-11-10 12:00')), 'Tuesday isn\'t chosen');
            System.assertEquals('Every day', RlyWindowText.dayText(everyDay), 'Every day');
            System.assertEquals('all day', RlyWindowText.hoursText(everyDay), 'From equal to To: the whole day');
            System.assertEquals(0, everyDay.freezes.size(), 'Bad JSON: no freezes');
            System.assertEquals(null, RlyReleaseWindow.minuteOf('25:00'), 'Not a time');
            System.assertEquals(570, RlyReleaseWindow.minuteOf('09:30:00.000Z'), 'A time from the page');
            System.assertEquals(null, RlyWindowFreezes.toJson(new List<RlyWindowFreezes.Freeze>()), 'No freezes, no JSON');
        }
    }
}
