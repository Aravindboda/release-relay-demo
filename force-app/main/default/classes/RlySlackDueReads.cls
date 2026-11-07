/**
 * @description Reads for the Slack daily digest and mentions (RlySlackDue, RlySlackAlert), in system mode: the hourly
 * call runs as the pipeline's hub user, and mentions need users and permission set assignments a viewer can't read.
 * Reads only, no DML.
 */
public with sharing class RlySlackDueReads {

    /**
     * @description What one org's daily digest says: deployed since a moment, waiting for approval, failed, steps to do.
     * @param orgId the org
     * @param since the start of yesterday
     * @return the digest's releases by line
     */
    public static Map<String, List<RLY_Release__c>> digest(Id orgId, Datetime since) {
        return new SystemAccess().digest(orgId, since);
    }

    /**
     * @description Linked Slack member ids of users.
     * @param userIds the users
     * @return user Id to Slack member id (linked users only)
     */
    public static Map<Id, String> memberIds(Set<Id> userIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (userIds.isEmpty()) {
            return out;
        }
        for (User u : new SystemAccess().users(userIds)) {
            if (String.isNotBlank(u.RLY_Slack_Member_Id__c)) {
                out.put(u.Id, u.RLY_Slack_Member_Id__c);
            }
        }
        return out;
    }

    /**
     * @description Active users holding a permission set (by API name), at most a few.
     * @param setNames the permission sets
     * @return the users' Ids
     */
    public static Set<Id> holders(Set<String> setNames) {
        return new SystemAccess().holders(setNames);
    }

    /**
     * @description The hub's time zone (the company's default).
     * @return the time zone
     */
    public static TimeZone hubTimeZone() {
        return TimeZone.getTimeZone(new SystemAccess().timeZoneKey());
    }

    /** @description Reads in system mode (see the class description). */
    private without sharing class SystemAccess {

        /**
         * @description An org's digest lines.
         * @param orgId the org
         * @param since the start of yesterday
         * @return deployed, waiting, failed and steps (releases with manual steps to do)
         */
        public Map<String, List<RLY_Release__c>> digest(Id orgId, Datetime since) {
            Set<Id> deployedIds = new Set<Id>();
            for (RLY_Release_Event__c e : [SELECT Release__c FROM RLY_Release_Event__c WHERE Org__c = :orgId
                                           AND Event_Type__c = 'Deployed' AND Occurred_On__c >= :since WITH SYSTEM_MODE LIMIT 200]) {
                deployedIds.add(e.Release__c);
            }
            Set<Id> stepIds = new Set<Id>();
            for (RLY_Manual_Step_Run__c r : [SELECT Release__c FROM RLY_Manual_Step_Run__c WHERE Org__c = :orgId
                                             AND Status__c = 'To_Do' WITH SYSTEM_MODE LIMIT 200]) {
                stepIds.add(r.Release__c);
            }
            return new Map<String, List<RLY_Release__c>>{
                'deployed' => [SELECT Id, Name, Title__c FROM RLY_Release__c WHERE Id IN :deployedIds WITH SYSTEM_MODE ORDER BY Name LIMIT 20],
                'waiting' => [SELECT Id, Name, Title__c, CreatedDate FROM RLY_Release__c WHERE Target_Org__c = :orgId
                              AND Status__c = :RlySlackDueStore.READY WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 20],
                'failed' => [SELECT Id, Name, Title__c, Status__c FROM RLY_Release__c WHERE Target_Org__c = :orgId
                             AND Status__c IN ('Checks failed', 'Deploy failed') AND LastModifiedDate >= :since
                             WITH SYSTEM_MODE ORDER BY Name LIMIT 20],
                'steps' => [SELECT Id, Name, Title__c FROM RLY_Release__c WHERE Id IN :stepIds AND Status__c = :RlySlackDueStore.DEPLOYED
                            WITH SYSTEM_MODE ORDER BY Name LIMIT 20]
            };
        }

        /**
         * @description Users with their Slack member ids.
         * @param userIds the users
         * @return the users
         */
        public List<User> users(Set<Id> userIds) {
            return [SELECT Id, Name, RLY_Slack_Member_Id__c FROM User WHERE Id IN :userIds AND IsActive = true WITH SYSTEM_MODE LIMIT 200];
        }

        /**
         * @description Active users holding the permission sets, linked to Slack, at most a few.
         * @param setNames the permission sets
         * @return the user Ids
         */
        public Set<Id> holders(Set<String> setNames) {
            Set<Id> out = new Set<Id>();
            for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name IN :setNames
                                              AND Assignee.IsActive = true AND Assignee.RLY_Slack_Member_Id__c != null
                                              WITH SYSTEM_MODE ORDER BY Assignee.Name LIMIT 50]) {
                if (out.size() < RlySlackDueStore.MAX_MENTIONS) {
                    out.add(a.AssigneeId);
                }
            }
            return out;
        }

        /**
         * @description The company's time zone.
         * @return its key
         */
        public String timeZoneKey() {
            return [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1].TimeZoneSidKey;
        }

    }
}
