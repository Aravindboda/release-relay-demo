/**
 * @description The developer's group of the Home tab's "Needs you" card (RlyHomeNeeds): the user's own releases that
 * stopped on a failure (checks failed, deploy failed, run failed) or wait on a conflict, with the target branch (a
 * failed check whose validation result lists conflicting files) or in the back-merge after a deploy (Back_Merge_Result__c
 * branches with status Conflict, releases deployed in the last 30 days). Releases are shared hub records, read in system
 * mode in the private inner without sharing class; nothing is written.
 */
public with sharing class RlyHomeProblems {

    private static final String TONE_WAIT = 'wait';
    private static final String TONE_BAD = 'bad';
    private static final String CONFLICT_STATUS = 'Conflict';
    private static final String STATUS_DEPLOYED = 'Deployed';
    /** @description Statuses of a release that stopped on a failure. */
    private static final Set<String> FAILED_STATUSES = new Set<String>{ 'Checks failed', 'Deploy failed', 'Failed' };

    /**
     * @description A user's releases with a problem.
     * @param userId the user who raised them
     * @return the group "Your releases with a problem"
     */
    public static RlyHomeNeeds.NeedGroup forUser(Id userId) {
        Data store = new Data();
        RlyHomeNeeds.NeedGroup g = RlyHomeNeeds.groupOf(RlyHomeNeeds.GROUP_MINE, 'Your releases with a problem');
        for (RLY_Release__c r : store.failedBy(userId)) {
            g.rows.add(failedRow(r));
        }
        for (RLY_Release__c r : store.deployedBy(userId)) {
            Integer branches = backMergeConflicts(r.Back_Merge_Result__c);
            if (branches > 0) {
                RlyHomeNeeds.NeedRow row = RlyHomeNeeds.releaseRow(r);
                row.pill = branches + ' to review';
                row.tone = TONE_WAIT;
                row.note = 'Merged back with conflicts in ' + plural(branches, 'branch') + ' · Review on the release';
                g.rows.add(row);
            }
        }
        return g;
    }

    private static RlyHomeNeeds.NeedRow failedRow(RLY_Release__c r) {
        RlyHomeNeeds.NeedRow row = RlyHomeNeeds.releaseRow(r);
        Integer files = conflictFiles(r.Validation_Result__c);
        if (files > 0) {
            row.pill = files + ' to review';
            row.tone = TONE_WAIT;
            row.note = 'Conflicts in ' + plural(files, 'file') + ' · Resolve on the release';
        } else {
            row.pill = r.Status__c;
            row.tone = TONE_BAD;
            row.note = String.isBlank(r.Error_Message__c) ? null : r.Error_Message__c.trim().substringBefore('\n').left(200);
        }
        return row;
    }

    private static String plural(Integer n, String word) {
        if (n == 1) {
            return n + ' ' + word;
        }
        return n + ' ' + (word.endsWith('h') ? word + 'es' : word + 's');
    }

    /**
     * @description How many files of a failed check conflict with the target branch.
     * @param validationResult the saved Validation_Result__c
     * @return the number of files, 0 when it's not a conflict
     */
    public static Integer conflictFiles(String validationResult) {
        return RlyConflictResult.filesOf(validationResult).size();
    }

    /**
     * @description How many branches the back-merge after a deploy could not merge.
     * @param backMergeResult the saved Back_Merge_Result__c: [{branch, status, message}]
     * @return the number of branches with status Conflict
     */
    public static Integer backMergeConflicts(String backMergeResult) {
        if (String.isBlank(backMergeResult)) {
            return 0;
        }
        Integer n = 0;
        try {
            for (Object o : (List<Object>) JSON.deserializeUntyped(backMergeResult)) {
                Map<String, Object> branch = (Map<String, Object>) o;
                n += String.valueOf(branch.get('status')) == CONFLICT_STATUS ? 1 : 0;
            }
        } catch (Exception e) {
            return 0;
        }
        return n;
    }

    /** @description Shared hub releases, read in system mode. */
    private without sharing class Data {

        /**
         * @description A user's releases stopped on a failure.
         * @param userId the user
         * @return up to 50 releases, newest change first
         */
        public List<RLY_Release__c> failedBy(Id userId) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, CreatedBy.Name, LastModifiedDate,
                           Validation_Result__c, Error_Message__c
                    FROM RLY_Release__c WHERE CreatedById = :userId AND Status__c IN :FAILED_STATUSES
                    WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 50];
        }

        /**
         * @description A user's releases deployed in the last 30 days, with their back-merge result.
         * @param userId the user
         * @return up to 50 releases, newest change first
         */
        public List<RLY_Release__c> deployedBy(Id userId) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Target_Org__r.Name, CreatedBy.Name, LastModifiedDate,
                           Back_Merge_Result__c
                    FROM RLY_Release__c WHERE CreatedById = :userId AND Status__c = :STATUS_DEPLOYED AND LastModifiedDate = LAST_N_DAYS:30
                    WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT 50];
        }
    }
}
