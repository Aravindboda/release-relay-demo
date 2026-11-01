/**
 * @description The Releases tab's server-side filter and chip counts. A release's status falls in one state:
 * open (still needs something: running, or waiting for the developer after Checks failed or for an approver),
 * deployed, failed (the run or the deploy failed) or closed (rejected or closed without deploying); all is every
 * status. Releases are shared hub records that every Release Relay user lists, so the queries run in system mode,
 * in the private inner without sharing class, and only read.
 */
public with sharing class RlyReleaseQuery {

    /** @description The default state of the Releases tab. */
    public static final String STATE_OPEN = 'open';

    /** @description Statuses that still need something (the open state). */
    private static final Set<String> OPEN_STATES = new Set<String>{ 'Submitted', 'Retrieving', 'Workflow running', 'Validating',
        'PR open', 'Checks failed', 'Ready for approval', 'Approved', 'Merging', 'Merged', 'Deploying' };

    /** @description The Releases tab's states and the statuses each one groups. */
    public static final Map<String, Set<String>> STATE_STATUSES = new Map<String, Set<String>>{
        STATE_OPEN => OPEN_STATES,
        'deployed' => new Set<String>{ 'Deployed' },
        'failed' => new Set<String>{ 'Failed', 'Deploy failed' },
        'closed' => new Set<String>{ 'Rejected', 'Closed' },
        'all' => everyStatus()
    };

    /** @description What the Releases tab filters on. */
    public class Filter {
        /** @description The user who raised the releases, or blank for everyone. */
        public String raisedById;
        /** @description open, deployed, failed, closed or all (blank: open). */
        public String state;
        /** @description Part of the release number or title, or blank. */
        public String searchText;
    }

    private static Set<String> everyStatus() {
        Set<String> statuses = new Set<String>(OPEN_STATES);
        statuses.addAll(new Set<String>{ 'Deployed', 'Failed', 'Deploy failed', 'Rejected', 'Closed' });
        return statuses;
    }

    /**
     * @description Reads a filter sent by the page.
     * @param filterJson {"raisedById", "state", "searchText"}, or blank for everyone's open releases
     * @return the filter
     */
    public static Filter parse(String filterJson) {
        return String.isBlank(filterJson) ? new Filter() : (Filter) JSON.deserialize(filterJson, Filter.class);
    }

    /**
     * @description Releases raised by a user (or everyone), in a state, matching a search on the number or title.
     * @param f the filter (a blank state means open)
     * @return up to 200 releases, newest first (open: hotfixes first)
     */
    public static List<RLY_Release__c> releasesFor(Filter f) {
        String state = String.isBlank(f.state) ? STATE_OPEN : f.state;
        Set<String> statuses = STATE_STATUSES.get(state);
        if (statuses == null) {
            throw new RlyReleaseException('Unknown release filter: ' + state);
        }
        String term = String.isBlank(f.searchText) ? '' : f.searchText.trim().left(80);
        String pattern = '%' + term + '%';
        Id userId = userIdOf(f.raisedById);
        SystemAccess access = new SystemAccess();
        List<RLY_Release__c> rels = userId == null ? access.listed(statuses, pattern) : access.listedBy(userId, statuses, pattern);
        return state == STATE_OPEN ? hotfixesFirst(rels) : rels;
    }

    /**
     * @description How many releases a user (or everyone) raised in each state.
     * @param raisedById the user, or blank for everyone
     * @return the count by state (open, deployed, failed, closed, all); every state is present
     */
    public static Map<String, Integer> countsFor(String raisedById) {
        Id userId = userIdOf(raisedById);
        SystemAccess access = new SystemAccess();
        List<AggregateResult> groups = userId == null ? access.statusCounts() : access.statusCountsBy(userId);
        Map<String, Integer> counts = new Map<String, Integer>();
        for (String state : STATE_STATUSES.keySet()) {
            counts.put(state, 0);
        }
        for (AggregateResult g : groups) {
            String status = (String) g.get('relStatus');
            Integer n = (Integer) g.get('relCount');
            for (String state : STATE_STATUSES.keySet()) {
                if (STATE_STATUSES.get(state).contains(status)) {
                    counts.put(state, counts.get(state) + n);
                }
            }
        }
        return counts;
    }

    private static Id userIdOf(String raisedById) {
        if (String.isBlank(raisedById)) {
            return null;
        }
        Id userId = Id.valueOf(raisedById.trim());
        if (userId.getSobjectType() != User.SObjectType) {
            throw new RlyReleaseException('Raised by must be a user.');
        }
        return userId;
    }

    private static List<RLY_Release__c> hotfixesFirst(List<RLY_Release__c> rels) {
        List<RLY_Release__c> hot = new List<RLY_Release__c>();
        List<RLY_Release__c> rest = new List<RLY_Release__c>();
        for (RLY_Release__c r : rels) {
            if (RlyHotfix.isHotfix(r)) {
                hot.add(r);
            } else {
                rest.add(r);
            }
        }
        hot.addAll(rest);
        return hot;
    }

    /** @description Shared hub releases, read in system mode for the list. */
    private without sharing class SystemAccess {

        /**
         * @description Releases anyone raised, in some statuses, matching a number or title pattern.
         * @param statuses the statuses
         * @param pattern a LIKE pattern for the number or title
         * @return the releases, newest first
         */
        public List<RLY_Release__c> listed(Set<String> statuses, String pattern) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                           Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND Status__c IN :statuses AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description Releases one user raised, in some statuses, matching a number or title pattern.
         * @param userId the user
         * @param statuses the statuses
         * @param pattern a LIKE pattern for the number or title
         * @return the releases, newest first
         */
        public List<RLY_Release__c> listedBy(Id userId, Set<String> statuses, String pattern) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                           Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :userId AND Status__c IN :statuses
                        AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description How many releases (raised from a developer org) are in each status.
         * @return one row per status: relStatus, relCount
         */
        public List<AggregateResult> statusCounts() {
            return [SELECT Status__c relStatus, COUNT(Id) relCount FROM RLY_Release__c WHERE Source_Org__c != null
                    WITH SYSTEM_MODE GROUP BY Status__c LIMIT 200];
        }

        /**
         * @description How many releases one user raised are in each status.
         * @param userId the user
         * @return one row per status: relStatus, relCount
         */
        public List<AggregateResult> statusCountsBy(Id userId) {
            return [SELECT Status__c relStatus, COUNT(Id) relCount FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :userId
                    WITH SYSTEM_MODE GROUP BY Status__c LIMIT 200];
        }
    }
}
