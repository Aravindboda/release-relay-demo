/**
 * @description The Metrics tab's reads (RlyMetricsController), in system mode so every Release Relay user sees the same
 * numbers: the route and developer orgs, deploy and rollback history events, grouped deploy counts per day, approvals,
 * check results, the releases a promotion carries and a few releases' check results. Every read is capped; nothing is
 * written.
 */
public with sharing class RlyMetricsStore {

    /** @description The most history events one read takes. */
    public static final Integer MAX_EVENTS = 4000;
    /** @description The events a deploy, a failed deploy or a rollback leaves. */
    public static final List<String> DEPLOY_TYPES = new List<String>{ 'Deployed', 'Deploy_Failed', 'Rolled_Back' };
    /** @description The events an approval leaves. */
    public static final List<String> APPROVAL_TYPES = new List<String>{ 'Approved', 'Auto_Approved' };
    /** @description The events a check leaves. */
    public static final List<String> CHECK_TYPES = new List<String>{ 'Validation', 'Scan' };

    /**
     * @description The orgs releases go to and come from, by stage order then name.
     * @return the orgs
     */
    public static List<RLY_Org__c> orgs() {
        return new SystemAccess().orgs();
    }

    /**
     * @description Deploys, failed deploys and rollbacks in a period, oldest first.
     * @param fromTime start (included)
     * @param toTime end (excluded)
     * @param orgId the org, or null for every org
     * @return the events, at most MAX_EVENTS
     */
    public static List<RLY_Release_Event__c> deployEvents(Datetime fromTime, Datetime toTime, Id orgId) {
        return new SystemAccess().deployEvents(fromTime, toTime, orgId);
    }

    /**
     * @description The validations of some releases up to a moment (when each became ready for approval).
     * @param releaseIds the releases
     * @param upTo the latest moment
     * @return the events, oldest first
     */
    public static List<RLY_Release_Event__c> validationsOf(Set<Id> releaseIds, Datetime upTo) {
        return releaseIds.isEmpty() ? new List<RLY_Release_Event__c>() : new SystemAccess().validationsOf(releaseIds, upTo);
    }

    /**
     * @description Releases by Id: when raised and from which org (the releases promotions carry).
     * @param ids the releases
     * @return the releases by Id
     */
    public static Map<Id, RLY_Release__c> raised(Set<Id> ids) {
        return ids.isEmpty() ? new Map<Id, RLY_Release__c>() : new Map<Id, RLY_Release__c>(new SystemAccess().raised(ids));
    }

    /**
     * @description A few releases' latest check results.
     * @param ids the releases (a page of them)
     * @return the releases
     */
    public static List<RLY_Release__c> results(Set<Id> ids) {
        return ids.isEmpty() ? new List<RLY_Release__c>() : new SystemAccess().results(ids);
    }

    /** @description Reads in system mode: the numbers are the same for every Release Relay user. */
    private without sharing class SystemAccess {
        /**
         * @description The orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Stage_Order__c FROM RLY_Org__c
                    WHERE Role__c IN ('Developer', 'Stage', 'Hub') WITH SYSTEM_MODE ORDER BY Stage_Order__c NULLS FIRST, Name LIMIT 200];
        }

        /**
         * @description Deploy events.
         * @param fromTime start
         * @param toTime end
         * @param orgId the org, or null
         * @return the events
         */
        public List<RLY_Release_Event__c> deployEvents(Datetime fromTime, Datetime toTime, Id orgId) {
            if (orgId == null) {
                return [SELECT Event_Type__c, Org__c, Occurred_On__c, Release__c, Release__r.Name, Release__r.CreatedDate,
                               Release__r.Is_Hotfix__c, Release__r.Source_Org__c, Release__r.Carried_Releases__c
                        FROM RLY_Release_Event__c
                        WHERE Event_Type__c IN :DEPLOY_TYPES AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :MAX_EVENTS];
            }
            return [SELECT Event_Type__c, Org__c, Occurred_On__c, Release__c, Release__r.Name, Release__r.CreatedDate,
                           Release__r.Is_Hotfix__c, Release__r.Source_Org__c, Release__r.Carried_Releases__c
                    FROM RLY_Release_Event__c
                    WHERE Event_Type__c IN :DEPLOY_TYPES AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        AND Org__c = :orgId
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :MAX_EVENTS];
        }

        /**
         * @description Validations of releases.
         * @param releaseIds the releases
         * @param upTo the latest moment
         * @return the events
         */
        public List<RLY_Release_Event__c> validationsOf(Set<Id> releaseIds, Datetime upTo) {
            return [SELECT Release__c, Occurred_On__c FROM RLY_Release_Event__c
                    WHERE Event_Type__c = 'Validation' AND Release__c IN :releaseIds AND Occurred_On__c <= :upTo
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :MAX_EVENTS];
        }

        /**
         * @description Releases' raise time and source.
         * @param ids the releases
         * @return the releases
         */
        public List<RLY_Release__c> raised(Set<Id> ids) {
            return [SELECT Id, CreatedDate, Source_Org__c FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE LIMIT 10000];
        }

        /**
         * @description Releases' check results.
         * @param ids the releases
         * @return the releases
         */
        public List<RLY_Release__c> results(Set<Id> ids) {
            return [SELECT Id, Name, Validation_Status__c, Validation_Result__c FROM RLY_Release__c
                    WHERE Id IN :ids WITH SYSTEM_MODE LIMIT 20];
        }
    }
}
