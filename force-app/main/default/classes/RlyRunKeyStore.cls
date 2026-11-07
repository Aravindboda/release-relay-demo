/**
 * @description Run signing (build 48): where the run-signing key lives. The protected hierarchy custom setting
 * RLY_Run_Key__c (org default row) holds it; users can't read or write it themselves, so it is read and written in
 * system mode in the private inner without sharing class. Callers check who may change it (RlyRunSigningController).
 * Also reads a release's Validated_Head__c when the caller's query didn't carry it.
 */
public with sharing class RlyRunKeyStore {

    /**
     * @description The run-signing key, or null when none is set (runs aren't signed, unsigned results are accepted).
     * @return the Base64 key, or null
     */
    public static String key() {
        String k = new SystemAccess().orgRow().Key__c;
        return String.isBlank(k) ? null : k.trim();
    }

    /**
     * @description The org default row (a blank one when none is saved yet).
     * @return the row
     */
    public static RLY_Run_Key__c row() {
        return new SystemAccess().orgRow();
    }

    /**
     * @description Saves the key and who set it.
     * @param key the Base64 key (checked by the caller)
     */
    public static void save(String key) {
        SystemAccess access = new SystemAccess();
        RLY_Run_Key__c r = access.orgRow();
        r.Key__c = key;
        r.Set_On__c = System.now();
        r.Set_By__c = UserInfo.getName().left(121);
        access.save(r);
    }

    /**
     * @description The head the release's passing checks validated (Validated_Head__c), read again when the caller's
     * query didn't carry it.
     * @param rel the release
     * @return the head, or null
     */
    public static String validatedHeadOf(RLY_Release__c rel) {
        return (String) validated(rel).get('Validated_Head__c');
    }

    /**
     * @description The merge's options from the passing check: expectHead (Validated_Head__c) and validationAttempt
     * (Validated_Attempt__c), each only when set.
     * @param rel the release
     * @return the options to add
     */
    public static Map<String, Object> validatedOptions(RLY_Release__c rel) {
        Map<String, Object> v = validated(rel);
        Map<String, Object> out = new Map<String, Object>();
        if (String.isNotBlank((String) v.get('Validated_Head__c'))) {
            out.put('expectHead', v.get('Validated_Head__c'));
        }
        if (String.isNotBlank((String) v.get('Validated_Attempt__c'))) {
            out.put('validationAttempt', v.get('Validated_Attempt__c'));
        }
        return out;
    }

    /**
     * @description With a run-signing key set, the pipeline refuses a merge without expectHead: a release whose checks
     * passed before build 48 (no Validated_Head__c) runs its checks again instead of dispatching.
     * @param rel the release about to merge
     */
    public static void requireValidatedHead(RLY_Release__c rel) {
        if (key() != null && String.isBlank(validatedHeadOf(rel))) {
            throw new RlyReleaseException('Run the checks again: ' + rel.Name + '\'s checks passed before the hub signed its runs, '
                + 'so the commit they validated isn\'t known. Approve it after they pass.');
        }
    }

    /**
     * @description Pins the approval to what a validation checked: when it passed with the release branch head
     * (validate.json headSha), Validated_Head__c is that head and Validated_Attempt__c its run token (attempt, else the
     * release's Check_Token__c); otherwise both are cleared (a failed check, or an older pipeline without headSha).
     * @param rel the release, with Validation_Status__c just set
     * @param val the validate.json result
     */
    public static void pinValidation(RLY_Release__c rel, Map<String, Object> val) {
        Object head = val.get('headSha');
        String sha = head == null ? '' : String.valueOf(head).trim();
        Boolean pinned = rel.Validation_Status__c == 'Passed' && Pattern.matches('[0-9a-fA-F]{40}', sha);
        Object attempt = val.get('attempt');
        String token = attempt == null ? rel.Check_Token__c : String.valueOf(attempt);
        rel.Validated_Head__c = pinned ? sha.toLowerCase() : null;
        rel.Validated_Attempt__c = pinned && token != null ? token.left(40) : null;
    }

    // Validated_Head__c and Validated_Attempt__c, from the release or read again.
    private static Map<String, Object> validated(RLY_Release__c rel) {
        Map<String, Object> present = rel.getPopulatedFieldsAsMap();
        if (present.containsKey('Validated_Head__c') || rel.Id == null) {
            return present;
        }
        RLY_Release__c row = new SystemAccess().validatedRow(rel.Id);
        return row == null ? new Map<String, Object>() : row.getPopulatedFieldsAsMap();
    }

    /** @description RLY_Run_Key__c is a protected setting and releases are hub records: system mode. */
    private without sharing class SystemAccess {

        /**
         * @description The org default row (a blank one when none is saved yet).
         * @return the row
         */
        public RLY_Run_Key__c orgRow() {
            RLY_Run_Key__c r = RLY_Run_Key__c.getOrgDefaults();
            if (r == null) {
                r = new RLY_Run_Key__c();
            }
            if (r.Id == null) {
                r.SetupOwnerId = UserInfo.getOrganizationId();
            }
            return r;
        }

        /**
         * @description Saves the row.
         * @param r the row
         */
        public void save(RLY_Run_Key__c r) {
            if (r.Id == null) {
                Database.insert(r, true, AccessLevel.SYSTEM_MODE);
            } else {
                Database.update(r, true, AccessLevel.SYSTEM_MODE);
            }
        }

        /**
         * @description A release's Validated_Head__c and Validated_Attempt__c.
         * @param releaseId the release
         * @return the row, or null
         */
        public RLY_Release__c validatedRow(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Validated_Head__c, Validated_Attempt__c FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
