/**
 * @description Pipeline tab: the repository's per-org values (.relay/values.json) and quality gates (.relay/gates.json),
 * read from the pipeline branch for the read-only cards. Everyone with the tab sees them; they're edited in Git.
 * One callout per file, no DML. Values are text in Git, so the page warns never to put passwords there.
 */
public with sharing class RlyRepoSettings {

    /** @description The per-org values file. */
    public static final String VALUES_PATH = '.relay/values.json';
    /** @description The quality gates file. */
    public static final String GATES_PATH = '.relay/gates.json';

    /** @description What the two cards show. */
    public class Settings {
        /** @description The branch the files were read from (the pipeline branch), or null without a Git connection. */
        @AuraEnabled public String branch;
        /** @description When the files were read. */
        @AuraEnabled public Datetime readAt;
        /** @description Why the files couldn't be read (no connection, provider error), or null. */
        @AuraEnabled public String message;
        /** @description The named values, in the file's order (keys starting with _ left out). */
        @AuraEnabled public List<ValueRow> values = new List<ValueRow>();
        /** @description Every environment name the values use, first seen first. */
        @AuraEnabled public List<String> environments = new List<String>();
        /** @description Why the values file couldn't be read, or null. */
        @AuraEnabled public String valuesError;
        /** @description The gates, one row each, or empty when the file sets none. */
        @AuraEnabled public List<GateRow> gates = new List<GateRow>();
        /** @description Why the gates file couldn't be read, or null. */
        @AuraEnabled public String gatesError;
        /** @description The values file is on the branch (false: the page offers to create it). */
        @AuraEnabled public Boolean valuesFound = false;
        /** @description The gates file is on the branch (false: the page offers to create it). */
        @AuraEnabled public Boolean gatesFound = false;
    }

    /** @description One named value and its value per Git environment. */
    public class ValueRow {
        /** @description The placeholder name, for example PAYMENT_URL. */
        @AuraEnabled public String name;
        /** @description Git environment name to value. */
        @AuraEnabled public Map<String, String> byEnvironment = new Map<String, String>();
    }

    /** @description One quality gate in words. */
    public class GateRow {
        /** @description scan, perClass, orgWide or tests. */
        @AuraEnabled public String key;
        /** @description What the gate is, for example Code scan. */
        @AuraEnabled public String label;
        /** @description What it's set to, or Not set. */
        @AuraEnabled public String text;
        /** @description The file sets this gate. */
        @AuraEnabled public Boolean isSet = false;
    }

    /**
     * @description Reads both files from the pipeline branch (callouts only, nothing saved).
     * @return the values and gates, or a message when they can't be read
     */
    @AuraEnabled(cacheable=false)
    public static Settings read() {
        Settings s = new Settings();
        s.readAt = System.now();
        RLY_Git_Connection__c conn = new Data().git();
        if (conn == null || String.isBlank(conn.Pipeline_Branch__c)) {
            s.message = 'No Git connection yet: the values and gates are read from the repository once it\'s set up.';
            return s;
        }
        s.branch = conn.Pipeline_Branch__c.trim();
        try {
            RlyGit git = RlyGit.forConnection(conn);
            String valuesText = git.getFileRaw(VALUES_PATH, s.branch);
            String gatesText = git.getFileRaw(GATES_PATH, s.branch);
            s.valuesFound = valuesText != null;
            s.gatesFound = gatesText != null;
            fillValues(s, valuesText);
            fillGates(s, gatesText);
        } catch (Exception e) {
            s.message = ('Couldn\'t read ' + VALUES_PATH + ' and ' + GATES_PATH + ' from ' + s.branch + ': ' + e.getMessage()).left(1000);
        }
        return s;
    }

    private static void fillValues(Settings s, String text) {
        try {
            s.values = RlyRepoParse.valueRows(RlyRepoParse.objectOf(text));
        } catch (Exception e) {
            s.valuesError = VALUES_PATH + ' isn\'t a valid JSON object, so the values can\'t be shown.';
        }
        s.environments = RlyRepoParse.environments(s.values);
    }

    private static void fillGates(Settings s, String text) {
        try {
            s.gates = RlyRepoParse.gateRows(RlyRepoParse.objectOf(text));
        } catch (Exception e) {
            s.gatesError = GATES_PATH + ' isn\'t a valid JSON object, so the gates can\'t be shown.';
        }
    }

    /** @description The Git connection is hub configuration: read in system mode for everyone with the tab. */
    private without sharing class Data {

        /**
         * @description The hub's Git connection.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
