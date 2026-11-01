/**
 * @description Keeps a release's Slack card (RlySlackCard) in step with the release: whether a save changed anything the
 * card shows (so the card is edited even when no Slack event is selected for that change), whether the card still
 * offers Approve and Reject, and the lines for approvals (who, where, the second approver, the org's rule), a deploy
 * that waits for a second approver or for manual steps, a failed deploy or failed checks (with the reason), how the
 * deploy ran (quick or full) and the branches merged back.
 */
public with sharing class RlySlackCardState {

    private static final String READY = 'Ready for approval';
    private static final String APPROVED_STATE = 'Approved';
    private static final String WAITING = ':hourglass_flowing_sand:';

    /**
     * @description Whether a change moved anything the card shows: the status (or phase), the approval, the deploy, the
     * checks, the pull request or the branches merged back.
     * @param prior the release before the change
     * @param rel the release now
     * @return true when the card needs editing
     */
    public static Boolean changed(RLY_Release__c prior, RLY_Release__c rel) {
        return prior != null && rel != null && fingerprint(prior) != fingerprint(rel);
    }

    private static String fingerprint(RLY_Release__c rel) {
        List<Object> parts = new List<Object>{ rel.Status__c, rel.Pending_Run__c, rel.Approval_Status__c, rel.Approved_By__c,
            rel.Approved_Via__c, rel.Second_Approved_By__c, rel.Deploy_Status__c, rel.Scan_Status__c, rel.Validation_Status__c,
            rel.PR_Number__c, String.isBlank(rel.Back_Merge_Result__c) ? 0 : rel.Back_Merge_Result__c.hashCode() };
        return String.join(parts, '|');
    }

    /**
     * @description Whether the release still waits for an approver's decision (the card then offers Approve and Reject
     * when its target org is approved in Slack). A first of two approvals still waits; an approved release waiting for
     * manual steps doesn't.
     * @param rel the release
     * @return true while a decision is awaited
     */
    public static Boolean awaitsApprover(RLY_Release__c rel) {
        return rel.Status__c == READY && rel.Approval_Status__c != APPROVED_STATE;
    }

    /**
     * @description The line that replaces Approve and Reject once the release is decided: who approved it (and where, the
     * second approver, or the org's rule) or who rejected it.
     * @param rel the release
     * @param approverName who approved or rejected it, or null
     * @return the line (mrkdwn), or null when nothing is decided yet
     */
    public static String decisionLine(RLY_Release__c rel, String approverName) {
        if (rel.Status__c == 'Rejected' || rel.Approval_Status__c == 'Rejected') {
            return ':no_entry: Rejected' + RlySlackCard.byWhom(approverName) + via(rel) + '. The approval is closed.';
        }
        if (rel.Approval_Status__c == APPROVED_STATE) {
            String text = approvedText(rel, approverName);
            return RlySlackCard.DONE + ' ' + text.left(1).toUpperCase() + text.substring(1) + '. The approval is closed.';
        }
        return null;
    }

    /**
     * @description The card's context block with the decision line, in place of Approve and Reject once it is decided.
     * @param rel the release
     * @param approverName who approved or rejected it, or null
     * @return the block, or an empty list while nothing is decided
     */
    public static List<Object> decisionBlocks(RLY_Release__c rel, String approverName) {
        String decision = decisionLine(rel, approverName);
        List<Object> out = new List<Object>();
        if (decision != null) {
            out.add(new Map<String, Object>{ 'type' => 'context', 'block_id' => 'rly_decision', 'elements' => new List<Object>{
                new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => decision.left(2900) } } });
        }
        return out;
    }

    /**
     * @description "approved by Ana in Slack, second approver Ben", or "approved automatically by the org's rule".
     * @param rel the release
     * @param approverName who approved it, or null
     * @return the words (escaped)
     */
    public static String approvedText(RLY_Release__c rel, String approverName) {
        if (rel.Approved_Via__c == RlyReleaseLog.VIA_RULE) {
            return 'approved automatically by the rule for ' + RlySlackMessage.esc(RlySlackCard.targetName(rel));
        }
        String second = RlyReleaseStore.userName(rel.Second_Approved_By__c);
        return 'approved' + RlySlackCard.byWhom(approverName) + via(rel)
            + (String.isBlank(second) ? '' : ', second approver ' + RlySlackMessage.esc(second));
    }

    private static String via(RLY_Release__c rel) {
        return String.isBlank(rel.Approved_Via__c) ? '' : ' in ' + RlySlackMessage.esc(rel.Approved_Via__c);
    }

    /**
     * @description The status line for a release that is approved but waits (for a second approver, or for the
     * deployment team's manual steps before deploy), whose deploy failed, or whose checks failed.
     * @param rel the release
     * @param approverName who approved it, or null
     * @return the line (mrkdwn), or null for any other state
     */
    public static String heldOrFailedLine(RLY_Release__c rel, String approverName) {
        String route = RlySlackCard.route(rel);
        if (RlyTwoApprovers.waitsForSecond(rel)) {
            return WAITING + ' Approved' + RlySlackCard.byWhom(approverName) + via(rel) + '. Waiting for a second approver · ' + route;
        }
        if (rel.Status__c == READY && rel.Approval_Status__c == APPROVED_STATE) {
            String gate = RlyManualStepGate.notice(rel);
            return WAITING + ' ' + RlySlackMessage.esc(gate == null ? 'Approved. Waiting to deploy.' : gate) + ' · ' + route
                + ' · ' + approvedText(rel, approverName);
        }
        if (rel.Status__c == 'Deploy failed') {
            return RlySlackCard.FAILED + ' Deploy to ' + RlySlackMessage.esc(RlySlackCard.targetName(rel)) + ' failed · ' + route
                + ': ' + RlySlackMessage.esc(RlySlackCard.text(rel.Error_Message__c).left(300));
        }
        if (rel.Status__c == 'Checks failed') {
            return ':red_circle: Checks failed · ' + route + ': '
                + RlySlackMessage.esc(RlySlackMessage.checksReason(rel).replace('\n', '; ').left(300));
        }
        return null;
    }

    /**
     * @description How the deploy ran, from its result: " (quick deploy)" or " (full deploy, 12 tests run)".
     * @param rel the release, with Deploy_Result__c
     * @return the words, or an empty string without a deploy result
     */
    public static String deployHow(RLY_Release__c rel) {
        RlyEvidenceText.Deploy d = RlyEvidenceText.deployOf(rel.Deploy_Result__c);
        if (d.quick) {
            return ' (quick deploy)';
        }
        if (String.isBlank(d.deployId)) {
            return '';
        }
        return ' (full deploy' + (d.testsRun > 0 ? ', ' + d.testsRun + ' tests run' : '') + ')';
    }

    /**
     * @description The branches brought up to date after the merge: "Branches merged back: 3 synced, 1 conflict".
     * @param rel the release, with Back_Merge_Result__c
     * @return the line (mrkdwn, starting with a line break), or an empty string
     */
    public static String mergedBackLine(RLY_Release__c rel) {
        if (String.isBlank(rel.Back_Merge_Result__c)) {
            return '';
        }
        return '\n:twisted_rightwards_arrows: Branches merged back: ' + RlySlackMessage.esc(RlyEvidenceText.backMergeCounts(rel.Back_Merge_Result__c));
    }
}
