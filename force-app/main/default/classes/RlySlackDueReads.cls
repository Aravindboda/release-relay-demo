/**
 * @description Reads for the Slack daily digest and mentions (RlySlackDue, RlySlackAlert), in system mode: the hourly
 * call runs as the pipeline's hub user, and mentions need users and permission set assignments a viewer can't read.
 * Reads only, no DML.
 */
public with sharing class RlySlackDueReads {

    /**
     * @description What each due org's daily digest says, read for every org at once (five queries in all, not six per
     * org): deployed since a moment, waiting for approval, failed, steps to do; at most 20
     * releases a line per org.
     * @param orgIds the orgs whose digest is due
     * @param since the start of yesterday
     * @return org Id to its digest's releases by line (deployed, waiting, failed, steps)
     */
    public static Map<Id, Map<String, List<RLY_Release__c>>> digests(Set<Id> orgIds, Datetime since) {
        Map<Id, Map<String, List<RLY_Release__c>>> out = new Map<Id, Map<String, List<RLY_Release__c>>>();
        for (Id orgId : orgIds) {
            out.put(orgId, new Map<String, List<RLY_Release__c>>{ 'deployed' => new List<RLY_Release__c>(),
                'waiting' => new List<RLY_Release__c>(), 'failed' => new List<RLY_Release__c>(), 'steps' => new List<RLY_Release__c>() });
        }
        if (orgIds.isEmpty()) {
            return out;
        }
        SystemAccess data = new SystemAccess();
        Map<Id, Set<Id>> deployedIn = data.deployedIn(orgIds, since);
        Map<Id, Set<Id>> stepsIn = data.stepsIn(orgIds);
        Set<Id> ids = new Set<Id>(deployedIn.keySet());
        ids.addAll(stepsIn.keySet());
        for (RLY_Release__c r : data.byName(ids)) {
            if (deployedIn.containsKey(r.Id)) {
                addTo(linesOf(out, deployedIn.get(r.Id), 'deployed'), r);
            }
            if (stepsIn.containsKey(r.Id) && r.Status__c == RlySlackDueStore.DEPLOYED) {
                addTo(linesOf(out, stepsIn.get(r.Id), 'steps'), r);
            }
        }
        for (RLY_Release__c r : data.waiting(orgIds)) {
            addTo(linesOf(out, new Set<Id>{ r.Target_Org__c }, 'waiting'), r);
        }
        for (RLY_Release__c r : data.failed(orgIds, since)) {
            addTo(linesOf(out, new Set<Id>{ r.Target_Org__c }, 'failed'), r);
        }
        return out;
    }

    // One line of each of these orgs' digests.
    private static List<List<RLY_Release__c>> linesOf(Map<Id, Map<String, List<RLY_Release__c>>> out, Set<Id> orgIds, String line) {
        List<List<RLY_Release__c>> lines = new List<List<RLY_Release__c>>();
        for (Id orgId : orgIds) {
            if (out.containsKey(orgId)) {
                lines.add(out.get(orgId).get(line));
            }
        }
        return lines;
    }

    // Adds a release to each line, up to 20 a line.
    private static void addTo(List<List<RLY_Release__c>> lines, RLY_Release__c r) {
        for (List<RLY_Release__c> rows : lines) {
            if (rows.size() < 20) {
                rows.add(r);
            }
        }
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
         * @description Releases deployed in the orgs since a moment, with the orgs each was deployed in.
         * @param orgIds the orgs
         * @param since the start of yesterday
         * @return release Id to the orgs
         */
        public Map<Id, Set<Id>> deployedIn(Set<Id> orgIds, Datetime since) {
            Map<Id, Set<Id>> out = new Map<Id, Set<Id>>();
            for (RLY_Release_Event__c e : [SELECT Release__c, Org__c FROM RLY_Release_Event__c WHERE Org__c IN :orgIds
                                           AND Event_Type__c = 'Deployed' AND Occurred_On__c >= :since WITH SYSTEM_MODE LIMIT 2000]) {
                addOrg(out, e.Release__c, e.Org__c);
            }
            return out;
        }

        /**
         * @description Releases with manual steps to do in the orgs, with the orgs.
         * @param orgIds the orgs
         * @return release Id to the orgs
         */
        public Map<Id, Set<Id>> stepsIn(Set<Id> orgIds) {
            Map<Id, Set<Id>> out = new Map<Id, Set<Id>>();
            for (RLY_Manual_Step_Run__c r : [SELECT Release__c, Org__c FROM RLY_Manual_Step_Run__c WHERE Org__c IN :orgIds
                                             AND Status__c = 'To_Do' WITH SYSTEM_MODE LIMIT 2000]) {
                addOrg(out, r.Release__c, r.Org__c);
            }
            return out;
        }

        private void addOrg(Map<Id, Set<Id>> byRelease, Id releaseId, Id orgId) {
            if (!byRelease.containsKey(releaseId)) {
                byRelease.put(releaseId, new Set<Id>());
            }
            byRelease.get(releaseId).add(orgId);
        }

        /**
         * @description Releases by name, with their status.
         * @param ids the releases
         * @return the releases
         */
        public List<RLY_Release__c> byName(Set<Id> ids) {
            return [SELECT Id, Name, Title__c, Status__c FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE ORDER BY Name LIMIT 2000];
        }

        /**
         * @description Releases waiting for approval into the orgs, oldest first.
         * @param orgIds the orgs
         * @return the releases
         */
        public List<RLY_Release__c> waiting(Set<Id> orgIds) {
            return [SELECT Id, Name, Title__c, CreatedDate, Target_Org__c FROM RLY_Release__c WHERE Target_Org__c IN :orgIds
                    AND Status__c = :RlySlackDueStore.READY WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 2000];
        }

        /**
         * @description Releases whose checks or deploy failed in the orgs since a moment, by name.
         * @param orgIds the orgs
         * @param since the start of yesterday
         * @return the releases
         */
        public List<RLY_Release__c> failed(Set<Id> orgIds, Datetime since) {
            return [SELECT Id, Name, Title__c, Status__c, Target_Org__c FROM RLY_Release__c WHERE Target_Org__c IN :orgIds
                    AND Status__c IN ('Checks failed', 'Deploy failed') AND LastModifiedDate >= :since
                    WITH SYSTEM_MODE ORDER BY Name LIMIT 2000];
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
