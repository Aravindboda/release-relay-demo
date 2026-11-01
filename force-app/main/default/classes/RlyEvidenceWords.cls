/**
 * @description Words for the evidence document (RlyEvidenceTables): picklist values as plain words, and break points in
 * long words so the PDF renderer wraps them inside table cells.
 */
public with sharing class RlyEvidenceWords {

    private static final Integer LONG_WORD = 26;
    private static final Integer SLASH_RUN = 12;
    // The PDF renderer ignores zero-width break points, so a long word gets a real space where it may wrap.
    private static final String BREAK_POINT = ' ';
    // Column widths (percent) per table, by its header; a two-column table gives the value most of the width.
    private static final Map<String, List<Integer>> COLUMN_WIDTHS = new Map<String, List<Integer>>{
        'Item|Value' => new List<Integer>{ 28, 72 },
        'Change|Type|Name' => new List<Integer>{ 15, 25, 60 },
        'Severity|Rule|Where|Message' => new List<Integer>{ 9, 13, 38, 40 },
        'Org|Step|Timing|Status|Done by|Note' => new List<Integer>{ 10, 36, 13, 10, 17, 14 },
        'When|Event|Org|Who|Detail|Reference' => new List<Integer>{ 13, 13, 7, 15, 32, 20 }
    };

    /**
     * @description A picklist value as words: To_Do is "To do", After_Deploy is "After deploy".
     * @param value the API value
     * @return the words (null is empty)
     */
    public static String words(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String spaced = value.replace('_', ' ').toLowerCase();
        return spaced.left(1).toUpperCase() + spaced.substring(1);
    }

    /**
     * @description Adds break points to long words (links, file paths): after a / that ends a long enough run, and
     * every 26 characters, so a table cell wraps them instead of running into the next column. Deploy ids (18
     * characters) and other short words stay whole.
     * @param html escaped text
     * @return the text with break points
     */
    public static String breakable(String html) {
        List<String> words = new List<String>();
        for (String word : html.split(' ')) {
            words.add(word.length() <= LONG_WORD ? word : breakWord(word));
        }
        return String.join(words, ' ');
    }

    private static String breakWord(String word) {
        String out = '';
        Integer run = 0;
        for (Integer i = 0; i < word.length(); i++) {
            String ch = word.substring(i, i + 1);
            out += ch;
            run++;
            if ((ch == '/' && run >= SLASH_RUN) || run >= LONG_WORD) {
                out += BREAK_POINT;
                run = 0;
            }
        }
        return out;
    }

    /**
     * @description The column widths for a table's header (percent), or an empty list to let the renderer share them.
     * @param header the header cells
     * @return the widths
     */
    public static List<Integer> widths(List<String> header) {
        List<Integer> w = header == null ? null : COLUMN_WIDTHS.get(String.join(header, '|'));
        return w == null ? new List<Integer>() : w;
    }
}
