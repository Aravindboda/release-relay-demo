/**
 * @description The people and the page a pipeline run names (build 44, pipeline version 25): by (who raised the
 * release), approvedBy (who approved it, both approvers for two-approver orgs) and hubUrl (the release's page in the
 * hub). The pipeline shows them in the run's name and its job summary. No SOQL, DML or callouts.
 */
public with sharing class RlyRunPeople {

    /**
     * @description Who raised and approved the release and its page in the hub (build 44): by, approvedBy and hubUrl,
     * which the pipeline shows in the run's name and summary. Only fields the release was read with are used.
     * @param rel the release
     * @param options the options to add to
     */
    public static void addTo(RLY_Release__c rel, Map<String, Object> options) {
        String raisedBy = nameOf(rel, 'CreatedBy');
        if (String.isNotBlank(raisedBy)) {
            options.put('by', raisedBy);
        }
        List<String> approvers = new List<String>();
        for (String lookup : new List<String>{ 'Approved_By__r', 'Second_Approved_By__r' }) {
            String approver = nameOf(rel, lookup);
            if (String.isNotBlank(approver)) {
                approvers.add(approver);
            }
        }
        if (!approvers.isEmpty()) {
            options.put('approvedBy', String.join(approvers, ', '));
        }
        if (rel.Id != null) {
            options.put('hubUrl', URL.getOrgDomainUrl().toExternalForm() + '/lightning/r/RLY_Release__c/' + rel.Id + '/view');
        }
    }

    // A user lookup's name, when the release was read with it (no error when it wasn't).
    private static String nameOf(RLY_Release__c rel, String relationship) {
        Object related = rel.getPopulatedFieldsAsMap().get(relationship);
        if (!(related instanceof User)) {
            return null;
        }
        Object name = ((User) related).getPopulatedFieldsAsMap().get('Name');
        return name == null ? null : String.valueOf(name).left(80);
    }
}
