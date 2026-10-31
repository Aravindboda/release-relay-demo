/**
 * @description What the release page and the Slack card say about where a release is: the phase (the status, or
 * Resolving conflicts while a resolve run checks it), a notice (the target moved so the checks run again, or the
 * merge waits for the Git provider's reviewers) and the Slack card's link.
 */
public with sharing class RlyReleasePhase {

    /**
     * @description The label for the status pill.
     * @param rel the release
     * @return Resolving conflicts while a resolve run checks it, otherwise the status
     */
    public static String phase(RLY_Release__c rel) {
        return rel.Status__c == 'Validating' && rel.Pending_Run__c == 'resolve' ? 'Resolving conflicts' : rel.Status__c;
    }

    /**
     * @description The info line above the timeline.
     * @param rel the release, with Target_Org__r
     * @return the notice, or null
     */
    public static String notice(RLY_Release__c rel) {
        if (rel.Status__c == 'Validating' && rel.Pending_Run__c == RlyPipelineRun.RECHECK) {
            String target = rel.Target_Org__r == null ? rel.Target_Branch__c : rel.Target_Org__r.Name;
            return target + ' changed after the checks passed, so they are running again.';
        }
        if (rel.Status__c == 'Deploying' && rel.Deploy_Status__c == 'Deploying' && RlyApprovalRuns.approvedInGit(rel)) {
            return 'Waiting for ' + RlyGitName.reviewers() + ' reviewers before deploying.';
        }
        return null;
    }

    /**
     * @description A link that opens the release's Slack card.
     * @param rel the release, with Slack_Channel_Id__c and Slack_Ts__c
     * @return the link, or null when there's no card
     */
    public static String slackUrl(RLY_Release__c rel) {
        if (String.isBlank(rel.Slack_Channel_Id__c) || String.isBlank(rel.Slack_Ts__c)) {
            return null;
        }
        return 'https://slack.com/app_redirect?channel=' + EncodingUtil.urlEncode(rel.Slack_Channel_Id__c, 'UTF-8')
            + '&message_ts=' + EncodingUtil.urlEncode(rel.Slack_Ts__c, 'UTF-8');
    }

    /**
     * @description The channel the release card was posted to (the target org's channel).
     * @param rel the release, with Slack_Ts__c and Target_Org__r.Slack_Channel__c
     * @return the channel, or null when there's no card
     */
    public static String slackChannel(RLY_Release__c rel) {
        if (String.isBlank(rel.Slack_Ts__c)) {
            return null;
        }
        return rel.Target_Org__r == null || String.isBlank(rel.Target_Org__r.Slack_Channel__c) ? rel.Slack_Channel_Id__c
            : rel.Target_Org__r.Slack_Channel__c;
    }

    /**
     * @description The release's test classes.
     * @param rel the release, with Test_Classes__c
     * @return the class names (empty when none)
     */
    public static List<String> tests(RLY_Release__c rel) {
        List<String> out = new List<String>();
        for (String t : String.isBlank(rel.Test_Classes__c) ? new List<String>() : rel.Test_Classes__c.split(',')) {
            if (String.isNotBlank(t)) {
                out.add(t.trim());
            }
        }
        return out;
    }
}
