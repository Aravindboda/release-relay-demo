/**
 * @description Data access for manual steps and their runs (RlyManualSteps). Steps and runs are shared hub records like
 * the releases they belong to: the flow reads and writes them for every Release Relay user, in system mode, in the
 * private inner without sharing class. Callers check who may do what first (RlyManualStepRules, RlyManualStepCheck).
 */
public with sharing class RlyManualStepStore {

    /**
     * @description The steps these releases defined, by sequence.
     * @param releaseIds the releases
     * @return the steps
     */
    public static List<RLY_Manual_Step__c> stepsOf(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new List<RLY_Manual_Step__c>() : new SystemAccess().querySteps(releaseIds);
    }

    /**
     * @description Steps by Id.
     * @param stepIds the steps
     * @return the steps (those that exist), by sequence
     */
    public static List<RLY_Manual_Step__c> stepsById(Set<Id> stepIds) {
        return stepIds.isEmpty() ? new List<RLY_Manual_Step__c>() : new SystemAccess().queryStepsById(stepIds);
    }

    /**
     * @description The runs of these steps in these orgs.
     * @param stepIds the steps
     * @param orgIds the orgs
     * @return the runs, newest first
     */
    public static List<RLY_Manual_Step_Run__c> runsIn(Set<Id> stepIds, Set<Id> orgIds) {
        return stepIds.isEmpty() ? new List<RLY_Manual_Step_Run__c>() : new SystemAccess().queryRunsIn(stepIds, orgIds);
    }

    /**
     * @description The runs of these steps (every org), and the runs of this release's deploy.
     * @param stepIds the steps
     * @param releaseId the release
     * @return the runs, in deploy order
     */
    public static List<RLY_Manual_Step_Run__c> runsFor(Set<Id> stepIds, Id releaseId) {
        return new SystemAccess().queryRunsFor(stepIds, releaseId);
    }

    /**
     * @description The runs of these releases' deploys.
     * @param releaseIds the releases
     * @return the runs, in deploy order
     */
    public static List<RLY_Manual_Step_Run__c> runsOfReleases(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new List<RLY_Manual_Step_Run__c>() : new SystemAccess().queryRunsOfReleases(releaseIds);
    }

    /**
     * @description One run, with its step's timing.
     * @param runId the run
     * @return the run, or null
     */
    public static RLY_Manual_Step_Run__c run(Id runId) {
        return new SystemAccess().queryRun(runId);
    }

    /**
     * @description How many Before deploy runs of a deploy are still to do.
     * @param releaseId the release deploying
     * @param orgId the org it deploys into
     * @param skipRunId a run not to count (being checked off now), or null
     * @return the number
     */
    public static Integer openBefore(Id releaseId, Id orgId, Id skipRunId) {
        if (releaseId == null || orgId == null) {
            return 0;
        }
        return new SystemAccess().countOpenBefore(releaseId, orgId, skipRunId);
    }

    /**
     * @description How many steps each of these releases defined.
     * @param releaseIds the releases
     * @return the number by release (missing means none)
     */
    public static Map<Id, Integer> stepCounts(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new Map<Id, Integer>() : new SystemAccess().countSteps(releaseIds);
    }

    /**
     * @description How many runs of each release's deploy are still to do.
     * @param releaseIds the releases
     * @return the number by release (missing means none)
     */
    public static Map<Id, Integer> openCounts(Set<Id> releaseIds) {
        return releaseIds.isEmpty() ? new Map<Id, Integer>() : new SystemAccess().countOpen(releaseIds);
    }

    /**
     * @description Saves new or changed steps.
     * @param steps the steps
     */
    public static void saveSteps(List<RLY_Manual_Step__c> steps) {
        if (!steps.isEmpty()) {
            new SystemAccess().upsertSteps(steps);
        }
    }

    /**
     * @description Deletes a step and its runs.
     * @param stepId the step
     */
    public static void deleteStep(Id stepId) {
        new SystemAccess().removeStep(stepId);
    }

    /**
     * @description Saves new or changed runs.
     * @param runs the runs
     */
    public static void saveRuns(List<RLY_Manual_Step_Run__c> runs) {
        if (!runs.isEmpty()) {
            new SystemAccess().upsertRuns(runs);
        }
    }

    /**
     * @description Deletes runs.
     * @param runs the runs
     */
    public static void deleteRuns(List<RLY_Manual_Step_Run__c> runs) {
        if (!runs.isEmpty()) {
            new SystemAccess().removeRuns(runs);
        }
    }

    /** @description Shared hub records, read and written in system mode for the flow. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyManualStepStore.stepsOf.
         * @param releaseIds the releases
         * @return the steps
         */
        public List<RLY_Manual_Step__c> querySteps(Set<Id> releaseIds) {
            return [SELECT Id, Name, Release__c, Release__r.Name, Title__c, Instructions__c, Category__c, Timing__c, Sequence__c,
                           Back_Promote__c, Org_Scope__c
                    FROM RLY_Manual_Step__c WHERE Release__c IN :releaseIds
                    WITH SYSTEM_MODE ORDER BY Sequence__c ASC NULLS LAST, Name ASC LIMIT 2000];
        }

        /**
         * @description See RlyManualStepStore.stepsById.
         * @param stepIds the steps
         * @return the steps
         */
        public List<RLY_Manual_Step__c> queryStepsById(Set<Id> stepIds) {
            return [SELECT Id, Name, Release__c, Release__r.Name, Title__c, Instructions__c, Category__c, Timing__c, Sequence__c,
                           Back_Promote__c, Org_Scope__c
                    FROM RLY_Manual_Step__c WHERE Id IN :stepIds
                    WITH SYSTEM_MODE ORDER BY Sequence__c ASC NULLS LAST, Name ASC LIMIT 2000];
        }

        /**
         * @description See RlyManualStepStore.runsIn.
         * @param stepIds the steps
         * @param orgIds the orgs
         * @return the runs
         */
        public List<RLY_Manual_Step_Run__c> queryRunsIn(Set<Id> stepIds, Set<Id> orgIds) {
            return [SELECT Id, Step__c, Release__c, Org__c, Status__c, Order__c
                    FROM RLY_Manual_Step_Run__c WHERE Step__c IN :stepIds AND Org__c IN :orgIds
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Name DESC LIMIT 5000];
        }

        /**
         * @description See RlyManualStepStore.runsFor.
         * @param stepIds the steps
         * @param releaseId the release
         * @return the runs
         */
        public List<RLY_Manual_Step_Run__c> queryRunsFor(Set<Id> stepIds, Id releaseId) {
            return [SELECT Id, Name, Step__c, Step__r.Title__c, Step__r.Timing__c, Step__r.Category__c, Step__r.Release__r.Name,
                           Release__c, Org__c, Org__r.Name, Org__r.Role__c, Org__r.Stage_Order__c, Status__c, Done_By__r.Name,
                           Done_On__c, Note__c, Order__c
                    FROM RLY_Manual_Step_Run__c WHERE Step__c IN :stepIds OR Release__c = :releaseId
                    WITH SYSTEM_MODE ORDER BY Order__c ASC NULLS LAST, Name ASC LIMIT 5000];
        }

        /**
         * @description See RlyManualStepStore.runsOfReleases.
         * @param releaseIds the releases
         * @return the runs
         */
        public List<RLY_Manual_Step_Run__c> queryRunsOfReleases(Set<Id> releaseIds) {
            return [SELECT Id, Step__c, Step__r.Timing__c, Release__c, Org__c, Status__c, Order__c
                    FROM RLY_Manual_Step_Run__c WHERE Release__c IN :releaseIds
                    WITH SYSTEM_MODE ORDER BY Order__c ASC NULLS LAST, Name ASC LIMIT 5000];
        }

        /**
         * @description See RlyManualStepStore.run.
         * @param runId the run
         * @return the run, or null
         */
        public RLY_Manual_Step_Run__c queryRun(Id runId) {
            List<RLY_Manual_Step_Run__c> rows = [SELECT Id, Step__c, Step__r.Timing__c, Step__r.Title__c, Release__c, Org__c, Org__r.Name,
                                                        Status__c, Note__c, Done_By__c, Done_On__c
                                                 FROM RLY_Manual_Step_Run__c WHERE Id = :runId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description See RlyManualStepStore.openBefore.
         * @param releaseId the release
         * @param orgId the org
         * @param skipRunId the run not to count, or null
         * @return the number
         */
        public Integer countOpenBefore(Id releaseId, Id orgId, Id skipRunId) {
            return [SELECT COUNT() FROM RLY_Manual_Step_Run__c
                    WHERE Release__c = :releaseId AND Org__c = :orgId AND Status__c = 'To_Do'
                        AND Step__r.Timing__c = 'Before_Deploy' AND Id != :skipRunId
                    WITH SYSTEM_MODE];
        }

        /**
         * @description See RlyManualStepStore.stepCounts.
         * @param releaseIds the releases
         * @return the number by release
         */
        public Map<Id, Integer> countSteps(Set<Id> releaseIds) {
            Map<Id, Integer> out = new Map<Id, Integer>();
            for (AggregateResult a : [SELECT Release__c relId, COUNT(Id) n FROM RLY_Manual_Step__c
                                      WHERE Release__c IN :releaseIds WITH SYSTEM_MODE GROUP BY Release__c]) {
                out.put((Id) a.get('relId'), (Integer) a.get('n'));
            }
            return out;
        }

        /**
         * @description See RlyManualStepStore.openCounts.
         * @param releaseIds the releases
         * @return the number by release
         */
        public Map<Id, Integer> countOpen(Set<Id> releaseIds) {
            Map<Id, Integer> out = new Map<Id, Integer>();
            for (AggregateResult a : [SELECT Release__c relId, COUNT(Id) n FROM RLY_Manual_Step_Run__c
                                      WHERE Release__c IN :releaseIds AND Status__c = 'To_Do' WITH SYSTEM_MODE GROUP BY Release__c]) {
                out.put((Id) a.get('relId'), (Integer) a.get('n'));
            }
            return out;
        }

        /**
         * @description See RlyManualStepStore.saveSteps.
         * @param steps the steps
         */
        public void upsertSteps(List<RLY_Manual_Step__c> steps) {
            upsert as system steps;
        }

        /**
         * @description See RlyManualStepStore.deleteStep.
         * @param stepId the step
         */
        public void removeStep(Id stepId) {
            List<RLY_Manual_Step_Run__c> runs = [SELECT Id FROM RLY_Manual_Step_Run__c WHERE Step__c = :stepId WITH SYSTEM_MODE LIMIT 5000];
            delete as system runs;
            RLY_Manual_Step__c step = new RLY_Manual_Step__c(Id = stepId);
            delete as system step;
        }

        /**
         * @description See RlyManualStepStore.saveRuns.
         * @param runs the runs
         */
        public void upsertRuns(List<RLY_Manual_Step_Run__c> runs) {
            upsert as system runs;
        }

        /**
         * @description See RlyManualStepStore.deleteRuns.
         * @param runs the runs
         */
        public void removeRuns(List<RLY_Manual_Step_Run__c> runs) {
            delete as system runs;
        }
    }
}
