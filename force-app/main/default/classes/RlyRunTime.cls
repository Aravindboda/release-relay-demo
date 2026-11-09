/**
 * @description Times of pipeline runs (build 56, D24): the provider's ISO 8601 times, and whether a run is older than
 * the release's request.
 */
public with sharing class RlyRunTime {

    /**
     * @description Whether the run belongs to an earlier request: created more than a minute before the release asked
     * for its run (a minute allows for the clocks of Salesforce and the Git provider to differ).
     * @param run the newest run with the release's title
     * @param rel the release, with Checks_Requested__c
     * @return true when the run is older than the request
     */
    public static Boolean startedBeforeRequest(RlyGit.Run run, RLY_Release__c rel) {
        return run.createdAt != null && rel.Checks_Requested__c != null && run.createdAt < rel.Checks_Requested__c.addSeconds(-60);
    }

    /**
     * @description A provider's ISO 8601 time (2026-11-09T23:20:18Z or with milliseconds or an offset), or null.
     * @param value the text
     * @return the time, or null when blank or unreadable
     */
    public static Datetime toTime(Object value) {
        String text = value == null ? '' : String.valueOf(value).trim();
        if (String.isBlank(text)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}
