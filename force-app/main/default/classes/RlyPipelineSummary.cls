/**
 * @description Pipeline tab (build 50): the status strip's five tiles (Git, Route, Approvals &amp; Slack, Security,
 * Credentials), a status dot for each of the seven sections, what needs fixing in Security &amp; credentials, and the
 * last settings changes. One page call that reads stored records only (RlyPipelineSummaryStore, RlySettingsLog): no
 * callouts, so the tab loads fast. The Git tile's pipeline-files version comes from the page's own files check.
 */
public with sharing class RlyPipelineSummary {

    /** @description Tones of a tile, a dot or a problem. */
    public static final String TONE_OK = 'ok';
    /** @description See TONE_OK. */
    public static final String TONE_WARN = 'warn';
    /** @description See TONE_OK. */
    public static final String TONE_BAD = 'bad';
    /** @description See TONE_OK: not set up, or nothing to judge. */
    public static final String TONE_NONE = 'none';
    /** @description Section keys, as the page's list has them. */
    public static final String CONNECTION = 'connection';
    /** @description See CONNECTION. */
    public static final String ORGS = 'orgs';
    /** @description See CONNECTION. */
    public static final String APPROVALS = 'approvals';
    /** @description See CONNECTION. */
    public static final String TRACKING = 'tracking';
    /** @description See CONNECTION. */
    public static final String SECURITY = 'security';
    /** @description See CONNECTION. */
    public static final String RETENTION = 'retention';
    /** @description See CONNECTION. */
    public static final String ADVANCED = 'advanced';
    /** @description How many settings changes the page shows. */
    public static final Integer RECENT_CHANGES = 10;
    /** @description A nightly archive call older than this many days while nightly is on: the night was missed. */
    public static final Integer MISSED_NIGHT_DAYS = 2;

    private static final List<String> WORST_FIRST = new List<String>{ TONE_BAD, TONE_WARN, TONE_OK, TONE_NONE };

    /** @description What the strip, the section list and the overview show. */
    public class Summary {
        /** @description The five tiles, in order. */
        @AuraEnabled public List<Tile> tiles = new List<Tile>();
        /** @description Section key to tone (ok, warn, bad, none). */
        @AuraEnabled public Map<String, String> dots = new Map<String, String>();
        /** @description Section key to a one-line summary, for the sections the page has no other summary for. */
        @AuraEnabled public Map<String, String> notes = new Map<String, String>();
        /** @description What needs fixing in Security &amp; credentials, worst first. */
        @AuraEnabled public List<Problem> problems = new List<Problem>();
        /** @description The last settings changes, newest first. */
        @AuraEnabled public List<Change> changes = new List<Change>();
        /** @description How many orgs are registered. */
        @AuraEnabled public Integer orgCount = 0;
        /** @description This org is the hub. */
        @AuraEnabled public Boolean isHub = false;
    }

    /** @description One status tile. */
    public class Tile {
        /** @description git, route, approvals, security or credentials. */
        @AuraEnabled public String key;
        /** @description The tile's heading. */
        @AuraEnabled public String label;
        /** @description The main line. */
        @AuraEnabled public String value;
        /** @description The grey line under it. */
        @AuraEnabled public String detail;
        /** @description ok, warn, bad or none. */
        @AuraEnabled public String tone = TONE_NONE;
        /** @description The section the tile opens. */
        @AuraEnabled public String section;
        /** @description When it was last checked, if the tile has a check. */
        @AuraEnabled public Datetime checkedOn;
    }

    /** @description Something to fix in Security &amp; credentials. */
    public class Problem {
        /** @description The tag before it: Fix, Off, 25 days, Expired… */
        @AuraEnabled public String tag;
        /** @description ok, warn or bad. */
        @AuraEnabled public String tone;
        /** @description What it is. */
        @AuraEnabled public String text;
        /** @description When it expires, for a credential. */
        @AuraEnabled public Date expiresOn;
    }

    /** @description One settings change. */
    public class Change {
        /** @description The Pipeline tab section. */
        @AuraEnabled public String section;
        /** @description What changed. */
        @AuraEnabled public String what;
        /** @description The value before (blank when none or a secret). */
        @AuraEnabled public String oldValue;
        /** @description The value after. */
        @AuraEnabled public String newValue;
        /** @description Who saved it. */
        @AuraEnabled public String who;
        /** @description When. */
        @AuraEnabled public Datetime changedOn;
    }

    /**
     * @description The strip, the dots, the problems and the recent changes. Stored records only, no callouts.
     * @return the summary
     */
    @AuraEnabled
    public static Summary summary() {
        try {
            return build();
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Pipeline status: ' + e.getMessage());
            ex.setMessage('Pipeline status: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description See summary.
     * @return the summary
     */
    public static Summary build() {
        Summary s = new Summary();
        s.isHub = RlyHubGuard.isHub();
        RLY_Git_Connection__c conn = RlyPipelineSummaryStore.git();
        List<RLY_Org__c> orgRows = RlyPipelineSummaryStore.orgs();
        s.orgCount = orgRows.size();
        Tile gitTile = RlyPipelineSummaryTiles.git(conn);
        Tile routeTile = RlyPipelineSummaryTiles.route(orgRows);
        s.tiles.add(gitTile);
        s.tiles.add(routeTile);
        s.tiles.add(RlyPipelineSummaryTiles.approvals(RlyPipelineSummaryStore.slack()));
        RLY_Run_Key__c key = RlyPipelineSummaryStore.runKey();
        Tile securityTile = RlyPipelineSummaryChecks.security(key, s.problems);
        Tile credTile = RlyPipelineSummaryChecks.credentials(RlyPipelineSummaryStore.credentials(), s.problems);
        s.tiles.add(securityTile);
        s.tiles.add(credTile);
        s.dots.put(CONNECTION, worst(gitTile.tone, routeTile.tone));
        s.dots.put(ORGS, RlyPipelineSummaryChecks.orgsTone(orgRows));
        s.dots.put(APPROVALS, s.tiles[2].tone);
        s.dots.put(SECURITY, worst(worst(securityTile.tone, credTile.tone), String.isBlank(key.Key__c) ? TONE_WARN : TONE_OK));
        s.dots.put(ADVANCED, TONE_NONE);
        addTracking(s);
        addRetention(s, conn);
        for (RLY_Settings_Change__c c : RlySettingsLog.recent(RECENT_CHANGES)) {
            s.changes.add(change(c));
        }
        return s;
    }

    /**
     * @description The worse of two tones (bad, warn, ok, then none).
     * @param a a tone
     * @param b a tone
     * @return the worse one
     */
    public static String worst(String a, String b) {
        Integer ia = WORST_FIRST.indexOf(a);
        Integer ib = WORST_FIRST.indexOf(b);
        ia = ia < 0 ? WORST_FIRST.size() : ia;
        ib = ib < 0 ? WORST_FIRST.size() : ib;
        return ia <= ib ? a : b;
    }

    private static void addTracking(Summary s) {
        Integer active = RlyPipelineSummaryStore.activeTrackers();
        Boolean required = RLY_Work_Tracking__c.getOrgDefaults().Required__c == true;
        if (active > 0) {
            s.dots.put(TRACKING, TONE_OK);
            s.notes.put(TRACKING, active + (active == 1 ? ' tracker on' : ' trackers on') + (required ? ' · tickets required' : ''));
        } else {
            s.dots.put(TRACKING, required ? TONE_WARN : TONE_NONE);
            s.notes.put(TRACKING, required ? 'Tickets required but no tracker is on' : 'No tracker yet');
        }
    }

    private static void addRetention(Summary s, RLY_Git_Connection__c conn) {
        Integer days = conn == null || conn.Retention_Days__c == null ? null : conn.Retention_Days__c.intValue();
        if (!s.isHub || days == null) {
            s.dots.put(RETENTION, TONE_NONE);
            s.notes.put(RETENTION, s.isHub ? 'No retention days set: finished releases are kept' : 'Set in the production hub');
            return;
        }
        Boolean nightly = conn.Archive_Nightly__c == true;
        Boolean missed = nightly && (conn.Last_Nightly_Call__c == null
            || conn.Last_Nightly_Call__c < System.now().addDays(-MISSED_NIGHT_DAYS));
        s.dots.put(RETENTION, missed ? TONE_WARN : TONE_OK);
        s.notes.put(RETENTION, 'Keep ' + days + ' days · ' + (nightly ? (missed ? 'nightly archive missed' : 'archive every night') : 'archive by hand'));
    }

    private static Change change(RLY_Settings_Change__c c) {
        Change out = new Change();
        out.section = c.Section__c;
        out.what = c.What__c;
        out.oldValue = c.Old_Value__c;
        out.newValue = c.New_Value__c;
        out.who = c.Changed_By__c;
        out.changedOn = c.CreatedDate;
        return out;
    }
}
