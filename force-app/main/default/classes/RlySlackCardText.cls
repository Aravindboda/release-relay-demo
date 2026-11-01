/**
 * @description The text a release's Slack card adds for hotfixes and promotions (RlySlackCard): the title ("Hotfix: "
 * first for a hotfix), "Why: <reason>" for a hotfix, "Promotes REL-…, REL-…" for a promotion and "Deletes: …" (the first
 * five, then "and n more") for a release that deletes components, and "Manual steps: 1 before deploy, 1 after deploy"
 * for a deploy with manual steps; a release with only manual steps says so first.
 */
public with sharing class RlySlackCardText {

    /**
     * @description The card's title: REL · title, with "Hotfix: " first for a hotfix.
     * @param rel the release
     * @return the title (not escaped)
     */
    public static String title(RLY_Release__c rel) {
        return (RlyHotfix.isHotfix(rel) ? 'Hotfix: ' : '') + rel.Name + ' · ' + rel.Title__c;
    }

    /**
     * @description The lines under the title: "Why: <reason>" for a hotfix, "Promotes REL-…, REL-…" for a promotion.
     * @param rel the release
     * @return the lines (mrkdwn, each ending with a line break), or an empty string
     */
    public static String aboutLines(RLY_Release__c rel) {
        String out = RlyManualOnly.isManualOnly(rel) ? ':memo: ' + RlyManualOnly.PILL + ': no Git branch, pull request or pipeline run\n' : '';
        if (RlyHotfix.isHotfix(rel) && String.isNotBlank(rel.Hotfix_Reason__c)) {
            out += 'Why: ' + RlySlackMessage.esc(rel.Hotfix_Reason__c.left(300)) + '\n';
        }
        List<String> carried = RlyPromotion.isPromotion(rel) ? RlyCarried.names(rel) : new List<String>();
        if (!carried.isEmpty()) {
            out += 'Promotes ' + RlySlackMessage.esc(String.join(carried, ', ')) + '\n';
        }
        String deletes = RlyDeletions.summary(rel);
        if (deletes != null) {
            out += RlySlackMessage.esc(deletes) + '\n';
        }
        String manual = RlyManualStepText.slackLine(RlyManualStepGate.counts(rel));
        if (manual != null) {
            out += RlySlackMessage.esc(manual) + '\n';
        }
        return out;
    }

    /**
     * @description The steps line of a release with only manual steps: no Git or pipeline steps, just the approval and
     * the manual steps that make its deploy.
     * @param rel the release
     * @return the line (mrkdwn)
     */
    public static String manualOnlySteps(RLY_Release__c rel) {
        String approval = RlySlackCardState.awaitsApprover(rel) ? RlySlackCard.WAITING : stateEmoji(rel.Approval_Status__c);
        String deploy = stateEmoji(rel.Deploy_Status__c) + (rel.Deploy_Status__c == 'Deployed' ? ' Manual steps done' : ' Manual steps');
        return String.join(new List<String>{ ':white_circle: Scan, validation: ' + RlyManualOnly.NOT_NEEDED,
            approval + ' Approval', deploy }, '   ');
    }

    private static String stateEmoji(String state) {
        if (state == 'Approved' || state == 'Deployed') {
            return RlySlackCard.DONE;
        }
        if (state == 'Deploying') {
            return RlySlackCard.WAITING;
        }
        return state == 'Rejected' || state == 'Failed' ? RlySlackCard.FAILED : ':white_circle:';
    }
}
