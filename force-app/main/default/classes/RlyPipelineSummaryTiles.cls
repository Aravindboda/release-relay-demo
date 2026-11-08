/**
 * @description Pipeline tab status strip (build 50): builds each tile of RlyPipelineSummary from stored records, and the
 * problems Security &amp; credentials lists. No SOQL or DML of its own except through the stores it calls.
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
        Boolean on = slack != null && slack.Enabled__c == true && String.isNotBlank(slack.Bot_Token_Hint__c);
        if (!on) {
            t.value = slack == null || String.isBlank(slack.Bot_Token_Hint__c) ? 'Slack not set up' : 'Slack off';
            t.detail = 'Approve in Salesforce · ' + prod;
            t.tone = RlyPipelineSummary.TONE_NONE;
            return t;
        }
        Map<String, Integer> counts = RlySlackApproverRows.counts();
        Integer linked = counts.get('linked');
        Integer total = counts.get('total');
        String last = slack.Last_Result__c == null ? '' : slack.Last_Result__c;
        Boolean lastFailed = last.startsWithIgnoreCase('Error') || last.startsWithIgnoreCase('Failed');
        t.value = lastFailed ? 'Slack: last message failed' : 'Slack connected';
        t.detail = linked + ' of ' + total + (total == 1 ? ' approver linked' : ' approvers linked');
        t.tone = lastFailed || linked < total ? RlyPipelineSummary.TONE_WARN : RlyPipelineSummary.TONE_OK;
        return t;
    }

    /**
     * @description The Security tile, from the last Repository security check kept on RLY_Run_Key__c; adds what to fix
     * (and run signing being off) to the problems.
     * @param key the RLY_Run_Key__c org default row
     * @param problems the summary's problems (added to)
     * @return the tile
     */
    public static RlyPipelineSummary.Tile security(RLY_Run_Key__c key, List<RlyPipelineSummary.Problem> problems) {
        RlyPipelineSummary.Tile t = tile('security', 'Security', RlyPipelineSummary.SECURITY);
        Integer missing = key.Security_Missing__c == null ? 0 : key.Security_Missing__c.intValue();
        Integer unknown = key.Security_Unknown__c == null ? 0 : key.Security_Unknown__c.intValue();
        List<String> names = RlyPipelineSummaryStore.securityProblems(key);
        for (String n : names) {
            problems.add(problem('Fix', RlyPipelineSummary.TONE_BAD, n));
        }
        if (String.isBlank(key.Key__c)) {
            problems.add(problem('Off', RlyPipelineSummary.TONE_WARN, 'Run signing is off: runs aren\'t signed'));
        }
        t.checkedOn = key.Security_Checked_On__c;
        if (key.Security_Checked_On__c == null) {
            t.value = 'Not checked';
            t.detail = 'Check the repository';
        } else if (missing > 0) {
            t.value = missing + ' to fix';
            t.detail = names.isEmpty() ? 'See Repository security' : names[0];
            t.tone = RlyPipelineSummary.TONE_BAD;
        } else if (unknown > 0) {
            t.value = unknown + ' couldn\'t be read';
            t.detail = 'Check again with a token that can read them';
            t.tone = RlyPipelineSummary.TONE_WARN;
        } else {
            t.value = 'OK';
            t.detail = 'Every protection in place';
            t.tone = RlyPipelineSummary.TONE_OK;
        }
        return t;
    }

    /**
     * @description The Credentials tile, from the stored credential rows (build 49); adds each one needing attention to
     * the problems.
     * @param rows the credential rows, soonest expiry first
     * @param problems the summary's problems (added to)
     * @return the tile
     */
    public static RlyPipelineSummary.Tile credentials(List<RLY_Credential_Status__c> rows, List<RlyPipelineSummary.Problem> problems) {
        RlyPipelineSummary.Tile t = tile('credentials', 'Credentials', RlyPipelineSummary.SECURITY);
        Map<String, Integer> counts = new Map<String, Integer>();
        RLY_Credential_Status__c worstRow;
        for (RLY_Credential_Status__c r : rows) {
            counts.put(r.Status__c, (counts.containsKey(r.Status__c) ? counts.get(r.Status__c) : 0) + 1);
            t.checkedOn = t.checkedOn == null || (r.Last_Checked__c != null && r.Last_Checked__c > t.checkedOn) ? r.Last_Checked__c : t.checkedOn;
            if (RlyCredentialRows.ATTENTION.contains(r.Status__c)) {
                problems.add(credentialProblem(r));
                worstRow = worstRow == null || RlyCredentialRows.worse(worstRow.Status__c, r.Status__c) != worstRow.Status__c ? r : worstRow;
            }
        }
        if (rows.isEmpty()) {
            t.value = 'Not checked';
            t.detail = 'Checked nightly, or Check now';
            return t;
        }
        String status = worstRow == null ? RlyCredentialRows.OK : worstRow.Status__c;
        t.value = status == RlyCredentialRows.OK ? 'OK' : counts.get(status) + ' ' + status.toLowerCase();
        t.detail = worstRow == null ? rows.size() + (rows.size() == 1 ? ' credential' : ' credentials') : worstRow.Name + daysText(worstRow);
        t.tone = status == RlyCredentialRows.OK ? RlyPipelineSummary.TONE_OK
            : (status == RlyCredentialRows.EXPIRING ? RlyPipelineSummary.TONE_WARN : RlyPipelineSummary.TONE_BAD);
        return t;
    }

    /**
     * @description The Orgs section's dot: red when an org can't sign in, amber when one isn't checked yet.
     * @param orgs every registered org
     * @return the tone
     */
    public static String orgsTone(List<RLY_Org__c> orgs) {
        String tone = orgs.isEmpty() ? RlyPipelineSummary.TONE_NONE : RlyPipelineSummary.TONE_OK;
        for (RLY_Org__c o : orgs) {
            tone = RlyPipelineSummary.worst(tone, o.Status__c == FAILED ? RlyPipelineSummary.TONE_BAD
                : (o.Status__c == CONNECTED ? RlyPipelineSummary.TONE_OK : RlyPipelineSummary.TONE_WARN));
        }
        return tone;
    }

    private static void signInLine(RlyPipelineSummary.Tile t, List<RLY_Org__c> onRoute, List<String> warnings) {
        List<String> failed = new List<String>();
        Integer unchecked = 0;
        for (RLY_Org__c o : onRoute) {
            if (o.Status__c == FAILED) {
                failed.add(o.Name);
            } else if (o.Status__c != CONNECTED) {
                unchecked++;
            }
        }
        String count = onRoute.size() + (onRoute.size() == 1 ? ' org' : ' orgs');
        if (!failed.isEmpty()) {
            t.detail = String.join(failed, ', ') + ' can\'t sign in';
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

    private static RlyPipelineSummary.Problem credentialProblem(RLY_Credential_Status__c r) {
        String tone = r.Status__c == RlyCredentialRows.EXPIRING ? RlyPipelineSummary.TONE_WARN : RlyPipelineSummary.TONE_BAD;
        String tag = r.Days_Left__c != null && r.Days_Left__c >= 0 ? r.Days_Left__c.intValue() + ' days' : r.Status__c;
        RlyPipelineSummary.Problem p = problem(tag, tone, r.Name + (String.isBlank(r.Kind__c) ? '' : ' (' + r.Kind__c.toLowerCase() + ')'));
        p.expiresOn = r.Expires_On__c;
        return p;
    }

    private static String daysText(RLY_Credential_Status__c r) {
        return r.Days_Left__c != null && r.Days_Left__c >= 0 ? ' · ' + r.Days_Left__c.intValue() + ' days' : ' · ' + r.Status__c.toLowerCase();
    }

    private static RlyPipelineSummary.Problem problem(String tag, String tone, String text) {
        RlyPipelineSummary.Problem p = new RlyPipelineSummary.Problem();
        p.tag = tag;
        p.tone = tone;
        p.text = text;
        return p;
    }

    private static RlyPipelineSummary.Tile tile(String key, String label, String section) {
        RlyPipelineSummary.Tile t = new RlyPipelineSummary.Tile();
        t.key = key;
        t.label = label;
        t.section = section;
        return t;
    }
}
