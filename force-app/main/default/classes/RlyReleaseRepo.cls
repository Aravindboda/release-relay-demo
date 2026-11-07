/**
 * @description Several Git connections (build 45): which repository each release lives in, for the release list's
 * GitHub / GitLab badge and its Repository filter. A release's own Git_Connection__c, else its source org's (not the
 * hub's), else the hub's main connection. Read in memory from the list's rows: one query for the connections.
 */
public with sharing class RlyReleaseRepo {

    /**
     * @description A release's connection Id, in memory.
     * @param r the release
     * @param mainId the main connection's Id
     * @return the connection's Id (the main one when nothing else is known)
     */
    public static Id connectionIdOf(RLY_Release__c r, Id mainId) {
        Map<String, Object> present = r.getPopulatedFieldsAsMap();
        if (present.get('Git_Connection__c') != null) {
            return (Id) present.get('Git_Connection__c');
        }
        Object source = present.get('Source_Org__r');
        return source instanceof RLY_Org__c ? RlyConnectionRoutes.connectionIdOf((RLY_Org__c) source, mainId) : mainId;
    }

    /**
     * @description Fills each row's repository: connection, provider name and repository.
     * @param rows the rows, in the releases' order
     * @param rels the releases
     */
    public static void fill(List<RlyReleasesController.Row> rows, List<RLY_Release__c> rels) {
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        if (conns.isEmpty()) {
            return;
        }
        Map<Id, RLY_Git_Connection__c> byId = new Map<Id, RLY_Git_Connection__c>(conns);
        Map<Id, String> labels = new Map<Id, String>();
        for (RLY_Git_Connection__c c : conns) {
            String label = RlyGitName.labelFor(c);
            labels.put(c.Id, label == null ? c.Provider__c : label);
        }
        for (Integer i = 0; i < rows.size() && i < rels.size(); i++) {
            Id connectionId = connectionIdOf(rels[i], conns[0].Id);
            RLY_Git_Connection__c c = byId.containsKey(connectionId) ? byId.get(connectionId) : conns[0];
            rows[i].connectionId = c.Id;
            rows[i].provider = labels.get(c.Id);
            rows[i].repository = c.Repository__c;
        }
    }

    /**
     * @description Keeps the releases in one repository (the Repository filter).
     * @param rels the releases
     * @param connectionId the connection picked, or blank for every repository
     * @return the releases in it
     */
    public static List<RLY_Release__c> onlyIn(List<RLY_Release__c> rels, Id connectionId) {
        if (connectionId == null) {
            return rels;
        }
        RLY_Git_Connection__c main = RlyReleaseStore.git();
        Id mainId = main == null ? null : main.Id;
        List<RLY_Release__c> out = new List<RLY_Release__c>();
        for (RLY_Release__c r : rels) {
            if (connectionIdOf(r, mainId) == connectionId) {
                out.add(r);
            }
        }
        return out;
    }
}
