/**
 * @description The one-line replies in a release card's thread, one per event (raised, checks passed or failed,
 * approved or waiting for the Git provider, deployed, deploy failed, rejected).
 */
public with sharing class RlySlackReply {

    /**
     * @description The one-line reply for an event, in the card's thread.
     * @param rel the release, with its new status
     * @param event the event (RlySlack.EVENTS or RlySlack.APPROVED)
     * @param approverName who approved or rejected it, or null
     * @return the line (mrkdwn)
     */
    public static String forEvent(RLY_Release__c rel, String event, String approverName) {
        String target = RlySlackMessage.esc(RlySlackCard.targetName(rel));
        Map<String, String> lines = new Map<String, String>{
            'Raised' => ':outbox_tray: Raised from ' + RlySlackMessage.esc(rel.Source_Org__r == null ? '' : rel.Source_Org__r.Name)
                + ' by ' + RlySlackMessage.esc(RlySlackCard.raisedBy(rel)) + ' · ' + (rel.Component_Count__c == null ? 0 : rel.Component_Count__c.intValue()) + ' component(s)',
            'Ready for approval' => RlySlackCard.DONE + ' Checks passed: code scan ' + RlySlackCard.text(rel.Scan_Status__c).toLowerCase()
                + ', validation in ' + target + ' ' + RlySlackCard.text(rel.Validation_Status__c).toLowerCase(),
            'Checks failed' => ':red_circle: Checks failed: ' + RlySlackMessage.esc(RlySlackMessage.checksReason(rel).replace('\n', '; ')),
            'Deployed' => ':rocket: Deployed to ' + target,
            'Deploy failed' => RlySlackCard.FAILED + ' Deploy to ' + target + ' failed: ' + RlySlackMessage.esc(RlySlackCard.text(rel.Error_Message__c).left(300)),
            'Rejected' => RlySlackCard.statusLine(rel, approverName)
        };
        if (event == RlySlack.APPROVED) {
            return RlySlackCard.waitingInGit(rel, approverName) ? RlySlackCard.WAITING + ' Waiting for approval in ' + RlySlackMessage.esc(rel.Approved_Via__c)
                : ':+1: Approved' + RlySlackCard.byWhom(approverName) + ' (' + RlySlackMessage.esc(rel.Approved_Via__c) + ') · deploying…';
        }
        return lines.containsKey(event) ? lines.get(event) : RlySlackCard.statusLine(rel, approverName);
    }
}
