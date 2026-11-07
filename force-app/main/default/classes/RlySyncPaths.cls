/**
 * @description Sync status: the picked components of a back promote or push (RLY_Release__c.Sync_Paths__c, written by
 * RlySyncPromote) as options for pipeline mode sync (pipeline files v23): paths (the files to bring), keys (for the
 * commit message) and branchOnly (a developer org gets its branch only). A release without picks syncs the whole branch.
 */
public with sharing class RlySyncPaths {

    /**
     * @description Adds the picks to a sync run's options.
     * @param rel the back promote release
     * @param options the run's options
     */
    public static void addOptions(RLY_Release__c rel, Map<String, Object> options) {
        Object raw = rel.getPopulatedFieldsAsMap().get('Sync_Paths__c');
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return;
        }
        Map<String, Object> picked;
        try {
            picked = (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(raw));
        } catch (Exception e) {
            picked = null;
        }
        if (picked == null) {
            // Never fall back to the whole branch: the run doesn't start.
            throw new RlyReleaseException('The picked components couldn\'t be read: pick them again on the Sync status tab.');
        }
        for (String k : new List<String>{ 'paths', 'keys', 'branchOnly' }) {
            if (picked.containsKey(k)) {
                options.put(k, picked.get(k));
            }
        }
    }
}
