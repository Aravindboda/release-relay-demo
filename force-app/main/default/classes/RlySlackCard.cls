/**
 * @description The Slack card of a release (one message per release, edited as it moves) and the one-line replies
 * in its thread. The card: a title line (REL · title, "Hotfix: " first for a hotfix), "Why: <reason>" for a hotfix and
 * "Promotes REL-…" for a promotion, a status line (emoji, status, route, who raised or approved
 * it), a steps line, Approve and Reject while it's ready for approval into an org approved in Slack, and a button
 * that opens the release in the hub. Emoji are Slack short codes. The thread replies are RlySlackReply.
 */
public with sharing class RlySlackCard {

    /** @description Action id of the Approve button. */
    public static final String APPROVE_ACTION = 'rly_approve';
    /** @description Action id of the Reject button. */
    public static final String REJECT_ACTION = 'rly_reject';

    /** @description Done. */
    public static final String DONE = ':white_check_mark:';
    /** @description Running or waiting. */
    public static final String WAITING = ':hourglass_flowing_sand:';
    /** @description Failed. */
    public static final String FAILED = ':x:';
    private static final String NOT_YET = ':white_circle:';
    private static final String STOPPED = ':no_entry:';
    private static final Map<String, String> CHECK_EMOJI = new Map<String, String>{
        'Passed' => DONE, 'Failed' => FAILED, 'Error' => FAILED, 'Bypassed' => ':warning:', 'Pending' => WAITING,
        'Skipped' => NOT_YET, 'Not configured' => NOT_YET, 'Deployed' => DONE, 'Deploying' => WAITING,
        'Approved' => DONE, 'Rejected' => STOPPED
    };
    private static final Map<String, String> STATUS_EMOJI = new Map<String, String>{
        'Ready for approval' => ':large_yellow_circle:', 'Checks failed' => ':red_circle:', 'Deployed' => DONE,
        'Deploy failed' => FAILED, 'Rejected' => STOPPED, 'Failed' => FAILED, 'Closed' => NOT_YET
    };

    /**
     * @description The card as chat.postMessage / chat.update arguments (without channel and ts).
     * @param rel the release, as RlyReleaseStore reads it, with its new status
     * @param approverName who approved or rejected it, or null
     * @return text and blocks
     */
    public static Map<String, Object> card(RLY_Release__c rel, String approverName) {
        String title = RlySlackCardText.title(rel);
        String body = '*' + RlySlackMessage.esc(title) + '*\n' + RlySlackCardText.aboutLines(rel) + statusLine(rel, approverName) + '\n' + stepsLine(rel) + RlyReleaseHistory.slackLine(rel);
        List<Object> blocks = new List<Object>{
            new Map<String, Object>{ 'type' => 'section', 'text' => new Map<String, Object>{ 'type' => 'mrkdwn', 'text' => body.left(2900) } },
            new Map<String, Object>{ 'type' => 'actions', 'block_id' => 'rly_actions', 'elements' => buttons(rel) }
        };
        return new Map<String, Object>{ 'text' => (title + ': ' + rel.Status__c).left(300), 'blocks' => blocks };
    }

    private static List<Object> buttons(RLY_Release__c rel) {
        List<Object> out = new List<Object>();
        if (rel.Status__c == 'Ready for approval' && RlyApprover.inSlack(rel.Target_Org__r)) {
            Map<String, Object> approve = button('Approve', APPROVE_ACTION, rel.Id);
            approve.put('style', 'primary');
            Map<String, Object> reject = button('Reject', REJECT_ACTION, rel.Id);
            reject.put('style', 'danger');
            out.add(approve);
            out.add(reject);
        }
        out.add(new Map<String, Object>{ 'type' => 'button', 'action_id' => 'rly_open', 'url' => RlySlackMessage.link(rel),
            'text' => plain('Open in ' + System.Label.RLY_App_Name) });
        return out;
    }

    private static Map<String, Object> button(String label, String actionId, Id releaseId) {
        return new Map<String, Object>{ 'type' => 'button', 'action_id' => actionId, 'value' => String.valueOf(releaseId), 'text' => plain(label) };
    }

    /**
     * @description A plain_text object.
     * @param text the text
     * @return the object
     */
    public static Map<String, Object> plain(String text) {
        return new Map<String, Object>{ 'type' => 'plain_text', 'text' => text, 'emoji' => true };
    }

    /**
     * @description The status line: emoji, status, route, and who raised or approved it.
     * @param rel the release
     * @param approverName who approved or rejected it, or null
     * @return the line (mrkdwn)
     */
    public static String statusLine(RLY_Release__c rel, String approverName) {
        String status = rel.Status__c;
        if (status == 'Rejected') {
            return STOPPED + ' Rejected' + byWhom(approverName) + ': “' + RlySlackMessage.esc(text(rel.Approval_Comment__c).left(300)) + '”';
        }
        if (status == 'Deploying' || status == 'Deployed') {
            return deployLine(rel) + ' · ' + route(rel) + approvedLine(rel, approverName);
        }
        String emoji = STATUS_EMOJI.containsKey(status) ? STATUS_EMOJI.get(status) : WAITING;
        return emoji + ' ' + RlyReleasePhase.phase(rel) + ' · ' + route(rel) + ' · raised by ' + RlySlackMessage.esc(raisedBy(rel));
    }

    private static String deployLine(RLY_Release__c rel) {
        if (rel.Status__c == 'Deployed') {
            return DONE + ' Deployed to ' + RlySlackMessage.esc(targetName(rel) + RlyManualStepText.stillOpen(rel, targetName(rel)));
        }
        return waitingInGit(rel) ? WAITING + ' Waiting for ' + RlySlackMessage.esc(RlyGitName.reviewers()) + ' reviewers before deploying'
            : ':rocket: Deploying to ' + RlySlackMessage.esc(targetName(rel));
    }

    private static String approvedLine(RLY_Release__c rel, String approverName) {
        return ' · approved' + byWhom(approverName) + (String.isBlank(rel.Approved_Via__c) ? '' : ' in ' + RlySlackMessage.esc(rel.Approved_Via__c));
    }

    /**
     * @description Whether the deploy waits for the Git provider's reviewers.
     * @param rel the release
     * @return true while it waits
     */
    public static Boolean waitingInGit(RLY_Release__c rel) {
        return rel.Status__c == 'Deploying' && RlyApprovalRuns.approvedInGit(rel);
    }

    /**
     * @description " by <name>", or nothing.
     * @param name the name, or null
     * @return the text (escaped)
     */
    public static String byWhom(String name) {
        return String.isBlank(name) ? '' : ' by ' + RlySlackMessage.esc(name);
    }

    /**
     * @description The steps line: collected, pull request, code scan, validation, approval, deploy.
     * @param rel the release
     * @return the line
     */
    public static String stepsLine(RLY_Release__c rel) {
        List<String> steps = new List<String>{
            (rel.Status__c == 'Retrieving' ? WAITING : DONE) + ' Collected',
            rel.PR_Number__c != null ? DONE + ' PR #' + rel.PR_Number__c.intValue() : NOT_YET + ' PR',
            emoji(rel.Scan_Status__c) + ' Scan' + findings(rel),
            emoji(rel.Validation_Status__c) + ' Validation',
            (rel.Status__c == 'Ready for approval' ? WAITING : emoji(rel.Approval_Status__c)) + ' Approval',
            emoji(rel.Deploy_Status__c) + (rel.Deploy_Status__c == 'Deployed' ? ' Deployed' : ' Deploy')
        };
        return String.join(steps, '   ');
    }

    private static String emoji(String checkStatus) {
        return CHECK_EMOJI.containsKey(checkStatus) ? CHECK_EMOJI.get(checkStatus) : NOT_YET;
    }

    private static String findings(RLY_Release__c rel) {
        Integer n = rel.Scan_Violations__c == null ? 0 : rel.Scan_Violations__c.intValue();
        return n > 0 ? ' (' + n + ' finding' + (n == 1 ? ')' : 's)') : '';
    }

    /**
     * @description The route: developer org → target org.
     * @param rel the release
     * @return the route (escaped)
     */
    public static String route(RLY_Release__c rel) {
        return RlySlackMessage.esc((rel.Source_Org__r == null ? '' : rel.Source_Org__r.Name) + ' → ' + targetName(rel));
    }

    /**
     * @description The target org's name.
     * @param rel the release
     * @return the name (the target branch when the org isn't read)
     */
    public static String targetName(RLY_Release__c rel) {
        return rel.Target_Org__r == null ? text(rel.Target_Branch__c) : rel.Target_Org__r.Name;
    }

    /**
     * @description A value, or an empty string for null.
     * @param value the value
     * @return the text
     */
    public static String text(String value) {
        return value == null ? '' : value;
    }

    /**
     * @description Who raised the release.
     * @param rel the release
     * @return the name, or an empty string
     */
    public static String raisedBy(RLY_Release__c rel) {
        return rel.CreatedBy == null ? '' : rel.CreatedBy.Name;
    }
}
