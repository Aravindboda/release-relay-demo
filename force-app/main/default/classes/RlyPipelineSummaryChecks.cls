/**
 * @description Pipeline tab status strip (build 50): the Security tile (the last Repository security check, kept on
 * RLY_Run_Key__c) and the Credentials tile (the build 49 credential rows), and what Security &amp; credentials lists to
 * fix. No SOQL or DML of its own.
 */
public with sharing class RlyPipelineSummaryChecks {

    /**
     * @description The Security tile, from the last Repository security check kept on RLY_Run_Key__c; adds what to fix
     * (and run signing being off) to the problems.
     * @param key the RLY_Run_Key__c org default row
     * @param problems the summary's problems (added to)
     * @return the tile
     */
    public static RlyPipelineSummary.Tile security(RLY_Run_Key__c key, List<RlyPipelineSummary.Problem> problems) {
        RlyPipelineSummary.Tile t = RlyPipelineSummaryTiles.tile('security', 'Security', RlyPipelineSummary.SECURITY);
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
        RlyPipelineSummary.Tile t = RlyPipelineSummaryTiles.tile('credentials', 'Credentials', RlyPipelineSummary.SECURITY);
        if (rows.isEmpty()) {
            t.value = 'Not checked';
            t.detail = 'Checked nightly, or Check now';
            return t;
        }
        RLY_Credential_Status__c worstRow;
        for (RLY_Credential_Status__c r : rows) {
            t.checkedOn = t.checkedOn == null || (r.Last_Checked__c != null && r.Last_Checked__c > t.checkedOn) ? r.Last_Checked__c : t.checkedOn;
            if (RlyCredentialRows.ATTENTION.contains(r.Status__c)) {
                problems.add(credentialProblem(r));
                worstRow = worstRow == null || RlyCredentialRows.worse(worstRow.Status__c, r.Status__c) != worstRow.Status__c ? r : worstRow;
            }
        }
        credentialLine(t, worstRow, rows);
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
            tone = RlyPipelineSummary.worst(tone, o.Status__c == 'Failed' ? RlyPipelineSummary.TONE_BAD
                : (o.Status__c == 'Connected' ? RlyPipelineSummary.TONE_OK : RlyPipelineSummary.TONE_WARN));
        }
        return tone;
    }

    // The worst status in words ("1 expiring"), which credential and when; OK when nothing needs attention.
    private static void credentialLine(RlyPipelineSummary.Tile t, RLY_Credential_Status__c worstRow, List<RLY_Credential_Status__c> rows) {
        if (worstRow == null) {
            t.value = 'OK';
            t.detail = rows.size() + (rows.size() == 1 ? ' credential' : ' credentials');
            t.tone = RlyPipelineSummary.TONE_OK;
            return;
        }
        Integer n = 0;
        for (RLY_Credential_Status__c r : rows) {
            n += r.Status__c == worstRow.Status__c ? 1 : 0;
        }
        t.value = n + ' ' + worstRow.Status__c.toLowerCase();
        t.detail = worstRow.Name + daysText(worstRow);
        t.tone = worstRow.Status__c == RlyCredentialRows.EXPIRING ? RlyPipelineSummary.TONE_WARN : RlyPipelineSummary.TONE_BAD;
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
}
