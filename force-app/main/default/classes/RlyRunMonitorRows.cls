/**
 * @description Turns pipeline run records (RLY_Pipeline_Run__c, read by RlyRunMonitorStore) into the Pipeline Monitor's
 * run rows (RlyRunMonitorViews.Run): the GitHub run number and attempt from Run_Id__c, the release's number (or the
 * request id when the release isn't in this org), and the jobs list from Steps__c.
 */
public with sharing class RlyRunMonitorRows {

    /**
     * @description Run rows, in the records' order.
     * @param records the runs
     * @return the rows
     */
    public static List<RlyRunMonitorViews.Run> rows(List<RLY_Pipeline_Run__c> records) {
        List<RlyRunMonitorViews.Run> out = new List<RlyRunMonitorViews.Run>();
        for (RLY_Pipeline_Run__c r : records) {
            out.add(row(r));
        }
        return out;
    }

    /**
     * @description One run row.
     * @param r the run, with Release__r
     * @return the row
     */
    public static RlyRunMonitorViews.Run row(RLY_Pipeline_Run__c r) {
        RlyRunMonitorViews.Run v = new RlyRunMonitorViews.Run();
        v.id = r.Id;
        v.runKey = r.Run_Id__c;
        String key = r.Run_Id__c == null ? '' : r.Run_Id__c;
        v.runNumber = key.substringBefore('-');
        String attempt = key.substringAfter('-');
        v.attempt = attempt.isNumeric() ? Integer.valueOf(attempt) : 1;
        v.status = r.Status__c;
        v.active = RlyRunMonitorStore.ACTIVE.contains(r.Status__c);
        v.step = r.Workflow_Step__c;
        v.mode = r.Mode__c;
        v.branch = r.Branch__c;
        v.targetOrg = r.Target_Org__c;
        v.releaseId = r.Release__c;
        v.releaseName = r.Release__c != null ? r.Release__r.Name : r.Request_Id__c;
        v.releaseTitle = r.Release__c != null ? r.Release__r.Title__c : null;
        v.started = r.Started__c;
        v.finished = r.Finished__c;
        v.durationSeconds = r.Duration_Seconds__c == null ? null : r.Duration_Seconds__c.intValue();
        v.actor = r.Actor__c;
        v.runUrl = r.Run_Url__c;
        v.failure = r.Failure_Message__c;
        v.steps = steps(r.Steps__c);
        return v;
    }

    /**
     * @description The jobs saved as JSON ([{name, outcome, seconds}]); bad JSON gives none.
     * @param json Steps__c
     * @return the jobs
     */
    public static List<RlyRunMonitorViews.Step> steps(String json) {
        List<RlyRunMonitorViews.Step> out = new List<RlyRunMonitorViews.Step>();
        if (String.isBlank(json)) {
            return out;
        }
        try {
            for (RlyRunMonitorViews.Step s : (List<RlyRunMonitorViews.Step>) System.JSON.deserialize(json, List<RlyRunMonitorViews.Step>.class)) {
                if (String.isNotBlank(s.name)) {
                    out.add(s);
                }
            }
        } catch (JSONException e) {
            out.clear();
        }
        return out;
    }

    /**
     * @description The lane key of an org or a run's target: its GitHub environment or name, lower case.
     * @param name the environment or name
     * @return the key, or '' for blank
     */
    public static String key(String name) {
        return String.isBlank(name) ? '' : name.trim().toLowerCase();
    }
}
