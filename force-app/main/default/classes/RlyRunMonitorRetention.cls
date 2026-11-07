/**
 * @description Retention for the pipeline runs (RLY_Pipeline_Run__c): each nightly archive call that isn't skipped
 * (RlyArchiveNightly) removes runs started before the Retention days set on the Pipeline tab, at most 2,000 per call
 * (the nightly job calls again for each archive pass), and empties the Recycle Bin for them. Same pass style as the
 * release archive: no async Apex. A failure here never stops the release archive; the next call tries again. Sync status
 * checks (RLY_Sync_Check__c) older than the same days go first (build 38).
 */
public with sharing class RlyRunMonitorRetention {

    /** @description Most runs removed per call. */
    @TestVisible
    private static Integer perCall = 2000;

    /**
     * @description Removes the runs older than the Retention days.
     * @param days the Retention days (null keeps every run)
     * @return how many runs were removed
     */
    public static Integer prune(Integer days) {
        if (days == null || days <= 0) {
            return 0;
        }
        Datetime cutoff = RlyArchiveService.cutoff(days);
        try {
            RlySyncStore.removeOlderThan(cutoff, perCall); // Sync status checks go by the same retention (build 38)
        } catch (DmlException e) {
            cutoff = RlyArchiveService.cutoff(days); // a locked check waits for the next night; the runs still go
        }
        try {
            return RlyRunMonitorStore.removeOlderThan(cutoff, perCall);
        } catch (DmlException e) {
            return 0;
        }
    }
}
