/**
 * @description Retention and the Archive tab, for RlyArchiveController; RlyArchiveRunner makes the runs. Works only in
 * the production hub (RlyHubGuard: the hub, not a sandbox, a copy or a sandbox with the admin override); elsewhere the
 * pages get the org gate and every action is refused. Admins (RLY_Admin) edit Retention and run the archive; approvers
 * (RLY_Approver) see the Archive tab. Counts come from RlyArchiveEligible, totals, months and health from
 * RlyArchiveStats, runs from RlyArchiveRuns. Shared records are read and changed in system mode only in the private
 * inner without sharing classes of those classes.
 */
public with sharing class RlyArchiveService {

    /** @description The Archive tab's API name. */
    public static final String ARCHIVE_TAB = 'RLY_Archive';
    /** @description The custom permission of approvers (product owners), who may see the Archive tab. */
    public static final String APPROVER_PERMISSION = 'RLY_Approver';
    /** @description Why someone who isn't an admin can't run the archive (board wording). */
    public static final String ADMIN_ONLY = 'Only admins can run the archive.';
    /** @description Why someone who isn't an admin can't change Retention. */
    public static final String EDIT_ADMIN_ONLY = 'Only admins can change Retention.';
    /** @description Why an action is refused outside the production hub (board wording). */
    public static final String COPY_MESSAGE = 'Release Relay settings and archiving work only in the production hub. '
        + 'Releases copied into this sandbox are never archived from here.';

    private static final String COPY_TITLE = 'This org is a sandbox copy of the hub';
    private static final Integer RUN_LIST = 500;
    private static final Integer NEXT_DAYS = 30;

    /** @description Tests set the time ("now") the archive works from. */
    @TestVisible
    private static Datetime nowForTest;

    /** @description The org's mode and the gate's title and text. */
    private class Gate {
        /** @description 'hub', 'sandbox', 'copy' or 'setup'. */
        public String mode;
        /** @description The gate's title, or null on the hub. */
        public String title;
        /** @description The gate's text, or null on the hub. */
        public String message;
    }

    /**
     * @description The time the archive works from (tests can set it).
     * @return now
     */
    public static Datetime now() {
        return nowForTest != null ? nowForTest : System.now();
    }

    /**
     * @description Whether this org is the production hub (not a sandbox, not a copy, no sandbox override).
     * @return true in the production hub
     */
    public static Boolean onHub() {
        return RlyHubGuard.isHub() && !RlyHubGuard.isSandbox();
    }

    /**
     * @description Releases finished before this moment are eligible.
     * @param days the Retention days
     * @return now minus the days
     */
    public static Datetime cutoff(Integer days) {
        return now().addDays(-days);
    }

    /**
     * @description The Retention section.
     * @return the setting, its last change and what is eligible now (only the gate outside the hub)
     */
    public static RlyArchiveViews.Retention readRetention() {
        RlyArchiveViews.Retention r = new RlyArchiveViews.Retention();
        Gate g = gate();
        r.mode = g.mode;
        r.gateTitle = g.title;
        r.gateMessage = g.message;
        if (g.mode != RlyHubGuard.MODE_HUB) {
            return r;
        }
        r.canEdit = RlyOrgController.isAdmin();
        RLY_Git_Connection__c conn = RlyArchiveSettings.read();
        r.days = RlyArchiveSettings.days(conn);
        r.nightly = RlyArchiveSettings.nightly(conn);
        if (r.days != null) {
            Datetime cut = cutoff(r.days);
            r.cutoffDate = cut.date();
            r.eligibleReleases = RlyArchiveEligible.countReleases(cut);
            r.eligibleRecords = RlyArchiveEligible.countRecords(cut, r.eligibleReleases);
        }
        if (conn != null) {
            r.changedOn = conn.Retention_Changed_On__c;
            r.changedBy = conn.Retention_Changed_By__r == null ? null : conn.Retention_Changed_By__r.Name;
            r.previousDays = conn.Retention_Previous_Days__c == null ? null : conn.Retention_Previous_Days__c.intValue();
            r.lastNightlyCall = conn.Last_Nightly_Call__c;
            r.lastNightlyResult = conn.Last_Nightly_Result__c;
        }
        return r;
    }

    /**
     * @description What a days value would make eligible, before Save. Blank, fewer than 30 days or outside the hub
     * gives no counts.
     * @param days the days typed
     * @return the preview
     */
    public static RlyArchiveViews.Preview previewRetention(Integer days) {
        RlyArchiveViews.Preview p = new RlyArchiveViews.Preview();
        p.days = days;
        RlyArchiveSettings.Choice c = new RlyArchiveSettings.Choice();
        c.days = days;
        if (days == null || RlyArchiveSettings.problem(c) != null || !onHub()) {
            return p;
        }
        Datetime cut = cutoff(days);
        p.cutoffDate = cut.date();
        p.eligibleReleases = RlyArchiveEligible.countReleases(cut);
        p.eligibleRecords = RlyArchiveEligible.countRecords(cut, p.eligibleReleases);
        return p;
    }

    /**
     * @description Saves the Retention setting (admins, production hub). Saving removes nothing.
     * @param c the days (null to keep forever, else 30 or more) and archive every night (needs days)
     * @return the Retention section after saving
     */
    public static RlyArchiveViews.Retention saveRetention(RlyArchiveSettings.Choice c) {
        requireAdmin(EDIT_ADMIN_ONLY);
        requireHub();
        String problem = RlyArchiveSettings.problem(c);
        if (problem != null) {
            throw failure(problem);
        }
        RLY_Git_Connection__c conn = RlyArchiveSettings.read();
        if (conn == null) {
            throw failure(RlyArchiveSettings.NO_SETTINGS);
        }
        RlyArchiveSettings.save(conn, c);
        return readRetention();
    }

    /**
     * @description The Archive tab: live counts, totals, the nightly job's health, the months and the runs.
     * @return the page (only the gate outside the hub, nothing more for someone who may not see it)
     */
    public static RlyArchiveViews.Archive readArchive() {
        RlyArchiveViews.Archive a = new RlyArchiveViews.Archive();
        Gate g = gate();
        a.mode = g.mode;
        a.gateTitle = g.title;
        a.gateMessage = g.message;
        Boolean admin = RlyOrgController.isAdmin();
        a.canView = admin || FeatureManagement.checkPermission(APPROVER_PERMISSION);
        if (g.mode != RlyHubGuard.MODE_HUB || !a.canView) {
            return a;
        }
        a.canRun = admin;
        RLY_Git_Connection__c conn = RlyArchiveSettings.read();
        a.days = RlyArchiveSettings.days(conn);
        a.nightly = RlyArchiveSettings.nightly(conn);
        if (a.days != null) {
            Datetime cut = cutoff(a.days);
            a.cutoffDate = cut.date();
            a.eligibleReleases = RlyArchiveEligible.countReleases(cut);
            a.eligibleRecords = RlyArchiveEligible.countRecords(cut, a.eligibleReleases);
            a.eligibleNext30 = Math.max(0, RlyArchiveEligible.countReleases(cut.addDays(NEXT_DAYS)) - a.eligibleReleases);
        }
        RlyArchiveStats.totals(a);
        a.running = RlyArchiveRuns.view(RlyArchiveRuns.running());
        for (RLY_Archive_Run__c r : RlyArchiveRuns.newest(RUN_LIST)) {
            a.runs.add(RlyArchiveRuns.view(r));
        }
        a.lastRun = a.runs.isEmpty() ? null : a.runs[0];
        a.health = RlyArchiveStats.health(conn);
        a.months = RlyArchiveStats.months();
        return a;
    }

    // The org's mode for the pages; a sandbox with the admin override still gets the copy gate.
    private static Gate gate() {
        RlyHubGuard.HubStatus s = RlyHubGuard.getHubStatus();
        Gate g = new Gate();
        g.mode = s.mode;
        g.title = s.title;
        g.message = s.message;
        if (s.mode == RlyHubGuard.MODE_COPY || (s.mode == RlyHubGuard.MODE_HUB && RlyHubGuard.isSandbox())) {
            g.mode = RlyHubGuard.MODE_COPY;
            g.title = COPY_TITLE;
            g.message = COPY_MESSAGE;
        }
        return g;
    }

    /**
     * @description Refuses the action for someone who isn't a Release Relay admin.
     * @param why the sentence the page shows
     */
    public static void requireAdmin(String why) {
        if (!RlyOrgController.isAdmin()) {
            throw failure(why);
        }
    }

    /**
     * @description Refuses the action outside the production hub.
     */
    public static void requireHub() {
        if (!onHub()) {
            throw failure(COPY_MESSAGE);
        }
    }

    /**
     * @description An error the page shows as it is.
     * @param message the sentence
     * @return the exception to throw
     */
    public static AuraHandledException failure(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
