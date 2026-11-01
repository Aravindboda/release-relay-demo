/**
 * @description Pipeline tab, first-run setup ("Set up Release Relay"): how far setup has come, read from what is
 * saved (the hub's org record, the Git connection and its last check, the registered orgs, the Slack record and its
 * last result). No callouts: the checks themselves run from the setup steps (checkOrg, checkGit, testSlack).
 */
public with sharing class RlySetupStatus {

    private static final String ROLE_OF_HUB = 'Hub';
    private static final String GIT_CONNECTED = 'Connected';
    private static final String FILES_FOUND = 'Pipeline files found';
    private static final String SLACK_SENT = 'Sent';

    /** @description What the setup steps show. */
    public class SetupStatus {
        /** @description An org with Role__c Hub is registered (step 1). */
        @AuraEnabled public Boolean hubRegistered = false;
        /** @description A Git connection is saved (step 2). */
        @AuraEnabled public Boolean gitSaved = false;
        /** @description Its last check passed. */
        @AuraEnabled public Boolean gitConnected = false;
        /** @description Its last check found the pipeline files on the pipeline branch (step 3). */
        @AuraEnabled public Boolean pipelineFilesFound = false;
        /** @description Registered orgs other than the hub (step 4). */
        @AuraEnabled public Integer orgCount = 0;
        /** @description Slack is on and its last message or test was sent (step 5, optional). */
        @AuraEnabled public Boolean slackConnected = false;
        /** @description Setup is shown: no hub org or no Git connection yet. */
        @AuraEnabled public Boolean needsSetup = true;
    }

    /**
     * @description How far setup has come, from saved data only.
     * @return the status
     */
    @AuraEnabled
    public static SetupStatus getSetupStatus() {
        Data data = new Data();
        SetupStatus s = new SetupStatus();
        s.hubRegistered = data.hubCount() > 0;
        RLY_Git_Connection__c git = data.git();
        s.gitSaved = git != null;
        s.gitConnected = git != null && git.Status__c == GIT_CONNECTED;
        s.pipelineFilesFound = s.gitConnected && git.Status_Message__c != null && git.Status_Message__c.contains(FILES_FOUND);
        s.orgCount = data.otherOrgCount();
        RLY_Notification__c slack = RlySlack.settings();
        s.slackConnected = slack != null && slack.Enabled__c && slack.Last_Result__c != null
            && slack.Last_Result__c.startsWith(SLACK_SENT);
        s.needsSetup = !s.hubRegistered || !s.gitSaved;
        return s;
    }

    /** @description The org records and the Git connection are shared hub records: read in system mode. */
    private without sharing class Data {

        /**
         * @description How many orgs are registered as the hub.
         * @return the count
         */
        public Integer hubCount() {
            return [SELECT COUNT() FROM RLY_Org__c WHERE Role__c = :ROLE_OF_HUB WITH SYSTEM_MODE];
        }

        /**
         * @description How many other orgs are registered.
         * @return the count
         */
        public Integer otherOrgCount() {
            return [SELECT COUNT() FROM RLY_Org__c WHERE Role__c != :ROLE_OF_HUB WITH SYSTEM_MODE];
        }

        /**
         * @description The Git connection with its last check.
         * @return the connection, or null when none is saved
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Status__c, Status_Message__c FROM RLY_Git_Connection__c
                                                WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
