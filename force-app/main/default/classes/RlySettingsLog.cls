/**
 * @description Settings changes (build 50): a small log of what admins change on the Pipeline tab, for its Recent changes
 * to settings list. A save path reads the area before it saves (read) and compares after its save (compare); each setting
 * that differs becomes one RLY_Settings_Change__c row: section, what, old and new value, who and when. Secrets (tokens,
 * the signing secret, the run-signing key, the lock password) are never written: they show as set, changed or removed.
 * Logging never stops a save: a failed read or write is skipped. Rows are kept 90 days; the nightly archive call removes
 * older ones (purge). Shared hub records: written and read in system mode in the private inner class.
 */
public with sharing class RlySettingsLog {

    /** @description Area: the Git connection (Connection &amp; route). */
    public static final String GIT = 'git';
    /** @description Area: the registered orgs and the route order. */
    public static final String ORGS = 'orgs';
    /** @description Area: the Slack connection. */
    public static final String SLACK = 'slack';
    /** @description Area: work tracking settings and trackers. */
    public static final String TRACKING = 'tracking';
    /** @description Area: retention days and the nightly archive switch. */
    public static final String RETENTION = 'retention';
    /** @description Area: the run-signing key. */
    public static final String SECURITY = 'security';
    /** @description Area: production approval needing the add-on. */
    public static final String APPROVAL = 'approval';
    /** @description Area: the What's built lock. */
    public static final String LOCK = 'lock';
    /** @description Section names, as the Pipeline tab's list shows them. */
    public static final String SECTION_CONNECTION = 'Connection & route';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_ORGS = 'Orgs';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_APPROVALS = 'Approvals & Slack';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_TRACKING = 'Work tracking';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_SECURITY = 'Security & credentials';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_RETENTION = 'Retention & archive';
    /** @description See SECTION_CONNECTION. */
    public static final String SECTION_ADVANCED = 'Advanced';
    /** @description How long rows are kept. */
    public static final Integer KEEP_DAYS = 90;
    /** @description Most rows one save writes. */
    public static final Integer MOST_PER_SAVE = 25;

    private static final Map<String, String> GIT_FIELDS = new Map<String, String>{
        'Provider__c' => 'Provider', 'Repository__c' => 'Repository', 'Named_Credential__c' => 'Named Credential',
        'Pipeline__c' => 'Workflow file', 'Pipeline_Branch__c' => 'Pipeline branch', 'Source_Path__c' => 'Source path',
        'Code_Scan__c' => 'Code scan', 'Back_Promote__c' => 'Back promote'
    };
    private static final Map<String, String> RETENTION_FIELDS = new Map<String, String>{
        'Retention_Days__c' => 'Keep finished releases (days)', 'Archive_Nightly__c' => 'Archive every night'
    };
    private static final Map<String, String> ORG_FIELDS = new Map<String, String>{
        'Role__c' => 'Role', 'Environment__c' => 'Salesforce environment', 'My_Domain__c' => 'My Domain URL',
        'Login_Type__c' => 'Login type', 'Username__c' => 'Integration username', 'Certificate__c' => 'Hub certificate',
        'Branch__c' => 'Branch', 'Git_Environment__c' => 'Git environment', 'Approval_Rule__c' => 'Approval rule',
        'Approval_Types__c' => 'Approval kinds', 'Code_Scan__c' => 'Code scan', 'Approve_In_Salesforce__c' => 'Approve in Salesforce',
        'Approve_In_Slack__c' => 'Approve in Slack', 'Require_Git_Review__c' => 'Git reviewers', 'Hotfix_Two_Approvers__c' => 'Hotfix two approvers',
        'Back_Promote_When__c' => 'Back promote when', 'Back_Promote_Approval__c' => 'Approve before syncing',
        'Slack_Channel__c' => 'Slack channel', 'Slack_Post__c' => 'Post to Slack', 'Slack_Reminders__c' => 'Slack reminders',
        'Slack_Digest__c' => 'Slack daily digest', 'Window_Days__c' => 'Release window days', 'Window_From__c' => 'Release window from',
        'Window_To__c' => 'Release window to', 'Window_Time_Zone__c' => 'Release window time zone'
    };
    private static final Map<String, String> SLACK_FIELDS = new Map<String, String>{
        'Enabled__c' => 'Slack', 'Events__c' => 'Slack messages', 'Slack_Match_By__c' => 'Match approvers by'
    };
    private static final Map<String, String> SLACK_SECRETS = new Map<String, String>{
        'Bot_Token_Hint__c' => 'Slack bot token', 'Signing_Secret__c' => 'Slack signing secret'
    };
    private static final Map<String, String> TRACKING_FIELDS = new Map<String, String>{
        'Required__c' => 'Tickets required', 'Require_Change__c' => 'Require an approved change', 'Change_Pattern__c' => 'Change format',
        'Tracker__c' => 'Tracker', 'Ticket_Pattern__c' => 'Ticket format', 'Link_Pattern__c' => 'Link',
        'Named_Credential__c' => 'Named Credential', 'Post_Updates__c' => 'Post updates', 'ServiceNow_Table__c' => 'ServiceNow table'
    };
    private static final Map<String, String> TRACKER_FIELDS = new Map<String, String>{
        'Type__c' => 'Type', 'Active__c' => 'On', 'Ticket_Pattern__c' => 'Ticket format', 'Link_Pattern__c' => 'Link',
        'Named_Credential__c' => 'Named Credential', 'Post_Updates__c' => 'Post updates', 'ServiceNow_Table__c' => 'ServiceNow table',
        'Change_Mentions_Release__c' => 'Change mentions the release', 'State_Map__c' => 'State map'
    };

    /** @description What an area held when it was read: one value per setting, keyed by record and field. */
    public class Snapshot {
        /** @description The area read. */
        public String area;
        /** @description Each setting by key (subject|field), or null when the read failed (nothing is logged then). */
        public Map<String, Item> items;
    }

    /** @description One setting as the log shows it. */
    public class Item {
        /** @description The record it belongs to (its Id, or the area). */
        public String subject;
        /** @description The Pipeline tab section. */
        public String section;
        /** @description What it is, for example Named Credential or SIT · Branch. */
        public String what;
        /** @description A secret: only set, changed or removed is written. */
        public Boolean secret = false;
        /** @description The record itself (its name): an added, removed or renamed record. */
        public Boolean marker = false;
        /** @description The value as text (On or Off for switches), or null when empty. */
        public String value;
    }

    /** @description How one kind of record is read: its section, subject and the label before each field. */
    public class Spec {
        /** @description The Pipeline tab section. */
        public String section;
        /** @description The subject, or null for each record's Id. */
        public String subject;
        /** @description Put before each field's label, for example the org's name. */
        public String prefix = '';
        /** @description Field API name to label. */
        public Map<String, String> fields;
        /** @description The fields are secrets. */
        public Boolean secret = false;
    }

    /**
     * @description Reads an area before a save. Never throws.
     * @param area GIT, ORGS, SLACK, TRACKING, RETENTION, SECURITY, APPROVAL or LOCK
     * @return the snapshot to pass to compare after the save
     */
    public static Snapshot read(String area) {
        Snapshot s = new Snapshot();
        s.area = area;
        try {
            s.items = new Map<String, Item>();
            readArea(s);
        } catch (Exception e) {
            s.items = null;
        }
        return s;
    }

    /**
     * @description Reads the area again after the save and logs what differs (nothing when that read fails). Call it after
     * the save path's last callout: it saves. Never throws.
     * @param was the snapshot from read
     * @return how many rows were written
     */
    public static Integer compare(Snapshot was) {
        if (was == null || was.items == null) {
            return 0;
        }
        try {
            Snapshot now = read(was.area);
            List<RLY_Settings_Change__c> rows = RlySettingsLogDiff.rows(was.items, now.items);
            if (!rows.isEmpty()) {
                new Data().insertRows(rows);
            }
            return rows.size();
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * @description The newest changes, newest first.
     * @param howMany how many (1 to 50)
     * @return the rows
     */
    public static List<RLY_Settings_Change__c> recent(Integer howMany) {
        Integer n = howMany == null ? 10 : Math.max(1, Math.min(50, howMany));
        return new Data().readRecent(n);
    }

    /**
     * @description Removes rows older than KEEP_DAYS (the nightly archive call; admins only). Never throws.
     * @return how many were removed
     */
    public static Integer purge() {
        try {
            if (!RlyOrgController.isAdmin()) {
                return 0;
            }
            return new Data().deleteOlder(System.now().addDays(-KEEP_DAYS));
        } catch (Exception e) {
            return 0;
        }
    }

    private static void readArea(Snapshot s) {
        String area = s.area;
        if (area == GIT || area == RETENTION) {
            List<RLY_Git_Connection__c> rows = new Data().readGit();
            if (!rows.isEmpty()) {
                addRecord(rows[0], spec(area == GIT ? SECTION_CONNECTION : SECTION_RETENTION, area, area == GIT ? GIT_FIELDS : RETENTION_FIELDS), s);
            }
        } else if (area == ORGS) {
            RlySettingsLogDiff.orgsInto(new Data().readOrgs(), spec(SECTION_ORGS, null, ORG_FIELDS), s);
        } else if (area == SLACK) {
            readSlack(s);
        } else if (area == TRACKING) {
            addRecord(RLY_Work_Tracking__c.getOrgDefaults(), spec(SECTION_TRACKING, TRACKING, TRACKING_FIELDS), s);
            RlySettingsLogDiff.trackersInto(new Data().readTrackers(), spec(SECTION_TRACKING, null, TRACKER_FIELDS), s);
        } else {
            readSettings(s);
        }
    }

    private static void readSlack(Snapshot s) {
        List<RLY_Notification__c> rows = new Data().readSlack();
        if (rows.isEmpty()) {
            return;
        }
        addRecord(rows[0], spec(SECTION_APPROVALS, SLACK, SLACK_FIELDS), s);
        addRecord(rows[0], secret(spec(SECTION_APPROVALS, SLACK, SLACK_SECRETS)), s);
    }

    private static void readSettings(Snapshot s) {
        if (s.area == SECURITY) {
            addRecord(RLY_Run_Key__c.getOrgDefaults(),
                secret(spec(SECTION_SECURITY, SECURITY, new Map<String, String>{ 'Key__c' => 'Run-signing key' })), s);
        } else if (s.area == APPROVAL) {
            addRecord(RLY_Approval_Setting__c.getOrgDefaults(),
                spec(SECTION_APPROVALS, APPROVAL, new Map<String, String>{ 'Prod_Needs_Addon__c' => 'Production approval needs the add-on' }), s);
        } else if (s.area == LOCK) {
            RLY_Lock__c lockRow = RLY_Lock__c.getOrgDefaults();
            addRecord(lockRow, spec(SECTION_ADVANCED, LOCK, new Map<String, String>{ 'Enabled__c' => 'What\'s built lock' }), s);
            addRecord(lockRow, secret(spec(SECTION_ADVANCED, LOCK, new Map<String, String>{ 'Hash__c' => 'What\'s built lock password' })), s);
        }
    }

    private static Spec secret(Spec sp) {
        sp.secret = true;
        return sp;
    }

    /**
     * @description Adds a record's settings to a snapshot: one value and one item per field.
     * @param rec the record
     * @param sp how to read it
     * @param target the snapshot
     */
    public static void addRecord(SObject rec, Spec sp, Snapshot target) {
        String subject = sp.subject == null ? String.valueOf(rec.get('Id')) : sp.subject;
        for (String field : sp.fields.keySet()) {
            Item i = new Item();
            i.subject = subject;
            i.section = sp.section;
            i.what = sp.prefix + sp.fields.get(field);
            i.secret = sp.secret;
            i.value = text(rec.get(field));
            target.items.put(subject + '|' + field, i);
        }
    }

    /**
     * @description A value as the log shows it: null when empty, On or Off for a switch, whole numbers without decimals,
     * a multi-select as a comma list.
     * @param v the field value
     * @return the text, or null
     */
    public static String text(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Boolean) {
            return (Boolean) v ? 'On' : 'Off';
        }
        if (v instanceof Decimal) {
            return ((Decimal) v).stripTrailingZeros().toPlainString();
        }
        String s = String.valueOf(v).trim();
        return String.isBlank(s) ? null : s.replace(';', ', ');
    }

    /**
     * @description How to read records of one kind.
     * @param section the Pipeline tab section
     * @param subject the subject (null: each record's Id)
     * @param fields field API name to label
     * @return the spec
     */
    public static Spec spec(String section, String subject, Map<String, String> fields) {
        Spec s = new Spec();
        s.section = section;
        s.subject = subject;
        s.fields = fields;
        return s;
    }

    /**
     * @description A copy of a spec with a label prefix (for example the org's name) for one record.
     * @param sp the spec
     * @param prefix the prefix
     * @return the copy
     */
    public static Spec withPrefix(Spec sp, String prefix) {
        Spec c = spec(sp.section, sp.subject, sp.fields);
        c.secret = sp.secret;
        c.prefix = prefix;
        return c;
    }

    /** @description Settings records and log rows, in system mode. */
    private without sharing class Data {

        /**
         * @description The Git connection's settings.
         * @return the active connection first
         */
        public List<RLY_Git_Connection__c> readGit() {
            return [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c, Source_Path__c,
                           Code_Scan__c, Back_Promote__c, Retention_Days__c, Archive_Nightly__c
                    FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY Active__c DESC, CreatedDate ASC LIMIT 1];
        }

        /**
         * @description The registered orgs' settings (never the consumer key).
         * @return the orgs
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, Environment__c, My_Domain__c, Login_Type__c, Username__c, Certificate__c, Branch__c,
                           Git_Environment__c, Stage_Order__c, Approval_Rule__c, Approval_Types__c, Code_Scan__c, Approve_In_Salesforce__c,
                           Approve_In_Slack__c, Require_Git_Review__c, Hotfix_Two_Approvers__c, Back_Promote_When__c,
                           Back_Promote_Approval__c, Slack_Channel__c, Slack_Post__c, Slack_Reminders__c, Slack_Digest__c,
                           Window_Days__c, Window_From__c, Window_To__c, Window_Time_Zone__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description The Slack settings row.
         * @return the row, or none
         */
        public List<RLY_Notification__c> readSlack() {
            return [SELECT Id, Enabled__c, Events__c, Slack_Match_By__c, Bot_Token_Hint__c, Signing_Secret__c
                    FROM RLY_Notification__c WHERE Channel__c = :RlySlack.CHANNEL WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
        }

        /**
         * @description The work trackers, in routing order.
         * @return the trackers
         */
        public List<RLY_Work_Tracker__c> readTrackers() {
            return [SELECT Id, Name, Type__c, Active__c, Sort_Order__c, Ticket_Pattern__c, Link_Pattern__c, Named_Credential__c,
                           Post_Updates__c, ServiceNow_Table__c, Change_Mentions_Release__c, State_Map__c
                    FROM RLY_Work_Tracker__c WITH SYSTEM_MODE ORDER BY Sort_Order__c ASC NULLS LAST, Name LIMIT 200];
        }

        /**
         * @description The newest rows.
         * @param n how many
         * @return the rows, newest first
         */
        public List<RLY_Settings_Change__c> readRecent(Integer n) {
            return [SELECT Id, Section__c, What__c, Old_Value__c, New_Value__c, Changed_By__c, CreatedDate
                    FROM RLY_Settings_Change__c WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Name DESC LIMIT :n];
        }

        /**
         * @description Writes rows.
         * @param rows the rows
         */
        public void insertRows(List<RLY_Settings_Change__c> rows) {
            insert as system rows;
        }

        /**
         * @description Removes rows made before a moment.
         * @param cutoff the moment
         * @return how many were removed
         */
        public Integer deleteOlder(Datetime cutoff) {
            List<RLY_Settings_Change__c> rows = [SELECT Id FROM RLY_Settings_Change__c WHERE CreatedDate < :cutoff
                                                 WITH SYSTEM_MODE LIMIT 5000];
            if (!rows.isEmpty()) {
                delete as system rows;
            }
            return rows.size();
        }
    }
}
