/**
 * @description Build 55: the rules of Edit a file (RlyFileEdit). Files can be edited while the release is open with its
 * pull request and no run is going (Checks failed or Ready for approval), by the person who raised it or an admin (as
 * Cancel release); an edit must be one of the release's files, not empty, not over MAX_CHARS, and change something.
 */
public with sharing class RlyFileEditRules {

    /** @description Statuses a file can be edited in (no run going). */
    public static final Set<String> EDITABLE = new Set<String>{ 'Checks failed', 'Ready for approval' };
    /** @description Largest file the page edits, in characters. */
    public static final Integer MAX_CHARS = 300000;

    /**
     * @description Why the current user can't edit the release's files now, or null when they can.
     * @param rel the release, with Status__c, PR_Number__c, Source_Branch__c and CreatedById
     * @return the reason, or null
     */
    public static String whyNot(RLY_Release__c rel) {
        if (rel == null || !EDITABLE.contains(rel.Status__c) || rel.PR_Number__c == null || String.isBlank(rel.Source_Branch__c)) {
            return 'Files can be edited while the release is open with its pull request and no run is going (Checks failed or Ready for approval).';
        }
        if (!RlyReleaseAccess.mayEditTickets(rel)) {
            return 'Only the person who raised ' + rel.Name + ' or an admin can edit its files.';
        }
        return null;
    }

    /**
     * @description Refuses an edit that isn't allowed now, isn't one of the release's files, or changes nothing (before
     * any callout).
     * @param rel the release
     * @param req the edit
     */
    public static void checkEdit(RLY_Release__c rel, RlyFileEdit.EditRequest req) {
        String why = whyNot(rel);
        if (why != null) {
            throw new RlyReleaseException(why);
        }
        if (req == null) {
            throw new RlyReleaseException('Nothing to save.');
        }
        RlyFileEditPaths.requirePath(RlyReleaseStore.items(rel.Id), req.path);
        checkContent(req);
    }

    // Not empty, not too large, and something changed.
    private static void checkContent(RlyFileEdit.EditRequest req) {
        if (String.isBlank(req.content) || req.content.length() > MAX_CHARS) {
            throw new RlyReleaseException('The file is empty or too large to save here.');
        }
        if (req.content.equals(req.expected)) {
            throw new RlyReleaseException('Nothing changed in ' + req.path + '.');
        }
    }

    /**
     * @description Whether two copies are the same text, line endings aside (null and blank alike).
     * @param a one copy
     * @param b the other
     * @return true when the same
     */
    public static Boolean sameText(String a, String b) {
        String x = a == null ? '' : a.replace('\r\n', '\n');
        String y = b == null ? '' : b.replace('\r\n', '\n');
        return x.equals(y);
    }
}
