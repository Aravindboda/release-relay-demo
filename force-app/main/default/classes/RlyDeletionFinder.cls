/**
 * @description Delete from the branch (build 37.1): the hub's Git connection, checked, and its source path, for the
 * branch's plan and parts (RlyDeletionPlan). Build 50 retired the automatic Find deleted components scan (the whole
 * branch's tree read plus a listing of the org): deletions are raised only by picking them on the branch, one folder
 * part per request.
 */
public with sharing class RlyDeletionFinder {

    /**
     * @description The hub's Git connection, checked (connected).
     * @return the provider
     */
    public static RlyGit git() {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null || conn.Status__c != 'Connected') {
            throw new RlyReleaseException('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        return RlyGit.forConnection(conn);
    }

    /**
     * @description The Git connection's source path, without a trailing slash (blank: the repository root).
     * @return the path
     */
    public static String sourcePath() {
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        return conn == null || String.isBlank(conn.Source_Path__c) ? '' : conn.Source_Path__c.trim().removeEnd('/');
    }

    // type:fullName (lower case) of every component of these types in the org.

    // A standard object (Account) or field (Account.Industry): it can't be deleted.
}
