/**
 * @description Tests for the Archive tab's numbers and the nightly job's health (RlyArchiveStats, RlyArchiveRuns.view)
 * and the Home tab's "Nightly archive" health item (RlyHomeHealth): totals, releases per calendar month over the last
 * 12 months, nightly runs of the last 30 days per status, the last failure and missed nights. The archive's clock is
 * fixed mid-month so months don't depend on the day the tests run. Each test runs through System.runAs as the active
 * System Administrator with Release Relay Admin, or a user without it.
 */
@IsTest
private class RlyArchiveRunsTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // 15 Nov 2026, noon (the viewer's time zone).
    private static Datetime fixedNow() {
        return Datetime.newInstance(2026, 11, 15, 12, 0, 0);
    }

    private static RlyHomeHealth.Item archiveItem() {
        for (RlyHomeHealth.Item i : RlyHomeHealth.read().items) {
            if (i.key == 'archive') {
                return i;
            }
        }
        return null;
    }

    @IsTest
    static void countsMonthsAndHealth() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.nightly(30);
            RlyArchiveService.nowForTest = fixedNow();
            RlyArchiveTestData.run(RlyArchiveRuns.NIGHTLY, RlyArchiveRuns.SUCCEEDED, fixedNow().addDays(-1));
            RlyArchiveTestData.run(RlyArchiveRuns.NIGHTLY, RlyArchiveRuns.SUCCEEDED, fixedNow().addDays(-2));
            RLY_Archive_Run__c failed = RlyArchiveTestData.run(RlyArchiveRuns.NIGHTLY, RlyArchiveRuns.FAILED, fixedNow().addDays(-3));
            update new RLY_Archive_Run__c(Id = failed.Id, Pipeline_Run_Url__c = 'https://github.com/acme/release/actions/runs/4821');
            RlyArchiveTestData.run(RlyArchiveRuns.NIGHTLY, RlyArchiveRuns.PARTIAL, fixedNow().addDays(-4));
            RlyArchiveTestData.run(RlyArchiveRuns.NIGHTLY, RlyArchiveRuns.FAILED, fixedNow().addDays(-40));
            RlyArchiveTestData.run(RlyArchiveRuns.RUN_NOW, RlyArchiveRuns.CANCELLED, Datetime.newInstance(2026, 3, 14, 16, 0, 0));
            RlyArchiveTestData.run(RlyArchiveRuns.RUN_NOW, RlyArchiveRuns.SUCCEEDED, Datetime.newInstance(2025, 10, 1, 9, 0, 0));
            update new RLY_Git_Connection__c(Id = RlyArchiveTestData.settings().Id, Last_Nightly_Call__c = fixedNow().addHours(-10),
                Last_Nightly_Result__c = 'Succeeded');
            Test.startTest();
            RlyArchiveViews.Archive a = RlyArchiveController.readArchive();
            Test.stopTest();
            System.assertEquals(7, a.runCount, 'Every run');
            System.assertEquals(70, a.archivedReleases, '10 each');
            System.assertEquals(350, a.archivedRecords, '50 each');
            System.assertEquals(700, a.freedKB, '100 KB each');
            System.assertEquals(Datetime.newInstance(2025, 10, 1, 9, 0, 0), a.firstRun, 'First run');
            System.assertEquals(7, a.runs.size(), 'Runs list');
            System.assertEquals(a.runs[0].id, a.lastRun.id, 'Newest first');
            System.assertEquals(RlyArchiveRuns.PIPELINE_JOB, a.lastRun.runBy, 'Nightly rows show the pipeline job');
            System.assertEquals('Nightly', a.lastRun.how, 'How');
            System.assertEquals(12, a.months.size(), '12 months');
            System.assertEquals('Dec', a.months[0].label, 'Oldest: December 2025');
            System.assertEquals(2025, a.months[0].year, 'Year');
            System.assertEquals('Nov', a.months[11].label, 'Newest: this month');
            System.assertEquals(40, a.months[11].releases, 'Four runs in November');
            System.assertEquals(10, a.months[10].releases, 'One in October (40 days back)');
            System.assertEquals(10, a.months[3].releases, 'March');
            checkHealth(a.health, failed.Id);
        }
    }

    private static void checkHealth(RlyArchiveViews.Health h, Id failedId) {
        System.assertEquals(4, h.runs, 'Nightly runs of the last 30 days');
        System.assertEquals(2, h.succeeded, 'Succeeded');
        System.assertEquals(1, h.failed, 'Failed');
        System.assertEquals(1, h.partial, 'Partial');
        System.assertEquals(0, h.missedNights, 'Called 10 hours ago');
        System.assertEquals('Succeeded', h.lastCallResult, 'Last call');
        System.assertEquals(failedId, h.lastFailure.id, 'Last failure of the 30 days');
        System.assertEquals('https://github.com/acme/release/actions/runs/4821', h.lastFailure.pipelineUrl, 'Run link');
    }

    @IsTest
    static void countsMissedNights() {
        System.runAs(RlyTestData.admin()) {
            Id connId = RlyArchiveTestData.hub().Id;
            RlyArchiveService.nowForTest = fixedNow();
            RLY_Git_Connection__c conn = new RLY_Git_Connection__c(Id = connId, Retention_Days__c = 30, Archive_Nightly__c = false,
                Last_Nightly_Call__c = fixedNow().addDays(-5));
            Test.startTest();
            Integer off = RlyArchiveStats.missedNights(conn);
            conn.Archive_Nightly__c = true;
            Integer five = RlyArchiveStats.missedNights(conn);
            conn.Last_Nightly_Call__c = fixedNow().addHours(-25);
            Integer none = RlyArchiveStats.missedNights(conn);
            conn.Last_Nightly_Call__c = fixedNow().addHours(-30);
            Integer one = RlyArchiveStats.missedNights(conn);
            conn.Last_Nightly_Call__c = null;
            conn.Retention_Changed_On__c = fixedNow().addHours(-50);
            Integer sinceOn = RlyArchiveStats.missedNights(conn);
            conn.Retention_Changed_On__c = null;
            Integer unknown = RlyArchiveStats.missedNights(conn);
            Test.stopTest();
            System.assertEquals(0, off, 'Nightly off');
            System.assertEquals(5, five, 'Five nights');
            System.assertEquals(0, none, 'Within 26 hours');
            System.assertEquals(1, one, 'Missed last night');
            System.assertEquals(2, sinceOn, 'Counted from when nightly was turned on');
            System.assertEquals(0, unknown, 'Nothing to count from');
            System.assertEquals(0, RlyArchiveStats.missedNights(null), 'No settings');
        }
    }

    @IsTest
    static void homeShowsMissedNightsToAdmins() {
        User plain = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.nightly(30);
            update new RLY_Git_Connection__c(Id = RlyArchiveTestData.settings().Id, Last_Nightly_Call__c = System.now().addHours(-30));
            Test.startTest();
            RlyHomeHealth.Item lastNight = archiveItem();
            update new RLY_Git_Connection__c(Id = RlyArchiveTestData.settings().Id, Last_Nightly_Call__c = System.now().addDays(-3));
            RlyHomeHealth.Item three = archiveItem();
            Test.stopTest();
            System.assertEquals('Nightly archive', lastNight.label, 'Label');
            System.assertEquals('missed last night', lastNight.text, 'One night');
            System.assertEquals(RlyHomeHealth.TONE_WAIT, lastNight.tone, 'Amber');
            System.assertEquals(RlyArchiveService.ARCHIVE_TAB, lastNight.tab, 'Opens the Archive tab');
            System.assertEquals('missed the last 3 nights', three.text, 'Three nights');
            System.assertEquals(RlyHomeHealth.TONE_BAD, three.tone, 'Red');
        }
        System.runAs(plain) {
            System.assertEquals(null, archiveItem(), 'Only admins see it');
        }
    }

    @IsTest
    static void homeQuietWhenNightlyIsOff() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.retention(30);
            Test.startTest();
            RlyHomeHealth.Item i = archiveItem();
            Test.stopTest();
            System.assertEquals(null, i, 'Nightly off: no item');
        }
    }
}
