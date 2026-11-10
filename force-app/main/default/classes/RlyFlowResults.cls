/**
 * @description Reads a release's flow activation results (RLY_Release__c.Flow_Results__c, JSON
 * [{org, flow, version, status, message}], written by RlyFlowActivation) for the release page's Flows section, the
 * evidence document and the change request summary. Each result carries the flow's After deploy choice
 * (Flow_Actions__c).
 */
public with sharing class RlyFlowResults {

    /** @description One flow in one org, as the release page shows it. */
    public class FlowResult {
        /** @description The flow's API name. */
        @AuraEnabled public String flow;
        /** @description The org's name. */
        @AuraEnabled public String org;
        /** @description The version now active (or the one that couldn't be activated), or null. */
        @AuraEnabled public Integer version;
        /** @description Activated, Already active or Failed. */
        @AuraEnabled public String status;
        /** @description Why it failed, or null. */
        @AuraEnabled public String message;
        /** @description The After deploy choice: Keep, Activate or Inactive. */
        @AuraEnabled public String choice;
    }

    /**
     * @description The stored results as a list of maps (unreadable or blank: empty).
     * @param resultsJson Flow_Results__c
     * @return the entries
     */
    public static List<Object> parse(String resultsJson) {
        List<Object> out = new List<Object>();
        if (String.isBlank(resultsJson)) {
            return out;
        }
        try {
            Object o = JSON.deserializeUntyped(resultsJson);
            for (Object e : o instanceof List<Object> ? (List<Object>) o : new List<Object>()) {
                if (e instanceof Map<String, Object>) {
                    out.add(e);
                }
            }
        } catch (Exception e) {
            return new List<Object>();
        }
        return out;
    }

    /**
     * @description A release's results, with each flow's choice, by flow then org.
     * @param rel the release, with Flow_Results__c and Flow_Actions__c
     * @return the results
     */
    public static List<FlowResult> forRelease(RLY_Release__c rel) {
        Map<String, String> choices = new Map<String, String>();
        for (RlyFlowChoices.FlowChoice c : RlyFlowChoices.fromRelease(rel)) {
            choices.put(c.name, c.choice);
        }
        List<FlowResult> out = new List<FlowResult>();
        for (Object o : parse(rel.Flow_Results__c)) {
            Map<String, Object> m = (Map<String, Object>) o;
            FlowResult r = new FlowResult();
            r.flow = RlyEvidenceText.str(m.get('flow'));
            r.org = RlyEvidenceText.str(m.get('org'));
            r.version = m.get('version') == null ? null : Integer.valueOf(String.valueOf(m.get('version')).substringBefore('.'));
            r.status = RlyEvidenceText.str(m.get('status'));
            r.message = RlyEvidenceText.str(m.get('message'));
            r.choice = choices.containsKey(r.flow) ? choices.get(r.flow) : RlyFlowChoices.CHOICE_ACTIVATE;
            out.add(r);
        }
        return out;
    }

    /**
     * @description "Case_Escalation · SIT v4 active" or "Case_Escalation · PROD failed: reason".
     * @param r the result
     * @return the line
     */
    public static String line(FlowResult r) {
        if (r.status == RlyFlowActivation.FAILED) {
            return r.flow + ' · ' + r.org + ' failed' + (r.message == null ? '' : ': ' + r.message);
        }
        return r.flow + ' · ' + r.org + (r.version == null ? '' : ' v' + r.version) + ' active'
            + (r.status == RlyFlowActivation.ACTIVATED ? ' (activated by the hub)' : '');
    }
}
