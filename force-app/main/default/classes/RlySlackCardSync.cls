/**
 * @description Keeps a release's Slack card current. Every writer that moves a release (the page's reads, approvals and
 * rejections in Salesforce or from the Slack card, manual steps, conflict resolutions, back promote syncs) calls
 * notifyChange with the release as it was and as it is now, after its own callouts and before its save (a callout can't
 * follow DML in the same transaction); RlySlack.saveResults() then saves the Slack result. A change that is a selected
 * event posts or edits the card and sends the event's messages (RlySlack.deliverEvent); any other change the card shows
 * (RlySlackCardState) edits the card alone, whatever events are selected. Slack off, or no card yet: nothing is called.
 */
public with sharing class RlySlackCardSync {

    /**
     * @description Tells Slack about a change to a release, before the caller saves it. Never throws: a Slack failure is
     * kept for Last_Result__c (RlySlack.saveResults) and never stops the change.
     * @param prior the release before the change (a clone taken before it was changed)
     * @param rel the release, as RlyReleaseStore reads it, with the change
     */
    public static void notifyChange(RLY_Release__c prior, RLY_Release__c rel) {
        if (prior == null || rel == null) {
            return;
        }
        try {
            RLY_Notification__c s = RlySlack.settings();
            if (s == null || !s.Enabled__c) {
                return;
            }
            String event = RlySlack.eventFor(prior.Status__c, rel.Status__c);
            if (event != null && RlySlack.wanted(s, event)) {
                RlySlack.deliverEvent(s, rel, event);
            } else if (RlySlackCardState.changed(prior, rel)) {
                refreshCard(s, rel);
            }
        } catch (Exception e) {
            return; // the Slack record couldn't be read: the change goes on without Slack
        }
    }

    // Edits the release's card to show its current state; the result (or the failure) is kept for RlySlack.saveResults().
    private static void refreshCard(RLY_Notification__c s, RLY_Release__c rel) {
        String result;
        try {
            result = RlySlackDelivery.refresh(rel);
        } catch (Exception e) {
            result = RlySlackApi.isRateLimited(e) ? RlySlack.busyResult(rel) : 'Failed: ' + rel.Name + ' · card update: ' + e.getMessage();
        }
        RlySlack.record(s.Id, result);
    }
}
