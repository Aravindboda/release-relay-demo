/**
 * @description The releases the pipeline runs belong to (RLY_Release__c): a release by its number (the run endpoint's
 * requestId), the open releases with a source branch and releases by Id (the Pipeline Monitor's Active branches).
 * Releases are shared hub records: read in system mode in the private inner without sharing class.
 */
public with sharing class RlyRunMonitorReleases {

    /**
     * @description The release with this number (REL-00031), or null.
     * @param releaseName the release number
     * @return the release's Id, or null
     */
    public static Id releaseIdByName(String releaseName) {
        return String.isBlank(releaseName) ? null : new SystemAccess().releaseIdByName(releaseName);
    }

    /**
     * @description Releases in some statuses that have a source branch, newest change first.
     * @param statuses the statuses (the open ones)
     * @param max how many at most
     * @return the releases
     */
    public static List<RLY_Release__c> releasesWithBranch(Set<String> statuses, Integer max) {
        return new SystemAccess().releasesWithBranch(statuses, max);
    }

    /**
     * @description Releases by Id, for the branches of recent runs.
     * @param ids the releases
     * @return the releases by Id
     */
    public static Map<Id, RLY_Release__c> releasesById(Set<Id> ids) {
        return ids.isEmpty() ? new Map<Id, RLY_Release__c>() : new SystemAccess().releasesById(ids);
    }

    /** @description Releases are shared hub records: read in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description A release's Id by its number.
         * @param releaseName the number
         * @return the Id, or null
         */
        public Id releaseIdByName(String releaseName) {
            List<RLY_Release__c> rows = [SELECT Id FROM RLY_Release__c WHERE Name = :releaseName WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0].Id;
        }

        /**
         * @description Releases with a source branch in some statuses.
         * @param statuses the statuses
         * @param max how many at most
         * @return the releases
         */
        public List<RLY_Release__c> releasesWithBranch(Set<String> statuses, Integer max) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Branch__c, PR_Number__c, PR_URL__c, LastModifiedDate,
                           Target_Org__r.Name, Release_Type__c
                    FROM RLY_Release__c WHERE Status__c IN :statuses AND Source_Branch__c != null
                    WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT :max];
        }

        /**
         * @description Releases by Id.
         * @param ids the releases
         * @return the releases by Id
         */
        public Map<Id, RLY_Release__c> releasesById(Set<Id> ids) {
            return new Map<Id, RLY_Release__c>([SELECT Id, Name, Title__c, Status__c, Source_Branch__c, PR_Number__c, PR_URL__c,
                                                       LastModifiedDate, Target_Org__r.Name, Release_Type__c
                                                FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]);
        }
    }
}
