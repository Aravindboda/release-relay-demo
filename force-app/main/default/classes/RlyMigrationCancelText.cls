/**
 * @description The words for releases Switch now cancelled (build 54, RlyMigrationCancel): the Who did what line and the
 * Migration report's columns. No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationCancelText {

    private static final Integer NAMES_LISTED = 40;

    /**
     * @description The Who did what line: the releases, the runs still going and the pull requests closed.
     * @param p what RlyMigrationCancel.prepare did
     * @return the line
     */
    public static String summary(RlyMigrationCancel.Plan p) {
        List<String> names = new List<String>();
        List<String> problems = new List<String>();
        for (RlyMigrationView.CancelledRelease r : p.rows) {
            if (names.size() < NAMES_LISTED) {
                names.add(r.name + (r.running ? ' (run going)' : ''));
            }
            if (String.isNotBlank(r.note)) {
                problems.add(r.name + ': ' + r.note);
            }
        }
        Integer more = p.rows.size() - names.size();
        return 'Cancelled ' + p.rows.size() + ' open release' + (p.rows.size() == 1 ? '' : 's') + ' on ' + p.oldLabel + ': '
            + String.join(names, ', ') + (more > 0 ? ' and ' + more + ' more' : '') + '. ' + closedText(p.rows)
            + (problems.isEmpty() ? '' : ' (' + String.join(problems, '; ') + ')') + '.';
    }

    /**
     * @description A cancelled release's pull request in words: its link and closed or not, or none.
     * @param r the release as kept
     * @return the words
     */
    public static String pullRequestText(RlyMigrationView.CancelledRelease r) {
        return String.isBlank(r.url) ? 'none' : r.url + (r.closed ? ' closed' : ' not closed');
    }

    /**
     * @description A cancelled release's notes: a run that was going, and what couldn't be done.
     * @param r the release as kept
     * @return the notes, or blank
     */
    public static String noteText(RlyMigrationView.CancelledRelease r) {
        List<String> parts = new List<String>();
        if (r.running == true) {
            parts.add('a pipeline run was going');
        }
        if (String.isNotBlank(r.note)) {
            parts.add(r.note);
        }
        return String.join(parts, ' · ');
    }

    private static String closedText(List<RlyMigrationView.CancelledRelease> rows) {
        Integer withPr = 0;
        Integer closed = 0;
        for (RlyMigrationView.CancelledRelease r : rows) {
            withPr += String.isBlank(r.url) ? 0 : 1;
            closed += r.closed ? 1 : 0;
        }
        return 'Pull requests closed: ' + closed + ' of ' + withPr;
    }
}
