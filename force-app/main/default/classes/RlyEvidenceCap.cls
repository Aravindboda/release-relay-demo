/**
 * @description Keeps the evidence PDF's long tables to a size the PDF renderer handles (RlyEvidenceHtml,
 * RlyEvidenceTables): at most MAX_ROWS rows, then one row saying how many more there are. Components keep the first
 * rows, the history its newest entries (the most recent steps matter most in an audit).
 */
public with sharing class RlyEvidenceCap {

    /** @description Most rows of a long table in the PDF; a row says how many more there are. */
    public static final Integer MAX_ROWS = 1000;

    /**
     * @description The first MAX_ROWS rows of a long table, then one row saying how many more there are.
     * @param rows the rows
     * @param width how many cells a row has
     * @param moreWords what the hidden rows are, for example "more components"
     * @return the rows to show
     */
    public static List<List<String>> capped(List<List<String>> rows, Integer width, String moreWords) {
        if (rows.size() <= MAX_ROWS) {
            return rows;
        }
        List<List<String>> out = new List<List<String>>();
        for (Integer i = 0; i < MAX_ROWS; i++) {
            out.add(rows[i]);
        }
        List<String> more = new List<String>{ '… and ' + (rows.size() - MAX_ROWS).format() + ' ' + moreWords };
        while (more.size() < width) {
            more.add('');
        }
        out.add(more);
        return out;
    }

    /**
     * @description The newest MAX_ROWS history entries, still oldest first.
     * @param events the history, oldest first
     * @return the entries to show
     */
    public static List<RLY_Release_Event__c> newest(List<RLY_Release_Event__c> events) {
        if (events.size() <= MAX_ROWS) {
            return events;
        }
        List<RLY_Release_Event__c> out = new List<RLY_Release_Event__c>();
        for (Integer i = events.size() - MAX_ROWS; i < events.size(); i++) {
            out.add(events[i]);
        }
        return out;
    }

    /**
     * @description The row that says how many earlier history entries aren't shown.
     * @param total how many entries the release has
     * @return the text
     */
    public static String earlierText(Integer total) {
        return (total - MAX_ROWS).format() + ' earlier entries aren\'t shown: the release page has the whole history.';
    }
}
