/**
 * @description The Credentials page's Git token row learns whether the token can close and comment on pull requests
 * (build 52). The nightly pass makes one call per token and can't tell; a rejected release closes its pull request
 * with a comment, so that close is the check: refused for the token (HTTP 403) turns the row Failed with what to give
 * the token, and the nightly pass keeps that note until a later close and comment work, which clears it. No extra
 * callouts; saved after the release (no callout follows).
 */
public with sharing class RlyCredentialPrAccess {

    /** @description What the Git token row says when a pull request close or comment was refused. */
    public static final String PR_ACCESS_TEXT = 'The token can\'t close or comment on pull requests: give it Pull requests: Read and write.';
    /** @description The same for GitLab, whose merge requests need the api scope. */
    public static final String MR_ACCESS_TEXT = 'The token can\'t close or comment on merge requests: give it the api scope.';
    /** @description What the row says once a close and comment work again. */
    public static final String WORKS_AGAIN = 'Pull requests close and take comments again; the token\'s expiry is read on the next pass.';

    private static final String ACCESS_MARK = 'The token can\'t close or comment on ';
    private static final String NOTE_END = ')';
    private static final String REFUSED_CODE = 'HTTP 403';

    /** @description Why the last record failed, or null (the rejection never fails for it). */
    @TestVisible private static String lastProblem;

    /**
     * @description Records the outcome of a rejected release's pull request close on its connection's Git token row.
     * @param rel the release (saved already)
     * @param problems what closeWithComment returned, or null when the release had no pull request
     */
    public static void afterClose(RLY_Release__c rel, List<String> problems) {
        String outcome = outcomeOf(problems);
        if (outcome == null) {
            return;
        }
        try {
            RLY_Git_Connection__c conn = RlyReleaseStore.gitFor(rel);
            if (conn == null || conn.Id == null) {
                return;
            }
            RLY_Credential_Status__c r = rowAfter(conn, RlyCredentialStore.rowByKey(RlyCredentialHubChecks.gitKey(conn)), problems);
            if (r != null) {
                RlyCredentialStore.save(new List<RLY_Credential_Status__c>{ r }, null);
            }
        } catch (Exception e) {
            lastProblem = e.getMessage();
        }
    }

    /**
     * @description The outcome of a close: refused (a 403 on the comment or the close), worked (no problem), or null
     * (no pull request, or something else went wrong: nothing is recorded).
     * @param problems what closeWithComment returned, or null
     * @return refused, worked or null
     */
    public static String outcomeOf(List<String> problems) {
        if (problems == null) {
            return null;
        }
        if (problems.isEmpty()) {
            return 'worked';
        }
        for (String p : problems) {
            if (p != null && p.contains(REFUSED_CODE)) {
                return 'refused';
            }
        }
        return null;
    }

    /**
     * @description The Git token row after a close: Failed with the note when refused; OK without it when the close
     * worked and the row had one; null when nothing changes.
     * @param conn the connection
     * @param saved the saved row, or null
     * @param problems what closeWithComment returned
     * @return the row to save, or null
     */
    public static RLY_Credential_Status__c rowAfter(RLY_Git_Connection__c conn, RLY_Credential_Status__c saved, List<String> problems) {
        String outcome = outcomeOf(problems);
        if (outcome == null || (outcome == 'worked' && !hasNote(saved))) {
            return null;
        }
        RLY_Credential_Status__c r = RlyCredentialRows.row(RlyCredentialHubChecks.gitKey(conn), RlyCredentialRows.KIND_GIT,
            saved != null ? saved.Name : conn.Provider__c + ' · ' + conn.Repository__c);
        r.Expires_On__c = saved == null ? null : saved.Expires_On__c;
        r.Last_OK__c = saved == null ? null : saved.Last_OK__c;
        if (outcome == 'worked') {
            return RlyCredentialRows.mark(r, RlyCredentialRows.OK, WORKS_AGAIN);
        }
        String text = conn.Provider__c == 'GitLab' ? MR_ACCESS_TEXT : PR_ACCESS_TEXT;
        String said = ' ' + String.join(problems, '; ').replace(NOTE_END, ']').left(300);
        return RlyCredentialRows.mark(r, RlyCredentialRows.FAILED,
            text.removeEnd('.') + ' (refused ' + System.now().format('d MMM yyyy') + NOTE_END + '.' + said);
    }

    /**
     * @description Whether a saved Git token row carries a refused close.
     * @param saved the saved row, or null
     * @return true when it does
     */
    public static Boolean hasNote(RLY_Credential_Status__c saved) {
        return saved != null && saved.Message__c != null && saved.Message__c.contains(ACCESS_MARK);
    }

    /**
     * @description The nightly Git token row keeps a refused close (the pass makes no call that could tell it's fixed):
     * the row turns Failed with the note first.
     * @param fresh the row the nightly check built
     * @param saved the saved row, or null
     * @return the row
     */
    public static RLY_Credential_Status__c withNote(RLY_Credential_Status__c fresh, RLY_Credential_Status__c saved) {
        if (!hasNote(saved)) {
            return fresh;
        }
        String note = saved.Message__c.substring(saved.Message__c.indexOf(ACCESS_MARK)).substringBefore(NOTE_END) + NOTE_END;
        return RlyCredentialRows.mark(fresh, RlyCredentialRows.FAILED, note + '. ' + (fresh.Message__c == null ? '' : fresh.Message__c));
    }
}
