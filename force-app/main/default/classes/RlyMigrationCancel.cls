/**
 * @description Open releases at Switch now (build 54): the admin chose "Cancel the N open releases and switch". Every
 * release still open on the old connection becomes Cancelled, with a History event and the reason on the release; on the
 * old provider its pull or merge request gets a comment and is closed, and its Slack card is edited the way a rejection
 * edits it. The pull request and the card are best effort: a failure is kept on the release and in the result, and never
 * stops the switch. A pipeline run still going is not stopped (no provider call does that); it is named in the result.
 * prepare makes the callouts (no DML), save writes everything after them. Releases beyond what one request can call
 * out for are still cancelled, with their pull request left open and said so.
 */
public with sharing class RlyMigrationCancel {

    /** @description The release status. */
    public static final String CANCELLED = 'Cancelled';
    /** @description The History event type. */
    public static final String EVENT = 'Cancelled';

    // Kept back for the rest of the switch (the saves, the view read again) and the first guess of one release's use.
    @TestVisible private static Integer calloutsKept = 5;
    private static final Integer QUERIES_KEPT = 35;
    private static final Integer FIRST_GUESS = 4;

    // What one release used, the most seen so far: the next one is only started when that much is left.
    private Integer calloutsEach = FIRST_GUESS;
    private Integer queriesEach = FIRST_GUESS;

    /** @description What prepare did, for save. */
    public class Plan {
        /** @description Releases read in full and changed: saved with RlyReleaseStore.saveAll. */
        public List<RLY_Release__c> full = new List<RLY_Release__c>();
        /** @description Releases beyond the request's callouts: only their status and reason are saved. */
        public List<RLY_Release__c> light = new List<RLY_Release__c>();
        /** @description One row per release, for the migration and the report. */
        public List<RlyMigrationView.CancelledRelease> rows = new List<RlyMigrationView.CancelledRelease>();
        /** @description The old provider's name. */
        public String oldLabel;
    }

    /** @description The two providers and the migration, for the words. */
    public class Move {
        /** @description The old provider (GitHub). */
        public String oldLabel;
        /** @description The new provider (GitLab). */
        public String newLabel;
        /** @description MIG-… */
        public String migrationId;
    }

    /** @description The words of one cancellation: the reason on the release and the comment on its pull request. */
    public class Words {
        /** @description Error_Message__c: why it was cancelled. */
        public String reason;
        /** @description The comment posted on the pull or merge request before it is closed. */
        public String prComment;
    }

    /**
     * @description Cancels one release, read in full by RlyReleaseStore (build 54, also the release page's Cancel release):
     * comments on its pull or merge request and closes it (best effort; a merged one is left as it is), sets it Cancelled
     * with the reason, and edits its Slack card. Callouts only: the caller adds the History event and saves after.
     * @param rel the release
     * @param w the reason and the comment
     * @return what couldn't be done on the pull request (empty when it worked or there was none)
     */
    public static List<String> cancelOne(RLY_Release__c rel, Words w) {
        RLY_Release__c before = RlySlackCardState.snapshot(rel);
        List<String> problems = new List<String>();
        if (rel.PR_Number__c != null && String.isBlank(rel.Merge_Commit__c)) {
            problems = RlyPullRequestClose.closeWithComment(rel, w.prComment.left(1500));
        }
        rel.Status__c = CANCELLED;
        rel.Error_Message__c = (w.reason + (problems.isEmpty() ? '' : ' But ' + String.join(problems, '; ') + '.')).left(2000);
        RlySlackCardSync.notifyChange(before, rel);
        return problems;
    }

    /**
     * @description Refuses when a release is open that the admin didn't confirm (it was raised after the page was read).
     * @param open the releases open now
     * @param confirmedIds the releases the page showed when the admin chose
     */
    public static void requireConfirmed(List<RlyMigrationView.OpenRelease> open, List<Id> confirmedIds) {
        Set<Id> confirmed = confirmedIds == null ? new Set<Id>() : new Set<Id>(confirmedIds);
        List<String> unseen = new List<String>();
        for (RlyMigrationView.OpenRelease o : open) {
            if (!confirmed.contains(o.id)) {
                unseen.add(o.name);
            }
        }
        if (!unseen.isEmpty()) {
            throw new RlyReleaseException(String.join(unseen, ', ') + (unseen.size() == 1 ? ' was' : ' were')
                + ' opened after you chose. Read the list again and choose again.');
        }
    }

    /**
     * @description The callouts: each release's pull request closed with a comment and its Slack card edited. No DML.
     * @param open the releases to cancel
     * @param mv the providers and the migration
     * @return what to save
     */
    public static Plan prepare(List<RlyMigrationView.OpenRelease> open, Move mv) {
        RlyMigrationCancel budget = new RlyMigrationCancel();
        Plan p = new Plan();
        p.oldLabel = mv.oldLabel;
        for (RlyMigrationView.OpenRelease o : open) {
            RlyMigrationView.CancelledRelease row = rowOf(o);
            RLY_Release__c rel = budget.roomForOne() ? budget.cancelFully(o, mv, row) : null;
            if (rel != null) {
                p.full.add(rel);
            } else {
                rel = lightOf(o, mv, row);
                p.light.add(rel);
            }
            RlyReleaseLog.add(rel, EVENT, 'Cancelled by the move from ' + mv.oldLabel + ' to ' + mv.newLabel + ' by ' + UserInfo.getName())
                .byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE).withReference(o.url);
            p.rows.add(row);
        }
        return p;
    }

    /**
     * @description Saves the cancelled releases, their History and the Slack result, after every callout.
     * @param p what prepare did
     */
    public static void save(Plan p) {
        RlyMigrationStore.cancelReleases(p.light);
        RlyReleaseStore.saveAll(p.full);
        RlyReleaseLog.flush();
        RlySlack.saveResults();
    }

    // Beyond the request's callouts: only the status and the reason; the pull request and the Slack card are left as they are.
    private static RLY_Release__c lightOf(RlyMigrationView.OpenRelease o, Move mv, RlyMigrationView.CancelledRelease row) {
        String left = String.isBlank(o.url) ? 'Its Slack card was not edited (too many releases for one click).'
            : 'Its pull request was left open in ' + mv.oldLabel + ' (too many releases for one click): close it there.';
        row.note = left;
        return new RLY_Release__c(Id = o.id, Status__c = CANCELLED, Error_Message__c = (reasonOf(o, mv) + ' ' + left).left(2000));
    }

    private static String reasonOf(RlyMigrationView.OpenRelease o, Move mv) {
        return 'Cancelled by the move to ' + mv.newLabel + ' (' + mv.migrationId + ').'
            + (o.running == true ? ' Its pipeline run was still going in ' + mv.oldLabel + '.' : '');
    }

    private static RlyMigrationView.CancelledRelease rowOf(RlyMigrationView.OpenRelease o) {
        RlyMigrationView.CancelledRelease row = new RlyMigrationView.CancelledRelease();
        row.id = o.id;
        row.name = o.name;
        row.title = o.title;
        row.before = o.status;
        row.url = o.url;
        row.running = o.running == true;
        return row;
    }

    // Enough callouts and queries left for one more release, as much as the hungriest one so far, and the rest of the switch.
    private Boolean roomForOne() {
        return Limits.getLimitCallouts() - Limits.getCallouts() >= calloutsEach + calloutsKept
            && Limits.getLimitQueries() - Limits.getQueries() >= queriesEach + QUERIES_KEPT;
    }

    // Reads the release, closes its pull request with the comment, sets it Cancelled and edits its Slack card.
    private RLY_Release__c cancelFully(RlyMigrationView.OpenRelease o, Move mv, RlyMigrationView.CancelledRelease row) {
        Integer calloutsBefore = Limits.getCallouts();
        Integer queriesBefore = Limits.getQueries();
        RLY_Release__c rel = RlyReleaseStore.release(o.id);
        if (rel == null) {
            return null;
        }
        Words w = new Words();
        w.reason = reasonOf(o, mv);
        w.prComment = 'Cancelled in Release Relay: the hub moved to ' + mv.newLabel + '.';
        Boolean closing = rel.PR_Number__c != null && String.isBlank(rel.Merge_Commit__c);
        List<String> problems = cancelOne(rel, w);
        row.closed = closing && !String.join(problems, ' ').contains('couldn\'t be closed');
        row.note = problems.isEmpty() ? null : String.join(problems, '; ');
        calloutsEach = Math.max(calloutsEach, Limits.getCallouts() - calloutsBefore);
        queriesEach = Math.max(queriesEach, Limits.getQueries() - queriesBefore);
        return rel;
    }
}
