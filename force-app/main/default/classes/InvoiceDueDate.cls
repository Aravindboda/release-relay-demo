/**
 * @description Works out an invoice's due date from its payment terms (Net 15, Net 30, Net 45, Net 60, Due on receipt).
 */
public with sharing class InvoiceDueDate {
    private static final Map<String, Integer> TERM_DAYS = new Map<String, Integer>{
        'NET15' => 15, 'NET30' => 30, 'NET45' => 45, 'NET60' => 60, 'DUEONRECEIPT' => 0
    };

    /**
     * @description The due date: the invoice date plus the days the payment terms allow.
     * @param invoiceDate the date the invoice was raised
     * @param terms the payment terms, for example Net 30
     * @return the due date, or null when the invoice date is missing
     */
    public static Date dueDate(Date invoiceDate, String terms) {
        if (invoiceDate == null) {
            return null;
        }
        return invoiceDate.addDays(daysFor(terms));
    }

    /**
     * @description Days allowed by the payment terms; blank or unknown terms mean Net 30.
     * @param terms the payment terms, any case or spacing
     * @return the number of days
     */
    public static Integer daysFor(String terms) {
        String key = terms == null ? '' : terms.deleteWhitespace().toUpperCase();
        Integer days = TERM_DAYS.get(key);
        return days == null ? 30 : days;
    }
}