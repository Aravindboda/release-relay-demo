/**
 * @description The release page's history, flows and approval reason (RlyReleasesController.DetailHistory): the events
 * of RLY_Release_Event__c oldest first, the flow activation results, and why the release needs an approver or was
 * approved automatically (RlyApprovalRules).
 */
public with sharing class RlyReleaseHistory {

    /** @description One history event, as the page's timeline shows it. */
    public class EventRow {
        /** @description The event record. */
        @AuraEnabled public Id id;
        /** @description Event_Type__c API value, for example Approved or Flow_Activated. */
        @AuraEnabled public String eventType;
        /** @description A title, or null (the page words it from eventType). */
        @AuraEnabled public String title;
        /** @description The org it happened in, or null. */
        @AuraEnabled public String orgName;
        /** @description Who did it, or null. */
        @AuraEnabled public String actorName;
        /** @description Salesforce, Slack, Git, Rule or Pipeline. */
        @AuraEnabled public String via;
        /** @description What happened, in one line. */
        @AuraEnabled public String detail;
        /** @description Deploy id, pull request or run URL, or null. */
        @AuraEnabled public String reference;
        /** @description When it happened. */
        @AuraEnabled public Datetime occurredOn;
    }

    /**
     * @description Fills the page's history, flows and approval reason.
     * @param d the page payload, with release set
     */
    public static void fill(RlyReleasesController.Detail d) {
        d.events = events(d.release.Id);
        d.flows = RlyFlowResults.forRelease(d.release);
        d.approvalReason = approvalReason(d.release);
    }

    /**
     * @description A release's events, oldest first.
     * @param releaseId the release
     * @return the rows
     */
    public static List<EventRow> events(Id releaseId) {
        List<EventRow> out = new List<EventRow>();
        for (RLY_Release_Event__c e : RlyReleaseLog.eventsOf(new Set<Id>{ releaseId })) {
            out.add(rowOf(e));
        }
        return out;
    }

    /**
     * @description One event as a row.
     * @param e the event, with Org__r.Name and Actor__r.Name
     * @return the row
     */
    public static EventRow rowOf(RLY_Release_Event__c e) {
        EventRow r = new EventRow();
        r.id = e.Id;
        r.eventType = e.Event_Type__c;
        r.orgName = e.Org__r == null ? null : e.Org__r.Name;
        r.actorName = e.Actor__r == null ? null : e.Actor__r.Name;
        r.via = e.Via__c;
        r.detail = e.Detail__c;
        r.reference = e.Reference__c;
        r.occurredOn = e.Occurred_On__c;
        return r;
    }

    /**
     * @description The Slack card's line under the steps: why it needs an approver, or why it was approved automatically.
     * @param rel the release
     * @return "\n_reason_", or empty when there's nothing to say
     */
    public static String slackLine(RLY_Release__c rel) {
        try {
            Boolean show = rel.Status__c == 'Ready for approval' || rel.Approved_Via__c == RlyReleaseLog.VIA_RULE;
            String reason = show ? approvalReason(rel) : null;
            return String.isBlank(reason) ? '' : '\n_' + RlySlackMessage.esc(reason) + '_';
        } catch (SObjectException e) {
            return ''; // a release read without the rule fields: no reason line
        }
    }

    /**
     * @description Why the release needs an approver ("Needs approval: contains a Flow and a Profile", "Always needs
     * approval in PROD") or why it was approved automatically. Null for a back promote sync (its org's own setting).
     * @param rel the release, with Approved_Via__c, Approval_Comment__c and Target_Org__r's approval rule fields
     * @return the reason, or null
     */
    public static String approvalReason(RLY_Release__c rel) {
        if (rel.Approved_Via__c == RlyReleaseLog.VIA_RULE) {
            return rel.Approval_Comment__c;
        }
        if (RlyPromotion.typeOf(rel) == RlyPromotion.TYPE_BACK_PROMOTE) {
            return null;
        }
        return RlyApprovalRules.decide(rel).reason;
    }
}
