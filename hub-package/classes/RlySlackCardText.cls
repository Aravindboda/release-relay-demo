/**
 * @description The text a release's Slack card adds for hotfixes and promotions (RlySlackCard): the title ("Hotfix: "
 * first for a hotfix), "Why: <reason>" for a hotfix, "Promotes REL-…, REL-…" for a promotion and "Deletes: …" (the first
 * five, then "and n more") for a release that deletes components.
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
        String out = '';
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
        return out;
    }
}
