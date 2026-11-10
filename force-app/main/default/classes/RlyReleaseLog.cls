/**
 * @description A release's history (RLY_Release_Event__c): every transition adds an event here, and the events are saved
 * with the transaction's own saves (flush), after its callouts. RlyReleaseStore.saveAll records the status changes it
 * saves (RlyReleaseTransitions) and flushes; other writers (raising, promoting, manual steps) flush after their own saves.
 * Events are only ever created by this class, in system mode; users read them.
 */
public with sharing class RlyReleaseLog {

    /** @description Via__c: done by a person in Salesforce. */
    public static final String VIA_SALESFORCE = 'Salesforce';
    /** @description Via__c: done from the Slack card. */
    public static final String VIA_SLACK = 'Slack';
    /** @description Via__c: done by the Git provider. */
    public static final String VIA_GIT = 'Git';
    /** @description Via__c: done by the target org's approval rule. */
    public static final String VIA_RULE = 'Rule';
    /** @description Via__c: done by the pipeline or the hub on its own. */
    public static final String VIA_PIPELINE = 'Pipeline';

    // The events added in this transaction and not saved yet, with the release each belongs to (its Id may come later).
    private static final List<Entry> PENDING = new List<Entry>();

    /** @description One event to save. */
    public class Entry {
        /** @description The release (its Id is read when the event is saved). */
        public RLY_Release__c rel;
        /** @description The event row (Release__c is set when it is saved). */
        public RLY_Release_Event__c row;

        /**
         * @description Sets the org the event happened in.
         * @param orgId the org, or null
         * @return this entry
         */
        public Entry inOrg(Id orgId) {
            row.Org__c = orgId;
            return this;
        }

        /**
         * @description Sets who did it and where.
         * @param actorId the user, or null
         * @param via Salesforce, Slack, Git, Rule or Pipeline
         * @return this entry
         */
        public Entry byActor(Id actorId, String via) {
            row.Actor__c = actorId;
            row.Via__c = via == null ? null : via.left(40);
            return this;
        }

        /**
         * @description Sets the reference (deploy id, pull request or run URL).
         * @param reference the reference, or null
         * @return this entry
         */
        public Entry withReference(String reference) {
            row.Reference__c = String.isBlank(reference) ? null : reference.left(255);
            return this;
        }
    }

    /**
     * @description Adds an event for a release (saved by the next flush).
     * @param rel the release (saved now or later in the transaction)
     * @param eventType an Event_Type__c value, for example Approved
     * @param detail what happened, in one line
     * @return the event, to add its org, actor and reference
     */
    public static Entry add(RLY_Release__c rel, String eventType, String detail) {
        Entry e = new Entry();
        e.rel = rel;
        e.row = new RLY_Release_Event__c(Event_Type__c = eventType, Detail__c = detail == null ? null : detail.left(32768),
            Occurred_On__c = System.now(), Via__c = VIA_PIPELINE);
        PENDING.add(e);
        return e;
    }

    /**
     * @description Adds an event for a release by its Id.
     * @param releaseId the release
     * @param eventType an Event_Type__c value
     * @param detail what happened, in one line
     * @return the event
     */
    public static Entry addFor(Id releaseId, String eventType, String detail) {
        return add(new RLY_Release__c(Id = releaseId), eventType, detail);
    }

    /**
     * @description History of a manual step checked off: "Assign the permission set in SIT: done (note)".
     * @param run the run as saved, with Step__r.Title__c and Org__r.Name
     */
    public static void manualStep(RLY_Manual_Step_Run__c run) {
        String what = run.Status__c == RlyManualSteps.STATUS_DONE ? 'done'
            : (run.Status__c == RlyManualSteps.STATUS_NOT_NEEDED ? 'not needed' : 'to do again');
        String title = run.Step__r == null ? 'Manual step' : run.Step__r.Title__c;
        String orgName = run.Org__r == null ? '' : ' in ' + run.Org__r.Name;
        addFor(run.Release__c, 'Manual_Step', title + orgName + ': ' + what + (run.Note__c == null ? '' : ' (' + run.Note__c + ')'))
            .inOrg(run.Org__c).byActor(UserInfo.getUserId(), VIA_SALESFORCE);
    }

    /**
     * @description History of a promotion raised: on the promotion, and "Promoted …" on each release it carries. Saved now.
     * @param promotion the promotion, saved
     * @param carried the releases it carries
     * @param route for example "SIT to PROD"
     */
    public static void promoted(RLY_Release__c promotion, List<RLY_Release__c> carried, String route) {
        List<String> names = new List<String>();
        for (RLY_Release__c r : carried) {
            names.add(r.Name);
            add(r, 'Promoted', 'Promoted from ' + route + ' with ' + promotion.Title__c)
                .inOrg(promotion.Target_Org__c).byActor(UserInfo.getUserId(), VIA_SALESFORCE);
        }
        add(promotion, 'Promoted', 'Promotion raised from ' + route + ', carrying ' + String.join(names, ', '))
            .inOrg(promotion.Source_Org__c).byActor(UserInfo.getUserId(), VIA_SALESFORCE);
        flush();
    }

    /**
     * @description How many events wait to be saved.
     * @return the number
     */
    public static Integer pendingCount() {
        return PENDING.size();
    }

    /**
     * @description Saves the events added so far (those whose release has an Id) in one insert, and forgets them.
     * Call it after the transaction's callouts.
     */
    public static void flush() {
        List<RLY_Release_Event__c> rows = new List<RLY_Release_Event__c>();
        for (Entry e : PENDING) {
            if (e.rel != null && e.rel.Id != null) {
                e.row.Release__c = e.rel.Id;
                rows.add(e.row);
            }
        }
        PENDING.clear();
        if (!rows.isEmpty()) {
            new SystemAccess().insertRows(rows);
        }
    }

    /**
     * @description The history of some releases, oldest first.
     * @param releaseIds the releases
     * @return the events, with Actor__r.Name and Org__r.Name
     */
    public static List<RLY_Release_Event__c> eventsOf(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new List<RLY_Release_Event__c>() : new SystemAccess().queryEvents(releaseIds);
    }

    /** @description Events are written only by Release Relay's Apex and read by every Release Relay user: system mode. */
    private without sharing class SystemAccess {

        /**
         * @description Saves events.
         * @param rows the events
         */
        public void insertRows(List<RLY_Release_Event__c> rows) {
            insert as system rows;
        }

        /**
         * @description See RlyReleaseLog.eventsOf.
         * @param releaseIds the releases
         * @return the events
         */
        public List<RLY_Release_Event__c> queryEvents(Set<Id> releaseIds) {
            return [SELECT Id, Name, Release__c, Release__r.Name, Org__c, Org__r.Name, Event_Type__c, Actor__c, Actor__r.Name, Via__c,
                           Detail__c, Reference__c, Occurred_On__c
                    FROM RLY_Release_Event__c WHERE Release__c IN :releaseIds WITH SYSTEM_MODE
                    ORDER BY Occurred_On__c ASC, Name ASC LIMIT 2000];
        }
    }
}
