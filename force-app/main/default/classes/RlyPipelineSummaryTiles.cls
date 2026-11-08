/**
 * @description Pipeline tab status strip (build 50): builds the Git, Route and Approvals &amp; Slack tiles of
 * RlyPipelineSummary from stored records (RlyPipelineSummaryChecks builds Security and Credentials and the Orgs dot).
 * No SOQL or DML of its own except through the stores it calls.
 */
public with sharing class RlyPipelineSummaryTiles {

    private static final Map<String, String> PROVIDER_LABELS = new Map<String, String>{
        'GitHub' => 'GitHub', 'GitLab' => 'GitLab', 'Bitbucket' => 'Bitbucket', 'AzureDevOps' => 'Azure DevOps'
    };
    private static final String CONNECTED = 'Connected';
    private static final String FAILED = 'Failed';

    /**
     * @description The Git tile: provider and status.
     * @param conn the Git connection, or null
     * @return the tile
     */
    public static RlyPipelineSummary.Tile git(RLY_Git_Connection__c conn) {
        RlyPipelineSummary.Tile t = tile('git', 'Git', RlyPipelineSummary.CONNECTION);
        if (conn == null) {
            t.value = 'Not connected';
            t.detail = 'Choose the provider and repository';
            t.tone = RlyPipelineSummary.TONE_WARN;
            return t;
        }
        String provider = PROVIDER_LABELS.containsKey(conn.Provider__c) ? PROVIDER_LABELS.get(conn.Provider__c) : conn.Provider__c;
        t.checkedOn = conn.Last_Checked__c;
        t.detail = conn.Repository__c;
        if (conn.Status__c == CONNECTED) {
            t.value = provider + ' · connected';
            t.tone = RlyPipelineSummary.TONE_OK;
        } else if (conn.Status__c == FAILED) {
            t.value = provider + ' · check failed';
            t.detail = String.isBlank(conn.Status_Message__c) ? conn.Repository__c : conn.Status_Message__c.left(120);
            t.tone = RlyPipelineSummary.TONE_BAD;
        } else {
            t.value = provider + ' · not checked';
            t.tone = RlyPipelineSummary.TONE_WARN;
        }
        return t;
    }

    /**
     * @description The Route tile: the lane, and whether its orgs sign in.
     * @param orgs every registered org
     * @return the tile
     */
    public static RlyPipelineSummary.Tile route(List<RLY_Org__c> orgs) {
        RlyPipelineSummary.Tile t = tile('route', 'Route', RlyPipelineSummary.CONNECTION);
        List<RLY_Org__c> developers = new List<RLY_Org__c>();
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Developer') {
                developers.add(o);
            } else if (RlyRouteRules.isStage(o)) {
                stages.add(o);
            }
        }
        if (developers.isEmpty() && stages.isEmpty()) {
            t.value = 'No route yet';
            t.detail = 'Register the developer orgs and stages';
            t.tone = RlyPipelineSummary.TONE_WARN;
            return t;
        }
        t.value = lane(developers, RlyRouteRules.ordered(stages));
        List<RLY_Org__c> onRoute = new List<RLY_Org__c>(developers);
        onRoute.addAll(stages);
        signInLine(t, onRoute, RlyRouteRules.warnings(developers, stages));
        return t;
    }

    /**
     * @description The Approvals &amp; Slack tile: Slack on or off, approvers linked, production approval.
     * @param slack the Slack settings row, or null
     * @return the tile
     */
    public static RlyPipelineSummary.Tile approvals(RLY_Notification__c slack) {
        RlyPipelineSummary.Tile t = tile('approvals', 'Approvals & Slack', RlyPipelineSummary.APPROVALS);
        String prod = RlyProdApproval.isOn() ? 'production needs the add-on' : 'any approver approves production';
        Boolean slackOn = slack != null && slack.Enabled__c == true && String.isNotBlank(slack.Bot_Token_Hint__c);
        if (!slackOn) {
            t.value = slack == null || String.isBlank(slack.Bot_Token_Hint__c) ? 'Slack not set up' : 'Slack off';
            t.detail = 'Approve in Salesforce · ' + prod;
            t.tone = RlyPipelineSummary.TONE_NONE;
            return t;
        }
        slackLine(t, slack);
        return t;
    }

    // Slack on: whether the last message went out, and how many approvers are linked.
    private static void slackLine(RlyPipelineSummary.Tile t, RLY_Notification__c slack) {
        Map<String, Integer> counts = RlySlackApproverRows.counts();
        Integer linked = counts.get('linked');
        Integer total = counts.get('total');
        String lastResult = slack.Last_Result__c == null ? '' : slack.Last_Result__c;
        Boolean lastFailed = lastResult.startsWithIgnoreCase('Error') || lastResult.startsWithIgnoreCase('Failed');
        t.value = lastFailed ? 'Slack: last message failed' : 'Slack connected';
        t.detail = linked + ' of ' + total + (total == 1 ? ' approver linked' : ' approvers linked');
        t.tone = lastFailed || linked < total ? RlyPipelineSummary.TONE_WARN : RlyPipelineSummary.TONE_OK;
    }

    private static void signInLine(RlyPipelineSummary.Tile t, List<RLY_Org__c> onRoute, List<String> warnings) {
        List<String> failedNames = new List<String>();
        Integer unchecked = 0;
        for (RLY_Org__c o : onRoute) {
            if (o.Status__c == FAILED) {
                failedNames.add(o.Name);
            } else if (o.Status__c != CONNECTED) {
                unchecked++;
            }
        }
        String count = onRoute.size() + (onRoute.size() == 1 ? ' org' : ' orgs');
        if (!failedNames.isEmpty()) {
            t.detail = String.join(failedNames, ', ') + ' can\'t sign in';
            t.tone = RlyPipelineSummary.TONE_BAD;
        } else if (!warnings.isEmpty()) {
            t.detail = warnings[0];
            t.tone = RlyPipelineSummary.TONE_WARN;
        } else if (unchecked > 0) {
            t.detail = count + ' · ' + unchecked + ' not checked';
            t.tone = RlyPipelineSummary.TONE_WARN;
        } else {
            t.detail = count + ' · all signed in';
            t.tone = RlyPipelineSummary.TONE_OK;
        }
    }

    private static String lane(List<RLY_Org__c> developers, List<RLY_Org__c> stages) {
        List<String> names = new List<String>();
        if (developers.size() == 1) {
            names.add(developers[0].Name);
        } else if (!developers.isEmpty()) {
            names.add(developers.size() + ' dev orgs');
        }
        for (RLY_Org__c o : stages) {
            names.add(o.Name);
        }
        return String.join(names, RlySettingsLogDiff.ARROW);
    }

    /**
     * @description A tile with its key, heading and section.
     * @param key the tile key
     * @param label the heading
     * @param section the section it opens
     * @return the tile (tone none)
     */
    public static RlyPipelineSummary.Tile tile(String key, String label, String section) {
        RlyPipelineSummary.Tile t = new RlyPipelineSummary.Tile();
        t.key = key;
        t.label = label;
        t.section = section;
        return t;
    }
}
