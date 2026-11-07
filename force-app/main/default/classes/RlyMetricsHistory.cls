/**
 * @description The Metrics tab's grouped and history reads (RlyMetricsDora, RlyMetricsFlow), in system mode so every
 * Release Relay user sees the same numbers: deploys counted per day by Salesforce, approvals and check results of
 * releases going to an org. Capped; nothing is written.
 */
public with sharing class RlyMetricsHistory {

    /**
     * @description Deploys per day and org in a period, counted by Salesforce (exact even on a big hub).
     * @param fromTime start
     * @param toTime end
     * @param orgId the org, or null for every org
     * @return rows with d (the day), o (the org) and n (deploys)
     */
    public static List<AggregateResult> deploysPerDay(Datetime fromTime, Datetime toTime, Id orgId) {
        return new SystemAccess().deploysPerDay(fromTime, toTime, orgId);
    }

    /**
     * @description Approvals in a period of releases going to an org.
     * @param fromTime start
     * @param toTime end
     * @param orgId the org, or null
     * @return the events, oldest first
     */
    public static List<RLY_Release_Event__c> approvals(Datetime fromTime, Datetime toTime, Id orgId) {
        return new SystemAccess().approvals(fromTime, toTime, orgId);
    }

    /**
     * @description Check results (validations and scans) in a period of releases going to an org.
     * @param fromTime start
     * @param toTime end
     * @param orgId the org, or null
     * @return the events, oldest first
     */
    public static List<RLY_Release_Event__c> checks(Datetime fromTime, Datetime toTime, Id orgId) {
        return new SystemAccess().checks(fromTime, toTime, orgId);
    }

    /** @description Reads in system mode: the numbers are the same for every Release Relay user. */
    private without sharing class SystemAccess {
        private final Integer maxEvents = RlyMetricsStore.MAX_EVENTS;
        private final List<String> approvalTypes = RlyMetricsStore.APPROVAL_TYPES;
        private final List<String> checkTypes = RlyMetricsStore.CHECK_TYPES;

        /**
         * @description Deploys per day and org.
         * @param fromTime start
         * @param toTime end
         * @param orgId the org, or null
         * @return the grouped counts
         */
        public List<AggregateResult> deploysPerDay(Datetime fromTime, Datetime toTime, Id orgId) {
            if (orgId == null) {
                return [SELECT DAY_ONLY(convertTimezone(Occurred_On__c)) d, Org__c o, COUNT(Id) n FROM RLY_Release_Event__c
                        WHERE Event_Type__c = 'Deployed' AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        WITH SYSTEM_MODE GROUP BY DAY_ONLY(convertTimezone(Occurred_On__c)), Org__c LIMIT 2000];
            }
            return [SELECT DAY_ONLY(convertTimezone(Occurred_On__c)) d, Org__c o, COUNT(Id) n FROM RLY_Release_Event__c
                    WHERE Event_Type__c = 'Deployed' AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime AND Org__c = :orgId
                    WITH SYSTEM_MODE GROUP BY DAY_ONLY(convertTimezone(Occurred_On__c)), Org__c LIMIT 2000];
        }

        /**
         * @description Approval events.
         * @param fromTime start
         * @param toTime end
         * @param orgId the org, or null
         * @return the events
         */
        public List<RLY_Release_Event__c> approvals(Datetime fromTime, Datetime toTime, Id orgId) {
            if (orgId == null) {
                return [SELECT Release__c, Occurred_On__c, Release__r.Source_Org__c FROM RLY_Release_Event__c
                        WHERE Event_Type__c IN :approvalTypes AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :maxEvents];
            }
            return [SELECT Release__c, Occurred_On__c, Release__r.Source_Org__c FROM RLY_Release_Event__c
                    WHERE Event_Type__c IN :approvalTypes AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        AND Release__r.Target_Org__c = :orgId
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :maxEvents];
        }

        /**
         * @description Check events.
         * @param fromTime start
         * @param toTime end
         * @param orgId the org, or null
         * @return the events
         */
        public List<RLY_Release_Event__c> checks(Datetime fromTime, Datetime toTime, Id orgId) {
            if (orgId == null) {
                return [SELECT Event_Type__c, Release__c, Occurred_On__c, Detail__c, Release__r.Source_Org__c FROM RLY_Release_Event__c
                        WHERE Event_Type__c IN :checkTypes AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :maxEvents];
            }
            return [SELECT Event_Type__c, Release__c, Occurred_On__c, Detail__c, Release__r.Source_Org__c FROM RLY_Release_Event__c
                    WHERE Event_Type__c IN :checkTypes AND Occurred_On__c >= :fromTime AND Occurred_On__c < :toTime
                        AND Release__r.Target_Org__c = :orgId
                    WITH SYSTEM_MODE ORDER BY Occurred_On__c LIMIT :maxEvents];
        }

    }
}
