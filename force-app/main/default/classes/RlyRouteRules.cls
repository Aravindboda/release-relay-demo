/**
 * @description The route built from the registered orgs: stages in order (by Stage_Order__c, unordered last by
 * name, the hub always last) and the warnings about what's missing.
 */
public with sharing class RlyRouteRules {

    /**
     * @description Stages by Stage_Order__c (unordered last, by name); the hub always last.
     * @param stages the stages and the hub, by name
     * @return the stages in route order
     */
    public static List<RLY_Org__c> ordered(List<RLY_Org__c> stages) {
        List<RLY_Org__c> withOrder = new List<RLY_Org__c>();
        List<RLY_Org__c> rest = new List<RLY_Org__c>();
        RLY_Org__c hub;
        for (RLY_Org__c o : stages) {
            if (o.Role__c == 'Hub') {
                hub = o;
            } else if (o.Stage_Order__c != null) {
                withOrder.add(o);
            } else {
                rest.add(o);
            }
        }
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        while (!withOrder.isEmpty()) {
            out.add(withOrder.remove(lowest(withOrder)));
        }
        out.addAll(rest);
        if (hub != null) {
            out.add(hub);
        }
        return out;
    }

    // Position of the stage with the lowest order (the first of equals).
    private static Integer lowest(List<RLY_Org__c> withOrder) {
        Integer best = 0;
        for (Integer i = 1; i < withOrder.size(); i++) {
            if (withOrder[i].Stage_Order__c < withOrder[best].Stage_Order__c) {
                best = i;
            }
        }
        return best;
    }

    /**
     * @description What's missing from the route: stages, branches, Git environments, the hub, developer orgs.
     * @param developers the developer orgs
     * @param stages the stages and the hub
     * @return the warnings
     */
    public static List<String> warnings(List<RLY_Org__c> developers, List<RLY_Org__c> stages) {
        List<String> w = new List<String>();
        if (stages.isEmpty()) {
            w.add('Register at least one stage (for example SIT) for releases to go to.');
        }
        List<RLY_Org__c> everyOrg = new List<RLY_Org__c>(stages);
        everyOrg.addAll(developers);
        Set<String> branches = new Set<String>();
        for (RLY_Org__c o : everyOrg) {
            addOrgWarnings(o, branches, w);
        }
        if (!stages.isEmpty() && !hasHub(everyOrg)) {
            w.add('Register this hub with the role Hub, so releases can be promoted to production.');
        }
        if (developers.isEmpty()) {
            w.add('Register at least one developer org to raise releases from.');
        }
        return w;
    }

    /**
     * @description Whether an org is on the route: a stage or the hub (not a developer or back promote org).
     * @param o the org
     * @return true for stages and the hub
     */
    public static Boolean isStage(RLY_Org__c o) {
        return o.Role__c == 'Stage' || o.Role__c == 'Hub';
    }

    private static void addOrgWarnings(RLY_Org__c o, Set<String> branches, List<String> w) {
        if (String.isBlank(o.Branch__c)) {
            w.add(o.Name + ' has no branch: edit it and set its Git branch.');
        } else if (!branches.add(o.Branch__c.trim())) {
            w.add('Branch ' + o.Branch__c + ' is used by more than one org: each org needs its own branch.');
        }
        if (String.isBlank(o.Git_Environment__c)) {
            w.add(o.Name + ' has no Git environment: the pipeline needs it to sign in to that org.');
        }
    }

    private static Boolean hasHub(List<RLY_Org__c> orgs) {
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Hub') {
                return true;
            }
        }
        return false;
    }
}
