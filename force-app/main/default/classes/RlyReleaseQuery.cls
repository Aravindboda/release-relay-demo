/**
 * @description The Releases tab's server-side filter and chip counts. A release's status falls in one state:
 * open (still needs something: running, or waiting for the developer after Checks failed or for an approver),
 * deployed, failed (the run or the deploy failed) or closed (rejected or closed without deploying); all is every
 * status. checks is the part of open that waits for the developer (Checks failed: scan, check-only deploy or merge
 * conflicts). A release rolled back in an org (Rollback_Status__c Rolled_Back) keeps its status but is listed and counted
 * under rolledback instead of deployed. Releases are shared hub records that every Release Relay user lists, so the
 * queries run in system mode, in the private inner without sharing class, and only read.
 */
public with sharing class RlyReleaseQuery {

    /** @description The default state of the Releases tab. */
    public static final String STATE_OPEN = 'open';
    /** @description The Releases tab's state of releases rolled back in an org. */
    public static final String STATE_ROLLED_BACK = 'rolledback';

    private static final String STATE_DEPLOYED = 'deployed';
    // NOT IN needs a value: nothing is hidden outside the deployed state.
    private static final Set<String> HIDE_NOTHING = new Set<String>{ '-' };

    /** @description Statuses that still need something (the open state). */
    private static final Set<String> OPEN_STATES = new Set<String>{ 'Submitted', 'Retrieving', 'Workflow running', 'Validating',
        'PR open', 'Checks failed', 'Ready for approval', 'Approved', 'Merging', 'Merged', 'Deploying' };

    /** @description The Releases tab's states and the statuses each one groups. */
    public static final Map<String, Set<String>> STATE_STATUSES = new Map<String, Set<String>>{
        STATE_OPEN => OPEN_STATES,
        'checks' => new Set<String>{ 'Checks failed' },
        STATE_DEPLOYED => new Set<String>{ 'Deployed' },
        STATE_ROLLED_BACK => everyStatus(),
        'failed' => new Set<String>{ 'Failed', 'Deploy failed' },
        'closed' => new Set<String>{ 'Rejected', 'Closed' },
        'all' => everyStatus()
    };

    /** @description What the Releases tab filters on. */
    public class Filter {
        /** @description The user who raised the releases, or blank for everyone. */
        public String raisedById;
        /** @description open, checks, deployed, rolledback, failed, closed or all (blank: open). */
        public String state;
        /** @description Part of the release number or title, or blank. */
        public String searchText;
    }

    /** @description What the list queries: statuses, a search pattern, a user and the rollback states left out. */
    private class Criteria {
        /** @description The statuses. */
        public Set<String> statuses;
        /** @description A LIKE pattern for the number or title. */
        public String pattern;
        /** @description The user who raised them, or null for everyone. */
        public Id userId;
        /** @description Rollback_Status__c values left out (deployed leaves out Rolled_Back). */
        public Set<String> hiddenRollback;
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
        Criteria c = new Criteria();
        c.statuses = statuses;
        c.pattern = '%' + (String.isBlank(f.searchText) ? '' : f.searchText.trim().left(80)) + '%';
        c.userId = userIdOf(f.raisedById);
        c.hiddenRollback = state == STATE_DEPLOYED ? new Set<String>{ RlyRollbackState.ROLLED_BACK } : HIDE_NOTHING;
        List<RLY_Release__c> rels = state == STATE_ROLLED_BACK ? new SystemAccess().rolledBack(c) : new SystemAccess().listed(c);
        return state == STATE_OPEN ? hotfixesFirst(rels) : rels;
    }

    /**
     * @description How many releases a user (or everyone) raised in each state.
     * @param raisedById the user, or blank for everyone
     * @return the count by state (open, checks, deployed, rolledback, failed, closed, all); every state is present
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
            addCount(counts, g);
        }
        return counts;
    }

    // A group of releases (one status and rollback state) counts in each state it falls in: a rolled back release
    // counts under rolledback, not deployed.
    private static void addCount(Map<String, Integer> counts, AggregateResult g) {
        String status = (String) g.get('relStatus');
        Integer n = (Integer) g.get('relCount');
        Boolean rolledBack = (String) g.get('relRollback') == RlyRollbackState.ROLLED_BACK;
        for (String state : STATE_STATUSES.keySet()) {
            Boolean inState = state == STATE_ROLLED_BACK ? rolledBack : STATE_STATUSES.get(state).contains(status);
            if (inState && !(rolledBack && state == STATE_DEPLOYED)) {
                counts.put(state, counts.get(state) + n);
            }
        }
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
         * @description Releases in some statuses matching a number or title pattern, raised by anyone or by one user,
         * leaving out some rollback states.
         * @param c the criteria
         * @return the releases, newest first
         */
        public List<RLY_Release__c> listed(Criteria c) {
            Set<String> statuses = c.statuses;
            String pattern = c.pattern;
            Set<String> hidden = c.hiddenRollback;
            if (c.userId == null) {
                return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                               CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                               Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                        FROM RLY_Release__c WHERE Source_Org__c != null AND Status__c IN :statuses AND (Rollback_Status__c = null OR Rollback_Status__c NOT IN :hidden)
                            AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                        WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
            }
            Id userId = c.userId;
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                           Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :userId AND Status__c IN :statuses
                        AND (Rollback_Status__c = null OR Rollback_Status__c NOT IN :hidden) AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description Releases rolled back in an org, matching a number or title pattern, raised by anyone or one user.
         * @param c the criteria (statuses and hidden rollback states aren't used)
         * @return the releases, newest rollback first
         */
        public List<RLY_Release__c> rolledBack(Criteria c) {
            String pattern = c.pattern;
            Id userId = c.userId;
            String rolled = RlyRollbackState.ROLLED_BACK;
            if (userId == null) {
                return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                               CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                               Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                        FROM RLY_Release__c WHERE Source_Org__c != null AND Rollback_Status__c = :rolled
                            AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                        WITH SYSTEM_MODE ORDER BY Rollback_On__c DESC LIMIT 200];
            }
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c, Is_Hotfix__c, Hotfix_Reason__c,
                           Release_Type__c, Carried_Releases__c, Deletion_Count__c, CreatedById, Last_Synced__c, Manual_Only__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :userId AND Rollback_Status__c = :rolled
                        AND (Name LIKE :pattern OR Title__c LIKE :pattern)
                    WITH SYSTEM_MODE ORDER BY Rollback_On__c DESC LIMIT 200];
        }

        /**
         * @description How many releases (raised from a developer org) are in each status.
         * @return one row per status and rollback state: relStatus, relRollback, relCount
         */
        public List<AggregateResult> statusCounts() {
            return [SELECT Status__c relStatus, Rollback_Status__c relRollback, COUNT(Id) relCount FROM RLY_Release__c
                    WHERE Source_Org__c != null WITH SYSTEM_MODE GROUP BY Status__c, Rollback_Status__c LIMIT 200];
        }

        /**
         * @description How many releases one user raised are in each status.
         * @param userId the user
         * @return one row per status and rollback state: relStatus, relRollback, relCount
         */
        public List<AggregateResult> statusCountsBy(Id userId) {
            return [SELECT Status__c relStatus, Rollback_Status__c relRollback, COUNT(Id) relCount FROM RLY_Release__c
                    WHERE Source_Org__c != null AND CreatedById = :userId WITH SYSTEM_MODE GROUP BY Status__c, Rollback_Status__c LIMIT 200];
        }
    }
}
