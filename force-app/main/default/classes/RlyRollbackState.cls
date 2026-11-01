/**
 * @description A release's latest rollback, kept in its own fields (Rollback_Status__c Running, Rolled_Back or Failed,
 * Rollback_Org__c, Rollback_By__c, Rollback_On__c, Rollback_Reason__c, Rollback_Result__c, Rollback_Token__c); the
 * release's Status__c stays as it was. The flow's release query (RlyReleaseStore) doesn't read these fields, so they
 * are read here, once per release and transaction, and a change is remembered before it is saved so the Slack card
 * built in the same transaction shows it. Releases are shared hub records: read and saved in system mode, in the
 * private inner without sharing class, and only the rollback fields are written.
 */
public with sharing class RlyRollbackState {

    /** @description Rollback_Status__c while the pipeline deploys the snapshot. */
    public static final String RUNNING = 'Running';
    /** @description Rollback_Status__c after the snapshot was deployed. */
    public static final String ROLLED_BACK = 'Rolled_Back';
    /** @description Rollback_Status__c when the rollback failed (the org is unchanged). */
    public static final String FAILED = 'Failed';

    private static final String STATUS_FIELD = 'Rollback_Status__c';
    private static final Map<Id, RLY_Release__c> ROWS = new Map<Id, RLY_Release__c>();

    /**
     * @description A release's rollback fields (Rollback_Org__r.Name and Rollback_By__r.Name included), as saved or as
     * changed earlier in this transaction.
     * @param releaseId the release
     * @return the row (all fields null when it was never rolled back)
     */
    public static RLY_Release__c rowOf(Id releaseId) {
        if (releaseId == null) {
            return new RLY_Release__c();
        }
        if (!ROWS.containsKey(releaseId)) {
            ROWS.putAll(new SystemAccess().readRows(new Set<Id>{ releaseId }));
            if (!ROWS.containsKey(releaseId)) {
                ROWS.put(releaseId, new RLY_Release__c(Id = releaseId));
            }
        }
        return ROWS.get(releaseId);
    }

    /**
     * @description The rollback fields of several releases in one query (the Releases tab's rows, the CSV).
     * @param releaseIds the releases
     * @return the rows by release Id
     */
    public static Map<Id, RLY_Release__c> rowsOf(Set<Id> releaseIds) {
        Set<Id> missing = new Set<Id>();
        for (Id i : releaseIds) {
            if (!ROWS.containsKey(i)) {
                missing.add(i);
            }
        }
        if (!missing.isEmpty()) {
            ROWS.putAll(new SystemAccess().readRows(missing));
        }
        Map<Id, RLY_Release__c> out = new Map<Id, RLY_Release__c>();
        for (Id i : releaseIds) {
            out.put(i, ROWS.containsKey(i) ? ROWS.get(i) : new RLY_Release__c(Id = i));
        }
        return out;
    }

    /**
     * @description Forgets what was read in this transaction (a test that changes the fields itself reads them again).
     */
    @TestVisible
    private static void forget() {
        ROWS.clear();
    }

    /**
     * @description Remembers a change for this transaction (the Slack card and the page read it before it is saved).
     * @param row the rollback fields, with Rollback_Org__r and Rollback_By__r names set
     */
    public static void remember(RLY_Release__c row) {
        ROWS.put(row.Id, row);
    }

    /**
     * @description Saves the rollback fields (and remembers them).
     * @param row the release Id and its rollback fields
     */
    public static void save(RLY_Release__c row) {
        remember(row);
        new SystemAccess().updateRow(new RLY_Release__c(Id = row.Id, Rollback_Status__c = row.Rollback_Status__c,
            Rollback_Org__c = row.Rollback_Org__c, Rollback_By__c = row.Rollback_By__c, Rollback_On__c = row.Rollback_On__c,
            Rollback_Reason__c = row.Rollback_Reason__c, Rollback_Result__c = row.Rollback_Result__c,
            Rollback_Token__c = row.Rollback_Token__c));
    }

    /**
     * @description Whether a rollback of the release is running.
     * @param releaseId the release
     * @return true while it runs
     */
    public static Boolean isRunning(Id releaseId) {
        return rowOf(releaseId).Rollback_Status__c == RUNNING;
    }

    /**
     * @description The org name of the latest rollback.
     * @param row the rollback fields
     * @return the name, or an empty string
     */
    public static String orgName(RLY_Release__c row) {
        return row.Rollback_Org__r == null ? '' : row.Rollback_Org__r.Name;
    }

    /**
     * @description Who started the latest rollback.
     * @param row the rollback fields
     * @return the name, or an empty string
     */
    public static String byName(RLY_Release__c row) {
        if (row.Rollback_By__r != null) {
            return row.Rollback_By__r.Name;
        }
        return row.Rollback_By__c == null ? '' : RlyReleaseStore.userName(row.Rollback_By__c);
    }

    /**
     * @description The pill: "Rolling back in PROD", "Rolled back in PROD" or "Rollback failed in PROD" (the org's name).
     * @param row the rollback fields
     * @return the label, or null when the release was never rolled back
     */
    public static String label(RLY_Release__c row) {
        String status = row.Rollback_Status__c;
        if (status == RUNNING) {
            return 'Rolling back in ' + orgName(row);
        }
        if (status == ROLLED_BACK) {
            return 'Rolled back in ' + orgName(row);
        }
        return status == FAILED ? 'Rollback failed in ' + orgName(row) : null;
    }

    /**
     * @description The latest rollback's JSON (what was started and, once finished, rollback.json).
     * @param row the rollback fields
     * @return the parsed object (empty when there's none)
     */
    public static Map<String, Object> result(RLY_Release__c row) {
        return RlyEvidenceText.parse(row.Rollback_Result__c);
    }

    /**
     * @description "restored 4, removed 1", from the rollback's result.
     * @param row the rollback fields
     * @return the words, or an empty string before it finished
     */
    public static String counts(RLY_Release__c row) {
        Map<String, Object> r = result(row);
        if (r.get('restored') == null && r.get('removed') == null) {
            return '';
        }
        return 'restored ' + RlyEvidenceText.text(RlyEvidenceText.str(r.get('restored'))) + ', removed '
            + RlyEvidenceText.text(RlyEvidenceText.str(r.get('removed')));
    }

    /**
     * @description What the Slack card's fingerprint (RlySlackCardState) adds: the rollback state, when the release was
     * read or changed with it (a release read without it adds nothing, so other writers see no change).
     * @param rel the release
     * @return the rollback state and org, or an empty string
     */
    public static String fingerprint(RLY_Release__c rel) {
        Map<String, Object> fields = rel.getPopulatedFieldsAsMap();
        return fields.containsKey(STATUS_FIELD) ? String.valueOf(fields.get(STATUS_FIELD)) + '@' + String.valueOf(fields.get('Rollback_Org__c')) : '';
    }

    /**
     * @description The Slack card's rollback line: ":leftwards_arrow_with_hook: Rolled back in PROD by Ana · restored 4, removed 1".
     * @param rel the release
     * @return the line (mrkdwn, starting with a line break), or an empty string
     */
    public static String slackLine(RLY_Release__c rel) {
        try {
            RLY_Release__c row = rowOf(rel.Id);
            String text = label(row);
            if (text == null) {
                return '';
            }
            String emoji = row.Rollback_Status__c == FAILED ? ':x:' : ':leftwards_arrow_with_hook:';
            String how = row.Rollback_Status__c == FAILED ? '' : counts(row);
            String whom = String.isBlank(byName(row)) ? '' : ' by ' + byName(row);
            return '\n' + emoji + ' ' + RlySlackMessage.esc(text + whom + (String.isBlank(how) ? '' : ' · ' + how))
                + (String.isBlank(row.Rollback_Reason__c) ? '' : '\n_“' + RlySlackMessage.esc(row.Rollback_Reason__c) + '”_');
        } catch (Exception e) {
            return ''; // the rollback fields couldn't be read: the card goes on without the line
        }
    }

    /** @description Shared hub releases: the rollback fields are read and saved in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description The rollback fields of some releases.
         * @param ids the releases
         * @return the rows by Id
         */
        public Map<Id, RLY_Release__c> readRows(Set<Id> ids) {
            return new Map<Id, RLY_Release__c>([SELECT Id, Rollback_Status__c, Rollback_Org__c, Rollback_Org__r.Name, Rollback_By__c,
                    Rollback_By__r.Name, Rollback_On__c, Rollback_Reason__c, Rollback_Result__c, Rollback_Token__c
                FROM RLY_Release__c WHERE Id IN :ids WITH SYSTEM_MODE]);
        }

        /**
         * @description Saves the rollback fields.
         * @param row the row (Id and rollback fields only)
         */
        public void updateRow(RLY_Release__c row) {
            update as system row;
        }
    }
}
