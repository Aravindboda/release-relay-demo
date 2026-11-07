/**
 * @description The Retention setting on the hub's settings record (the one RLY_Git_Connection__c, beside Back_Promote__c):
 * Retention_Days__c (blank keeps finished releases forever, else 30 or more), Archive_Nightly__c, the last change (who,
 * when, the days before) and the last call of the archive endpoint (Last_Nightly_Call__c and Last_Nightly_Result__c,
 * stamped by every call). The settings record is a shared hub record: read and changed in system mode in the private
 * inner without sharing class, only after RlyArchiveService has checked the caller.
 */
public with sharing class RlyArchiveSettings {

    /** @description The fewest days that can be set. */
    public static final Integer MIN_DAYS = 30;
    /** @description The most days Retention_Days__c holds (Number 5,0). */
    public static final Integer MAX_DAYS = 99999;
    /** @description Why fewer days are refused (board wording). */
    public static final String TOO_FEW = 'Use 30 days or more.';
    /** @description Why nightly is refused without days (board wording). */
    public static final String NEEDS_DAYS = 'Set the number of days first.';
    /** @description Why more days than the field holds are refused. */
    public static final String TOO_MANY = 'Use 99,999 days or fewer.';
    /** @description Why nothing can be saved before Git is connected. */
    public static final String NO_SETTINGS = 'Connect Git on the Pipeline tab first: Retention is saved with the Git connection.';

    /**
     * @description The hub's settings record with its Retention fields.
     * @return the record, or null before Git is connected
     */
    public static RLY_Git_Connection__c read() {
        return new Data().settings();
    }

    /**
     * @description The Retention days saved on the record.
     * @param conn the settings record, or null
     * @return the days, or null to keep forever
     */
    public static Integer days(RLY_Git_Connection__c conn) {
        return conn == null || conn.Retention_Days__c == null ? null : conn.Retention_Days__c.intValue();
    }

    /**
     * @description Whether archive every night is on (and has days to work with).
     * @param conn the settings record, or null
     * @return true when nightly is on
     */
    public static Boolean nightly(RLY_Git_Connection__c conn) {
        return conn != null && conn.Archive_Nightly__c == true;
    }

    /** @description A Retention setting to save: the days and archive every night. */
    public class Choice {
        /** @description The days, or null to keep forever. */
        public Integer days;
        /** @description Archive every night. */
        public Boolean nightly = false;
    }

    /**
     * @description Why a setting can't be saved.
     * @param c the setting
     * @return the sentence, or null when it can be saved
     */
    public static String problem(Choice c) {
        if (c.days != null && c.days < MIN_DAYS) {
            return TOO_FEW;
        }
        if (c.days != null && c.days > MAX_DAYS) {
            return TOO_MANY;
        }
        return c.nightly == true && c.days == null ? NEEDS_DAYS : null;
    }

    /**
     * @description Saves the Retention setting; a change records who and when, and a change of days the days before.
     * @param conn the settings record
     * @param c the setting
     */
    public static void save(RLY_Git_Connection__c conn, Choice c) {
        Boolean nightlyOn = c.nightly == true;
        RLY_Git_Connection__c row = new RLY_Git_Connection__c(Id = conn.Id, Retention_Days__c = c.days, Archive_Nightly__c = nightlyOn,
            Retention_Previous_Days__c = conn.Retention_Previous_Days__c);
        Boolean daysChanged = c.days != days(conn);
        if (daysChanged || nightlyOn != nightly(conn)) {
            row.Retention_Changed_On__c = RlyArchiveService.now();
            row.Retention_Changed_By__c = UserInfo.getUserId();
        }
        if (daysChanged) {
            row.Retention_Previous_Days__c = days(conn);
        }
        new Data().write(row);
    }

    /**
     * @description Stamps a call of the archive endpoint (skipped calls included).
     * @param conn the settings record, or null (nothing is stamped)
     * @param result what the call did, for example "Skipped: nightly is off"
     */
    public static void stampCall(RLY_Git_Connection__c conn, String result) {
        if (conn == null) {
            return;
        }
        new Data().write(new RLY_Git_Connection__c(Id = conn.Id, Last_Nightly_Call__c = RlyArchiveService.now(),
            Last_Nightly_Result__c = result == null ? null : result.left(255)));
    }

    /** @description The settings record is a shared hub record: read and written in system mode. */
    private without sharing class Data {

        /**
         * @description The hub's settings record (the oldest Git connection).
         * @return the record, or null
         */
        public RLY_Git_Connection__c settings() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Retention_Days__c, Archive_Nightly__c, Retention_Changed_On__c,
                                                    Retention_Changed_By__c, Retention_Changed_By__r.Name, Retention_Previous_Days__c,
                                                    Last_Nightly_Call__c, Last_Nightly_Result__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Saves fields of the settings record.
         * @param row the record with the fields to save
         */
        public void write(RLY_Git_Connection__c row) {
            Database.update(row, true, AccessLevel.SYSTEM_MODE);
        }
    }
}
