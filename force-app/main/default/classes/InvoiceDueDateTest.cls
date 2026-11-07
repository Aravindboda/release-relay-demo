/**
 * @description Tests for InvoiceDueDate.
 */
@isTest
private class InvoiceDueDateTest {
    @isTest
    static void dueDateFollowsTerms() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Date invoiced = Date.newInstance(2026, 11, 3);
            System.assertEquals(Date.newInstance(2026, 11, 18), InvoiceDueDate.dueDate(invoiced, 'Net 15'), 'Net 15 adds 15 days');
            System.assertEquals(Date.newInstance(2027, 1, 2), InvoiceDueDate.dueDate(invoiced, 'net60'), 'Net 60 in any case or spacing');
            System.assertEquals(invoiced, InvoiceDueDate.dueDate(invoiced, 'Due on receipt'), 'Due on receipt is the same day');
            System.assertEquals(30, InvoiceDueDate.daysFor(null), 'Blank terms mean Net 30');
            System.assertEquals(null, InvoiceDueDate.dueDate(null, 'Net 30'), 'No invoice date, no due date');
        }
    }
}