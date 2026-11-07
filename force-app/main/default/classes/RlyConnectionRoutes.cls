/**
 * @description Several Git connections (build 45): which connection an org or a release is on, and each connection's
 * route. Every developer and stage org belongs to one connection; blank means the main one (the oldest active). The hub
 * belongs to every route: it is the last stop of each. A release lives in the repository it was raised in.
 */
public with sharing class RlyConnectionRoutes {

    /**
     * @description The connection an org is on, as an Id: its own, else the main one (the hub: the main one). Reads the
     * populated fields only, so an org queried without Role__c or Git_Connection__c is fine.
     * @param o the org
     * @param mainId the main connection's Id
     * @return the connection's Id
     */
    public static Id connectionIdOf(RLY_Org__c o, Id mainId) {
        Map<String, Object> present = o == null ? new Map<String, Object>() : o.getPopulatedFieldsAsMap();
        if (present.get('Role__c') == 'Hub' || present.get('Git_Connection__c') == null) {
            return mainId;
        }
        return (Id) present.get('Git_Connection__c');
    }

    /**
     * @description The main connection's Id.
     * @return the Id, or null when the hub has no connection
     */
    public static Id mainId() {
        RLY_Git_Connection__c main = RlyReleaseStore.git();
        return main == null ? null : main.Id;
    }

    /**
     * @description The connection a release lives in: its own Git_Connection__c, else its source org's, else the main
     * one. A release read without Git_Connection__c is read again for it.
     * @param rel the release
     * @return the connection, or null when the hub has none
     */
    public static RLY_Git_Connection__c forRelease(RLY_Release__c rel) {
        if (rel == null) {
            return RlyReleaseStore.git();
        }
        Map<String, Object> present = rel.getPopulatedFieldsAsMap();
        RLY_Release__c row = rel;
        if (!present.containsKey('Git_Connection__c') && rel.Id != null) {
            row = RlyConnectionStore.releaseConnection(rel.Id);
            present = row == null ? present : row.getPopulatedFieldsAsMap();
        }
        Id connectionId = (Id) present.get('Git_Connection__c');
        if (connectionId != null) {
            return RlyConnectionStore.orMain(connectionId);
        }
        Object source = present.get('Source_Org__r');
        if (source instanceof RLY_Org__c && ((RLY_Org__c) source).getPopulatedFieldsAsMap().containsKey('Git_Connection__c')) {
            return RlyConnectionStore.orMain(connectionIdOf((RLY_Org__c) source, null)); // read with the release: no query
        }
        Id orgId = (Id) present.get('Source_Org__c');
        return orgId == null ? RlyReleaseStore.git() : forOrg(orgId);
    }

    /**
     * @description The connection an org belongs to: its Git_Connection__c, else the main one (the hub: the main one).
     * @param orgId the org
     * @return the connection, or null when the hub has none
     */
    public static RLY_Git_Connection__c forOrg(Id orgId) {
        RLY_Org__c o = orgId == null ? null : RlyReleaseStore.org(orgId);
        return RlyConnectionStore.orMain(o == null || o.Role__c == 'Hub' ? null : o.Git_Connection__c);
    }

    /**
     * @description The orgs on one connection (the hub always kept: it ends every route).
     * @param orgs the orgs (with Role__c and Git_Connection__c)
     * @param connectionId the connection (blank: the main one)
     * @return the orgs on it
     */
    public static List<RLY_Org__c> onConnection(List<RLY_Org__c> orgs, Id connectionId) {
        Id mainId = mainId();
        Id wanted = connectionId == null ? mainId : connectionId;
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs) {
            if (o.Role__c == 'Hub' || connectionIdOf(o, mainId) == wanted) {
                out.add(o);
            }
        }
        return out;
    }

    /**
     * @description The route of one connection: its stages and the hub.
     * @param connectionId the connection (blank: the main one)
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> routeOrgsFor(Id connectionId) {
        return onConnection(RlyReleaseStore.routeOrgs(), connectionId);
    }

    /**
     * @description The first stage of one connection's route.
     * @param connectionId the connection (blank: the main one)
     * @return the stage, or null
     */
    public static RLY_Org__c firstStageFor(Id connectionId) {
        for (RLY_Org__c o : RlyRouteRules.ordered(routeOrgsFor(connectionId))) {
            if (o.Role__c == 'Stage') {
                return o;
            }
        }
        return null;
    }

    /**
     * @description The branches of one connection's developer orgs, each once, by org name.
     * @param connectionId the connection (blank: the main one)
     * @return the branch names
     */
    public static List<String> developerBranchesFor(Id connectionId) {
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (RLY_Org__c o : onConnection(RlyConnectionStore.orgs(), connectionId)) {
            if (o.Role__c == 'Developer' && String.isNotBlank(o.Branch__c) && seen.add(o.Branch__c.trim())) {
                out.add(o.Branch__c.trim());
            }
        }
        return out;
    }
}
