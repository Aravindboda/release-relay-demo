/**
 * @description What the release page and the Slack card say about a deploy's manual steps (RlyManualStepGate.counts):
 * the summary, the Slack card's line and, after a deploy, the steps still open.
 */
public with sharing class RlyManualStepText {

    /**
     * @description The release page's summary: "2 manual steps: 1 before deploy (open), 1 after deploy".
     * @param c the counts
     * @return the summary, or null when the deploy has no manual steps
     */
    public static String summary(RlyManualSteps.Counts c) {
        if (c.total() == 0) {
            return null;
        }
        List<String> parts = new List<String>();
        if (c.beforeCount > 0) {
            parts.add(c.beforeCount + ' before deploy' + state(c.beforeCount, c.beforeOpen));
        }
        if (c.afterCount > 0) {
            parts.add(c.afterCount + ' after deploy' + (c.afterOpen == 0 ? ' (done)' : ''));
        }
        return RlyManualSteps.stepWords(c.total()) + ': ' + String.join(parts, ', ');
    }

    private static String state(Integer total, Integer open) {
        if (open == 0) {
            return ' (done)';
        }
        return open == total ? ' (open)' : ' (' + open + ' open)';
    }

    /**
     * @description The Slack card's line: "Manual steps: 1 before deploy, 1 after deploy".
     * @param c the counts
     * @return the line, or null when the deploy has no manual steps
     */
    public static String slackLine(RlyManualSteps.Counts c) {
        if (c.total() == 0) {
            return null;
        }
        List<String> parts = new List<String>();
        if (c.beforeCount > 0) {
            parts.add(c.beforeCount + ' before deploy');
        }
        if (c.afterCount > 0) {
            parts.add(c.afterCount + ' after deploy');
        }
        return 'Manual steps: ' + String.join(parts, ', ');
    }

    /**
     * @description After a deploy: " · 1 manual step still open in PROD", or nothing.
     * @param rel the release, deployed
     * @param orgName its target org's name
     * @return the text (not escaped)
     */
    public static String stillOpen(RLY_Release__c rel, String orgName) {
        Integer n = RlyManualStepGate.counts(rel).open();
        return n == 0 ? '' : ' · ' + RlyManualSteps.stepWords(n) + ' still open in ' + orgName;
    }
}
