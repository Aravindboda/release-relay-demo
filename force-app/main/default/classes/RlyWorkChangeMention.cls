/**
 * @description Work items (build 48): the ServiceNow change gate's "Change must mention the release". An approved
 * change in its window opens the gate only when its short description or description names the release (the whole
 * number, any case: REL-0005 doesn't match REL-00052), unless the tracker's Change_Mentions_Release__c is off. So a
 * change approved for other work can't let this release into production.
 */
public with sharing class RlyWorkChangeMention {

    private static final List<String> FIELDS = new List<String>{ 'short_description', 'description' };

    /**
     * @description The change as the gate sees it: an allowed change that doesn't name the release isn't allowed.
     * @param c the change read from ServiceNow (RlyWorkTracker.change)
     * @param tracker the change's tracker
     * @param releaseName the release (REL-00052)
     * @return the change
     */
    public static RlyWorkTypes.Change checked(RlyWorkTypes.Change c, RLY_Work_Tracker__c tracker, String releaseName) {
        if (!c.allowed || tracker == null || tracker.Change_Mentions_Release__c == false || mentions(c.record, releaseName)) {
            return c;
        }
        c.allowed = false;
        Object changeNo = c.record.get('number');
        c.message = (changeNo == null ? 'The change' : String.valueOf(changeNo)) + ' is approved but doesn\'t mention ' + releaseName
            + ': add the release number to the change\'s short description or description.';
        return c;
    }

    /**
     * @description Whether a change request names the release in its short description or description.
     * @param rec the change request
     * @param releaseName the release
     * @return true when it does
     */
    public static Boolean mentions(Map<String, Object> rec, String releaseName) {
        if (rec == null || String.isBlank(releaseName)) {
            return false;
        }
        Pattern p = Pattern.compile('(?i)(?<![A-Za-z0-9])' + Pattern.quote(releaseName.trim()) + '(?![0-9])');
        for (String field : FIELDS) {
            Object v = rec.get(field);
            if (v != null && p.matcher(String.valueOf(v)).find()) {
                return true;
            }
        }
        return false;
    }
}
