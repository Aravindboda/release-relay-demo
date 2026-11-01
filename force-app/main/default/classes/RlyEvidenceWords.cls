/**
 * @description Words for the evidence document (RlyEvidenceTables): picklist values as plain words, and break points in
 * long words so the PDF renderer wraps them inside table cells.
 */
public with sharing class RlyEvidenceWords {

    private static final Integer LONG_WORD = 30;
    private static final String BREAK_POINT = '&#8203;';

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
     * @description Adds break points to long words (links, deploy ids, file paths): after each / and every 30
     * characters, so a table cell wraps them instead of running off the page.
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
            run = ch == '/' ? 0 : run + 1;
            if (ch == '/' || run >= LONG_WORD) {
                out += BREAK_POINT;
                run = 0;
            }
        }
        return out;
    }
}
