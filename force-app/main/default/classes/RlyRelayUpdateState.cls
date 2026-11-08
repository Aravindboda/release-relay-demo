/**
 * @description Install Release Relay update (Pipeline tab, Advanced): the four steps of one update and where each one
 * is. The steps run in order (the test org's check, its install, production's check, production's install); a step
 * opens only after the one before it passed for the same update, and only while no step runs. Each started step is
 * kept as JSON in RLY_Relay_Update__c.Steps__c. Pure logic: no queries, no callouts.
 */
public with sharing class RlyRelayUpdateState {

    /** @description Step: check the update in the test org (mode hub, check only). */
    public static final String TEST_CHECK = 'test-check';
    /** @description Step: install it in the test org (mode merge, quick deploy). */
    public static final String TEST_INSTALL = 'test-install';
    /** @description Step: check it in production. */
    public static final String PROD_CHECK = 'prod-check';
    /** @description Step: install it in production. */
    public static final String PROD_INSTALL = 'prod-install';
    /** @description The steps in order. */
    public static final List<String> ORDER = new List<String>{ TEST_CHECK, TEST_INSTALL, PROD_CHECK, PROD_INSTALL };
    /** @description The step's run was started and has no result yet. */
    public static final String RUNNING = 'Running';
    /** @description A check passed. */
    public static final String PASSED = 'Passed';
    /** @description An install deployed. */
    public static final String INSTALLED = 'Installed';
    /** @description The step failed. */
    public static final String FAILED = 'Failed';

    /** @description One started step. */
    public class Step {
        /** @description The request id the run started with (REL- and the hub's clock); an install keeps its check's. */
        public String requestId;
        /** @description The branch the hub made from the target with the zip on it. */
        public String branch;
        /** @description The branch the update goes into. */
        public String target;
        /** @description The org's Git environment. */
        public String environment;
        /** @description The run's token (options.attempt), echoed in its result files. */
        public String token;
        /** @description An install: its check's token (options.validationAttempt). */
        public String checkToken;
        /** @description A check: the branch head it validated (validate.json headSha); an install: the head it expects. */
        public String head;
        /** @description RUNNING, PASSED, INSTALLED or FAILED. */
        public String status;
        /** @description When it was started. */
        public Datetime startedAt;
        /** @description Who started it. */
        public String startedBy;
        /** @description Link to the run (https only). */
        public String runUrl;
        /** @description Tests run, from the result. */
        public Integer testsRun;
        /** @description Test failures and component errors, one line each. */
        public List<String> failures = new List<String>();
        /** @description The result's message, or why there is none. */
        public String message;
        /** @description When the result was written (from the result file). */
        public String finishedAt;
    }

    /**
     * @description The started steps of an update.
     * @param u the update, with Steps__c
     * @return the steps by key (empty when none or unreadable)
     */
    public static Map<String, Step> read(RLY_Relay_Update__c u) {
        if (u == null || String.isBlank(u.Steps__c)) {
            return new Map<String, Step>();
        }
        try {
            Map<String, Step> steps = (Map<String, Step>) JSON.deserialize(u.Steps__c, Map<String, Step>.class);
            return steps == null ? new Map<String, Step>() : steps;
        } catch (Exception e) {
            return new Map<String, Step>();
        }
    }

    /**
     * @description Puts the steps back on the update (not saved).
     * @param u the update
     * @param steps the steps by key
     */
    public static void write(RLY_Relay_Update__c u, Map<String, Step> steps) {
        u.Steps__c = JSON.serialize(steps);
    }

    /**
     * @description Whether a step has passed (a check) or deployed (an install).
     * @param s the step, or null
     * @return true when it is done
     */
    public static Boolean isDone(Step s) {
        return s != null && (s.status == PASSED || s.status == INSTALLED);
    }

    /**
     * @description The step that is running, if any.
     * @param steps the steps by key
     * @return its key, or null
     */
    public static String running(Map<String, Step> steps) {
        for (String key : ORDER) {
            Step s = steps.get(key);
            if (s != null && s.status == RUNNING) {
                return key;
            }
        }
        return null;
    }

    /**
     * @description Whether a step may start now: nothing runs, no later step has started, it hasn't passed, and the step
     * before it passed. The first step starts only on an update that hasn't run it (running it again prepares a new one).
     * @param steps the steps by key
     * @param key the step
     * @return true when it may start
     */
    public static Boolean canStart(Map<String, Step> steps, String key) {
        Integer i = ORDER.indexOf(key);
        if (i < 0 || running(steps) != null || laterStarted(steps, i)) {
            return false;
        }
        Step own = steps.get(key);
        if (i == 0) {
            return own == null;
        }
        return !isDone(own) && isDone(steps.get(ORDER[i - 1]));
    }

    /**
     * @description Whether the first step can run again on a new update (it failed and nothing runs).
     * @param steps the steps by key
     * @return true when it can
     */
    public static Boolean canRetryFirst(Map<String, Step> steps) {
        Step firstStep = steps.get(TEST_CHECK);
        return firstStep != null && firstStep.status == FAILED && running(steps) == null && !laterStarted(steps, 0);
    }

    /**
     * @description Whether a step is a check (mode hub) rather than an install (mode merge).
     * @param key the step
     * @return true for the two checks
     */
    public static Boolean isCheck(String key) {
        return key == TEST_CHECK || key == PROD_CHECK;
    }

    /**
     * @description The check an install merges.
     * @param installKey TEST_INSTALL or PROD_INSTALL
     * @return its check's key
     */
    public static String checkOf(String installKey) {
        return installKey == TEST_INSTALL ? TEST_CHECK : PROD_CHECK;
    }

    private static Boolean laterStarted(Map<String, Step> steps, Integer i) {
        for (Integer j = i + 1; j < ORDER.size(); j++) {
            if (steps.containsKey(ORDER[j])) {
                return true;
            }
        }
        return false;
    }
}
