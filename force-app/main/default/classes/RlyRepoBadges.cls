/**
 * @description The Releases list's older-repository badge (build 46): after a move to another Git provider, a release
 * raised before it lives in the old repository, and its card says which provider (GitHub, GitLab...). Releases in the
 * active repository, and every release of a hub with one connection, get no badge.
 */
public with sharing class RlyRepoBadges {

    /**
     * @description The releases among these that live in another repository than the active one, with its provider.
     * @param releaseIds the releases
     * @return release Id to provider name (for example GitHub); releases in the active repository are left out
     */
    public static Map<Id, String> olderRepositories(Set<Id> releaseIds) {
        Map<Id, String> out = new Map<Id, String>();
        Id active = RlyGitConnections.activeId();
        Id oldest = RlyGitConnections.oldestId();
        if (active == null || RlyGitConnections.connections().size() < 2) {
            return out; // one connection: nothing to tell apart
        }
        for (RLY_Release__c r : new SystemAccess().readConnections(releaseIds)) {
            Id own = r.Git_Connection__c == null ? oldest : r.Git_Connection__c;
            RLY_Git_Connection__c c = own == active ? null : RlyGitConnections.byId(own);
            if (c != null) {
                out.put(r.Id, RlyMigrationMethods.labelOf(c.Provider__c));
            }
        }
        return out;
    }

    /** @description Releases are shared hub records: read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description The releases' stamped connections.
         * @param releaseIds the releases
         * @return the releases with Git_Connection__c
         */
        public List<RLY_Release__c> readConnections(Set<Id> releaseIds) {
            return [SELECT Id, Git_Connection__c FROM RLY_Release__c WHERE Id IN :releaseIds WITH SYSTEM_MODE LIMIT 2000];
        }
    }
}
