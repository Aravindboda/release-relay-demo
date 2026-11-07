/**
 * @description Reads and saves for Slack reminders, the daily digest, mentions and hotfix alerts (RlySlackDue,
 * RlySlackAlert, RlySlackReminderController). Every read is in system mode: the hourly call runs as the pipeline's hub
 * user, and Slack mentions need users and permission set assignments that a viewer can't read. Saves touch only the
 * reminder fields (Slack_Reminded__c, Slack_Digest_Sent__c and an admin's per-org Slack settings).
 */
public with sharing class RlySlackDueStore {

    /** @description Release status a reminder nudges approvers for. */
    public static final String READY = 'Ready for approval';
    /** @description Release status whose open manual steps nudge the deploy team. */
    public static final String DEPLOYED = 'Deployed';
    /** @description Most mentions in one message. */
    public static final Integer MAX_MENTIONS = 5;

    /**
     * @description The orgs with a Slack channel and reminders or the digest on.
     * @return the orgs, with their Slack settings
     */
    public static List<RLY_Org__c> dueOrgs() {
        return new SystemAccess().dueOrgs();
    }

    /**
     * @description One org's Slack settings.
     * @param orgId the org
     * @return the org, or null
     */
    public static RLY_Org__c org(Id orgId) {
        List<RLY_Org__c> rows = orgId == null ? new List<RLY_Org__c>() : new SystemAccess().orgs(new Set<Id>{ orgId });
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Releases into these orgs that wait: for approval, or deployed with manual steps still to do there.
     * @param orgIds the orgs
     * @return the releases
     */
    public static List<RLY_Release__c> waiting(Set<Id> orgIds) {
        return orgIds.isEmpty() ? new List<RLY_Release__c>() : new SystemAccess().waiting(orgIds);
    }

    /**
     * @description When each release last moved (its latest history event), so a reminder counts the waiting time.
     * @param releaseIds the releases
     * @return release Id to its latest event's time
     */
    public static Map<Id, Datetime> lastMoved(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new Map<Id, Datetime>() : new SystemAccess().lastMoved(releaseIds);
    }

    /**
     * @description How many manual steps are still to do per release, in the release's target org.
     * @param releaseIds the releases
     * @return release Id to the count
     */
    public static Map<Id, Integer> stepsToDo(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new Map<Id, Integer>() : new SystemAccess().stepsToDo(releaseIds);
    }

    /**
     * @description Saves when releases were last nudged.
     * @param reminded release Id to the moment
     */
    public static void markReminded(Map<Id, Datetime> reminded) {
        List<RLY_Release__c> rows = new List<RLY_Release__c>();
        for (Id relId : reminded.keySet()) {
            rows.add(new RLY_Release__c(Id = relId, Slack_Reminded__c = reminded.get(relId)));
        }
        new SystemAccess().updateRows(rows);
    }

    /**
     * @description Saves the day orgs' digests went out.
     * @param orgIds the orgs
     * @param day the day
     */
    public static void markDigest(Set<Id> orgIds, Date day) {
        List<RLY_Org__c> rows = new List<RLY_Org__c>();
        for (Id orgId : orgIds) {
            rows.add(new RLY_Org__c(Id = orgId, Slack_Digest_Sent__c = day));
        }
        new SystemAccess().updateRows(rows);
    }

    /**
     * @description Saves an org's Slack reminder settings (the caller checked the admin).
     * @param row the org with the settings to save
     */
    public static void saveSettings(RLY_Org__c row) {
        new SystemAccess().updateRows(new List<RLY_Org__c>{ row });
    }

    /** @description Reads and saves in system mode (see the class description). */
    private without sharing class SystemAccess {

        /**
         * @description Orgs with a channel and reminders or the digest on.
         * @return the orgs
         */
        public List<RLY_Org__c> dueOrgs() {
            return [SELECT Id, Name, Slack_Channel__c, Slack_Post__c, Slack_Reminders__c, Slack_Reminder_Hours__c,
                           Slack_Digest__c, Slack_Digest_Hour__c, Slack_Digest_Sent__c, Slack_Mentions__c, Slack_Hotfix_Alerts__c
                    FROM RLY_Org__c WHERE Slack_Channel__c != null AND (Slack_Reminders__c = true OR Slack_Digest__c = true)
                    WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Orgs by Id with their Slack settings.
         * @param orgIds the orgs
         * @return the orgs
         */
        public List<RLY_Org__c> orgs(Set<Id> orgIds) {
            return [SELECT Id, Name, Role__c, Slack_Channel__c, Slack_Post__c, Slack_Reminders__c, Slack_Reminder_Hours__c,
                           Slack_Digest__c, Slack_Digest_Hour__c, Slack_Digest_Sent__c, Slack_Mentions__c, Slack_Hotfix_Alerts__c
                    FROM RLY_Org__c WHERE Id IN :orgIds WITH SYSTEM_MODE];
        }

        /**
         * @description Releases waiting for approval or deployed, into the orgs.
         * @param orgIds the orgs
         * @return the releases
         */
        public List<RLY_Release__c> waiting(Set<Id> orgIds) {
            return [SELECT Id, Name, Title__c, Status__c, Target_Org__c, Target_Org__r.Name, Slack_Ts__c, Slack_Channel_Id__c,
                           Slack_Reminded__c, CreatedDate, CreatedById, Is_Hotfix__c
                    FROM RLY_Release__c WHERE Target_Org__c IN :orgIds AND Status__c IN (:READY, :DEPLOYED)
                    WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 500];
        }

        /**
         * @description The latest history event per release.
         * @param releaseIds the releases
         * @return release Id to the time
         */
        public Map<Id, Datetime> lastMoved(Set<Id> releaseIds) {
            Map<Id, Datetime> out = new Map<Id, Datetime>();
            for (AggregateResult r : [SELECT Release__c rel, MAX(Occurred_On__c) moved FROM RLY_Release_Event__c
                                      WHERE Release__c IN :releaseIds AND Event_Type__c NOT IN ('Comment', 'File_Downloaded')
                                      WITH SYSTEM_MODE GROUP BY Release__c LIMIT 2000]) {
                out.put((Id) r.get('rel'), (Datetime) r.get('moved'));
            }
            return out;
        }

        /**
         * @description Manual steps to do per release, in its target org.
         * @param releaseIds the releases
         * @return release Id to the count
         */
        public Map<Id, Integer> stepsToDo(Set<Id> releaseIds) {
            Map<Id, Integer> out = new Map<Id, Integer>();
            Set<Id> targets = targetsOf(releaseIds);
            for (AggregateResult r : [SELECT Release__c rel, COUNT(Id) stepCount FROM RLY_Manual_Step_Run__c
                                      WHERE Release__c IN :releaseIds AND Status__c = 'To_Do' AND Org__c IN :targets
                                      WITH SYSTEM_MODE GROUP BY Release__c LIMIT 2000]) {
                out.put((Id) r.get('rel'), (Integer) r.get('stepCount'));
            }
            return out;
        }

        private Set<Id> targetsOf(Set<Id> releaseIds) {
            Set<Id> out = new Set<Id>();
            for (RLY_Release__c r : [SELECT Target_Org__c FROM RLY_Release__c WHERE Id IN :releaseIds WITH SYSTEM_MODE LIMIT 2000]) {
                out.add(r.Target_Org__c);
            }
            return out;
        }

        /**
         * @description Updates rows in system mode.
         * @param rows the rows
         */
        public void updateRows(List<SObject> rows) {
            if (!rows.isEmpty()) {
                Database.update(rows, true, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
