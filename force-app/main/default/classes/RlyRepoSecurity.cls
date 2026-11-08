/**
 * @description Pipeline tab, Repository security card (build 48): reads, through the active Git connection, whether the
 * pipeline branch is protected and needs a reviewed pull request, whether each org's Git environment only deploys from
 * the pipeline branch, and whether the run-signing key RELAY_RUN_KEY is there (names only: values are never read). It
 * lists what's missing with a "how to fix" line each. Read-only; a read that fails is shown on its row, never thrown.
 * GitHub (RlyRepoSecurityGitHub) and GitLab (RlyRepoSecurityGitLab); other providers get one row saying so.
 */
public with sharing class RlyRepoSecurity {

    /** @description Row state: in place. */
    public static final String OK = 'ok';
    /** @description Row state: missing; the fix line says what to do. */
    public static final String MISSING = 'missing';
    /** @description Row state: couldn't be read. */
    public static final String UNKNOWN = 'unknown';
    /** @description The secret or variable the pipeline reads the run-signing key from. */
    public static final String KEY_NAME = 'RELAY_RUN_KEY';

    /** @description The card's report. */
    public class Report {
        /** @description GitHub, GitLab… */
        @AuraEnabled public String provider;
        /** @description owner/repo or group/project. */
        @AuraEnabled public String repository;
        /** @description The pipeline branch (main). */
        @AuraEnabled public String branch;
        /** @description When it was read. */
        @AuraEnabled public Datetime checkedOn;
        /** @description Rows that are missing. */
        @AuraEnabled public Integer missing = 0;
        /** @description Rows that couldn't be read. */
        @AuraEnabled public Integer unknown = 0;
        /** @description One row per protection. */
        @AuraEnabled public List<Item> items = new List<Item>();
    }

    /** @description One protection. */
    public class Item {
        /** @description A stable key (branch, key, env:sit). */
        @AuraEnabled public String key;
        /** @description What is checked, for example "main is protected". */
        @AuraEnabled public String label;
        /** @description ok, missing or unknown. */
        @AuraEnabled public String state = UNKNOWN;
        /** @description What was found. */
        @AuraEnabled public String detail;
        /** @description How to fix it (missing and unknown rows). */
        @AuraEnabled public String fix;

        /**
         * @description Sets what was found.
         * @param newState ok, missing or unknown
         * @param what what was found
         * @return this row
         */
        public Item found(String newState, String what) {
            state = newState;
            detail = what == null ? null : what.left(400);
            return this;
        }

        /**
         * @description Sets how to fix it, unless the row is ok or already says how.
         * @param how the fix
         * @return this row
         */
        public Item orFix(String how) {
            fix = state == OK ? null : (fix == null ? how : fix);
            return this;
        }

        /**
         * @description The row couldn't be read.
         * @param why the reason (RlyRepoSecurity.why)
         * @param permission the token permission the read needs
         * @return this row
         */
        public Item cantRead(String why, String permission) {
            return found(UNKNOWN, 'Couldn\'t read: ' + why).orFix('Give the connection\'s token ' + permission + ', or check it by hand.');
        }
    }

    /**
     * @description Reads the active connection's repository.
     * @return the report (never throws for a failed read)
     */
    public static Report check() {
        Report r = new Report();
        r.checkedOn = System.now();
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn == null) {
            r.items.add(row('connection', 'Git connection').found(MISSING, 'No Git connection yet.').orFix('Set up "Where the code lives" first.'));
            return counted(r);
        }
        r.provider = conn.Provider__c;
        r.repository = conn.Repository__c;
        r.branch = String.isBlank(conn.Pipeline_Branch__c) ? 'main' : conn.Pipeline_Branch__c.trim();
        RlyGit git;
        try {
            git = RlyGit.forConnection(conn);
        } catch (Exception e) {
            r.items.add(row('connection', 'Git connection').found(UNKNOWN, e.getMessage()).orFix('Fix the Git connection, then check again.'));
            return counted(r);
        }
        List<String> envs = orgEnvironments();
        if (conn.Provider__c == 'GitHub') {
            r.items.addAll(new RlyRepoSecurityGitHub(git, r.branch).items());
            r.items.addAll(new RlyRepoSecurityGitHubKey(git).items(envs));
            r.items.addAll(new RlyRepoSecurityGitHubEnvs(git, r.branch).items(envs));
        } else if (conn.Provider__c == 'GitLab') {
            r.items.addAll(new RlyRepoSecurityGitLab(git, r.branch).items(envs));
        } else {
            r.items.add(row('provider', 'Repository security').found(UNKNOWN, 'This check reads GitHub and GitLab repositories.')
                .orFix('Check branch protection, environments and the ' + KEY_NAME + ' secret by hand in ' + conn.Provider__c + '.'));
        }
        return counted(r);
    }

    /**
     * @description A GitHub read under the connection's repository (/repos/owner/name + path).
     * @param git the Git provider (GitHub)
     * @param path the path after the repository
     * @return the answer
     */
    public static HttpResponse gitHubGet(RlyGit git, String path) {
        return git.request(new RlyGitRequest('GET', '/repos/' + git.connection().Repository__c.trim() + path, null));
    }

    /**
     * @description A new row (state unknown until found).
     * @param key a stable key
     * @param label what is checked
     * @return the row
     */
    public static Item row(String key, String label) {
        Item i = new Item();
        i.key = key;
        i.label = label;
        return i;
    }

    /**
     * @description Each registered org's Git environment, once each, in name order (at most 20).
     * @return the environment names
     */
    public static List<String> orgEnvironments() {
        return new Store().environments();
    }

    /**
     * @description Why an answer can't be used.
     * @param res the answer
     * @return the reason
     */
    public static String why(HttpResponse res) {
        Integer code = res.getStatusCode();
        return 'the answer was ' + code + (code == 403 || code == 401 ? ': the token can\'t read this.' : '.');
    }

    /**
     * @description The JSON answer as a map (empty when it isn't one).
     * @param res the answer
     * @return the map
     */
    public static Map<String, Object> asMap(HttpResponse res) {
        Object o = parsed(res);
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
    }

    /**
     * @description The JSON answer as a list (empty when it isn't one).
     * @param res the answer
     * @return the list
     */
    public static List<Object> asList(HttpResponse res) {
        Object o = parsed(res);
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    /**
     * @description A number from an answer.
     * @param o the value
     * @return the number (0 when absent)
     */
    public static Integer num(Object o) {
        try {
            return o == null ? 0 : Integer.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return 0;
        }
    }

    private static Object parsed(HttpResponse res) {
        try {
            return String.isBlank(res.getBody()) ? null : JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            return null;
        }
    }

    private static Report counted(Report r) {
        for (Item i : r.items) {
            r.missing += i.state == MISSING ? 1 : 0;
            r.unknown += i.state == UNKNOWN ? 1 : 0;
        }
        return r;
    }

    /** @description Registered orgs are hub records: read in system mode (names of their Git environments only). */
    private without sharing class Store {

        /**
         * @description Each org's Git environment, once each, in name order.
         * @return the environment names
         */
        public List<String> environments() {
            Set<String> seen = new Set<String>();
            List<String> out = new List<String>();
            for (RLY_Org__c o : [SELECT Git_Environment__c FROM RLY_Org__c WHERE Git_Environment__c != null
                                 WITH SYSTEM_MODE ORDER BY Git_Environment__c LIMIT 20]) {
                String env = o.Git_Environment__c.trim();
                if (env != '' && seen.add(env.toLowerCase())) {
                    out.add(env);
                }
            }
            return out;
        }
    }
}
