/**
 * @description Pipeline tab status strip (build 50): reads what the strip and the section dots show, from stored records
 * only (no callouts): the Git connection, the registered orgs, the Slack settings row, the credential rows, the work
 * trackers and the last Repository security check, kept on the RLY_Run_Key__c org default row. Shared hub records:
 * read and written in system mode in the private inner class.
 */
public with sharing class RlyPipelineSummaryStore {

    /** @description Separates the names of the missing protections in Security_Problems__c (255 characters at most). */
    public static final String PROBLEM_SEPARATOR = '; ';

    /**
     * @description The hub's Git connection, with its retention fields.
     * @return the connection, or null
     */
    public static RLY_Git_Connection__c git() {
        List<RLY_Git_Connection__c> rows = new Data().readGit();
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Every registered org, with the fields the route rules and the strip read.
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> orgs() {
        return new Data().readOrgs();
    }

    /**
     * @description The Slack settings row.
     * @return the row, or null before Slack was set up
     */
    public static RLY_Notification__c slack() {
        List<RLY_Notification__c> rows = new Data().readSlack();
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Every credential row (build 49).
     * @return the rows
     */
    public static List<RLY_Credential_Status__c> credentials() {
        return new Data().readCredentials();
    }

    /**
     * @description How many work trackers are on.
     * @return the count
     */
    public static Integer activeTrackers() {
        return new Data().countTrackers();
    }

    /**
     * @description The org default row of RLY_Run_Key__c: the run-signing key and the last Repository security check.
     * @return the row (blank when none is saved)
     */
    public static RLY_Run_Key__c runKey() {
        return RLY_Run_Key__c.getOrgDefaults();
    }

    /**
     * @description Keeps the result of a Repository security check (counts and the names of what is missing) so the status
     * strip shows it without calling the provider. Called after the check's callouts; never throws.
     * @param report the check's report
     * @return true when it was kept
     */
    public static Boolean keepSecurity(RlyRepoSecurity.Report report) {
        if (report == null) {
            return false;
        }
        try {
            RLY_Run_Key__c r = RLY_Run_Key__c.getOrgDefaults();
            if (r.SetupOwnerId == null) {
                r.SetupOwnerId = UserInfo.getOrganizationId();
            }
            r.Security_Checked_On__c = report.checkedOn == null ? System.now() : report.checkedOn;
            r.Security_Missing__c = report.missing;
            r.Security_Unknown__c = report.unknown;
            List<String> names = new List<String>();
            for (RlyRepoSecurity.Item i : report.items) {
                if (i.state == RlyRepoSecurity.MISSING && String.isNotBlank(i.label)) {
                    names.add(i.label.replace(PROBLEM_SEPARATOR, ', '));
                }
            }
            r.Security_Problems__c = names.isEmpty() ? null : String.join(names, PROBLEM_SEPARATOR).left(255);
            new Data().saveRunKey(r);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description The names the stored check found missing.
     * @param r the RLY_Run_Key__c row
     * @return the names, in the check's order
     */
    public static List<String> securityProblems(RLY_Run_Key__c r) {
        List<String> out = new List<String>();
        if (r == null || String.isBlank(r.Security_Problems__c)) {
            return out;
        }
        for (String s : r.Security_Problems__c.split(PROBLEM_SEPARATOR)) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }

    /** @description The hub's settings records, in system mode. */
    private without sharing class Data {

        /**
         * @description See RlyPipelineSummaryStore.git.
         * @return the active connection first
         */
        public List<RLY_Git_Connection__c> readGit() {
            return [SELECT Id, Provider__c, Repository__c, Status__c, Status_Message__c, Last_Checked__c, Back_Promote__c,
                           Retention_Days__c, Archive_Nightly__c, Last_Nightly_Call__c, Last_Nightly_Result__c
                    FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY Active__c DESC, CreatedDate ASC LIMIT 1];
        }

        /**
         * @description See RlyPipelineSummaryStore.orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Git_Environment__c, Status__c, Source_Tracking__c,
                           My_Domain__c, Environment__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description See RlyPipelineSummaryStore.slack.
         * @return the Slack row, or none
         */
        public List<RLY_Notification__c> readSlack() {
            return [SELECT Id, Enabled__c, Bot_Token_Hint__c, Last_Sent__c, Last_Result__c
                    FROM RLY_Notification__c WHERE Channel__c = :RlySlack.CHANNEL WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
        }

        /**
         * @description See RlyPipelineSummaryStore.credentials.
         * @return the rows
         */
        public List<RLY_Credential_Status__c> readCredentials() {
            return [SELECT Id, Name, Kind__c, Expires_On__c, Days_Left__c, Status__c, Last_Checked__c
                    FROM RLY_Credential_Status__c WITH SYSTEM_MODE ORDER BY Days_Left__c ASC NULLS LAST, Name LIMIT 1000];
        }

        /**
         * @description See RlyPipelineSummaryStore.activeTrackers.
         * @return the count
         */
        public Integer countTrackers() {
            return [SELECT COUNT() FROM RLY_Work_Tracker__c WHERE Active__c = true WITH SYSTEM_MODE];
        }

        /**
         * @description Saves the RLY_Run_Key__c org default row (protected custom setting).
         * @param r the row
         */
        public void saveRunKey(RLY_Run_Key__c r) {
            upsert as system r;
        }
    }
}
