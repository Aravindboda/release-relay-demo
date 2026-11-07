/**
 * @description Several Git connections (build 45): what stops saving a connection. One connection per provider; the main
 * connection (the oldest active one) stays active; a connection is switched off only once its orgs have moved.
 */
public with sharing class RlyConnectionRules {

    /**
     * @description Why the connection can't be saved, or null.
     * @param input the connection as sent (checked by RlyGitValidator)
     * @param conns every connection, the main one first
     * @return the reason as a sentence, or null when it may be saved
     */
    public static String problemOf(RLY_Git_Connection__c input, List<RLY_Git_Connection__c> conns) {
        RLY_Git_Connection__c existing = input.Id == null ? null : find(conns, input.Id);
        if (input.Id != null && existing == null) {
            return 'That Git connection isn\'t there any more.';
        }
        try {
            checkUnique(input, conns);
            if (!activeOf(input, existing) && existing != null) {
                checkCanDeactivate(existing, conns);
            }
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return null;
    }

    /**
     * @description The Active toggle as sent, else as saved (a new connection is active).
     * @param input the connection as sent
     * @param existing the connection as saved, or null for a new one
     * @return whether it is active
     */
    public static Boolean activeOf(RLY_Git_Connection__c input, RLY_Git_Connection__c existing) {
        if (input.isSet('Active__c')) {
            return input.Active__c == true;
        }
        return existing == null || existing.Active__c == true;
    }

    private static void checkUnique(RLY_Git_Connection__c input, List<RLY_Git_Connection__c> conns) {
        for (RLY_Git_Connection__c c : conns) {
            if (c.Provider__c == input.Provider__c && c.Id != input.Id) {
                String provider = RlyGitName.labelFor(c);
                throw new RlyReleaseException('There\'s already a ' + (provider == null ? c.Provider__c : provider)
                    + ' connection: edit it instead. One connection per provider.');
            }
        }
    }

    private static void checkCanDeactivate(RLY_Git_Connection__c existing, List<RLY_Git_Connection__c> conns) {
        if (existing.Id == conns[0].Id) {
            throw new RlyReleaseException('The main connection stays active: the schedules and the archive run on it, and orgs without a '
                + 'connection are on it.');
        }
        List<RLY_Org__c> onIt = new List<RLY_Org__c>();
        for (RLY_Org__c o : RlyConnectionStore.orgsOn(existing.Id, conns[0].Id)) {
            if (o.Role__c != 'Hub') {
                onIt.add(o);
            }
        }
        if (!onIt.isEmpty()) {
            throw new RlyReleaseException('Move its orgs to another connection first (' + onIt[0].Name + (onIt.size() > 1 ? ' and ' + (onIt.size() - 1) + ' more' : '') + ').');
        }
    }

    private static RLY_Git_Connection__c find(List<RLY_Git_Connection__c> conns, Id connectionId) {
        for (RLY_Git_Connection__c c : conns) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return null;
    }
}
