/**
 * @description Shares one status read of a release between everyone who has it open (RlyStatusReader.advance, called by
 * RlyReleasesController.refreshRelease from the release page and the Releases tab). A release read less than
 * FRESH_SECONDS ago is returned as saved: only one viewer per window calls Git, the org and Slack, the others read the
 * record. When two viewers save the same release at the same moment, the one that meets the row lock
 * (UNABLE_TO_LOCK_ROW) rolls its own saves back and returns the release as the other one saved it, instead of an error.
 *
 * Claim before reading: a release that looks stale is re-read FOR UPDATE before any callout (a query, not DML, so the
 * callouts may follow) and its freshness checked again on the locked row. A second viewer waits for the first one's
 * transaction to commit, then sees the fresh Last_Synced__c and returns the saved release; when the lock can't be had
 * in time it returns the saved release too. So only one viewer at a time calls Git, the org and Slack for a release.
 * The page's Check now button asks with CHECK_NOW_SECONDS instead of FRESH_SECONDS.
 */
public with sharing class RlySharedRead {

    /** @description A release read this many seconds ago or less is returned as saved, without reading it again. */
    public static final Integer FRESH_SECONDS = 20;

    /** @description Check now (the page's button) reads again unless the last read is this many seconds old or less. */
    public static final Integer CHECK_NOW_SECONDS = 5;

    private static final String LOCK_ERROR = 'UNABLE_TO_LOCK_ROW';
    private static final String UNAVAILABLE = 'Record Currently Unavailable';

    /**
     * @description Reads are shared (freshness and the claim). Off in tests (every read reads, no claim), so a test can
     * move a release along several times in a row; the shared-read tests switch it on.
     */
    @TestVisible
    private static Boolean shareReads = !Test.isRunningTest();

    /** @description Tests only: the save fails as if another viewer held the row. */
    @TestVisible
    private static Boolean lockedForTest = false;

    /** @description Tests only: the claim's FOR UPDATE fails as if another viewer held the row too long. */
    @TestVisible
    private static Boolean claimLockedForTest = false;

    /**
     * @description Whether the release was read within FRESH_SECONDS, so the saved record is returned instead of reading.
     * @param rel the release, with Last_Synced__c
     * @return true when its Last_Synced__c is within the window
     */
    public static Boolean isFresh(RLY_Release__c rel) {
        return isFresh(rel, FRESH_SECONDS);
    }

    /**
     * @description Whether the release was read within a number of seconds.
     * @param rel the release, with Last_Synced__c
     * @param seconds the window (FRESH_SECONDS, or CHECK_NOW_SECONDS for Check now)
     * @return true when reads are shared and its Last_Synced__c is within the window
     */
    public static Boolean isFresh(RLY_Release__c rel, Integer seconds) {
        return shareReads && seconds > 0 && rel != null && rel.Last_Synced__c != null
            && rel.Last_Synced__c.addSeconds(seconds) > System.now();
    }

    /**
     * @description Claims the read of a release that looks stale, before any callout: locks its row (FOR UPDATE, which
     * waits for another viewer's read to commit) and checks its freshness again on the locked row.
     * @param releaseId the release
     * @param seconds the freshness window the caller asked with
     * @return true when this transaction holds the row and the release is still stale (it reads); false when another
     * viewer read it meanwhile or the lock couldn't be had (the caller returns the release as saved)
     */
    public static Boolean claim(Id releaseId, Integer seconds) {
        if (!shareReads) {
            return true;
        }
        try {
            return !isFresh(new SystemAccess().lockRow(releaseId), seconds);
        } catch (QueryException e) {
            if (!isLockMessage(e.getMessage())) {
                throw e;
            }
            return false;
        }
    }

    /**
     * @description Reads a release for its page (RlyReleasesController.refreshRelease and checkRelease): a running one moves
     * along (RlyStatusReader.advanceWithin, shared within the window), one with nothing running reads its rollback or the
     * back promote syncs (RlyRollbackRun.readIdle).
     * @param releaseId the release
     * @param seconds the freshness window (FRESH_SECONDS, or CHECK_NOW_SECONDS for Check now)
     */
    public static void refresh(Id releaseId, Integer seconds) {
        if (RlyStatusReader.isOpen(RlyReleaseStore.release(releaseId))) {
            RlyStatusReader.advanceWithin(releaseId, seconds);
        } else {
            RlyRollbackRun.readIdle(releaseId);
        }
    }

    /**
     * @description Saves one read (after its callouts): the release, the Slack results, the components an add brought, and
     * after a deploy the back promote syncs. A row lock held by another viewer undoes these saves and returns the release
     * as saved; any other save error is thrown as before.
     * @param rel the release as this read moved it
     * @param oldStatus its status before the read
     * @return the release as this read saved it, or as saved by the viewer holding the lock
     */
    public static RLY_Release__c save(RLY_Release__c rel, String oldStatus) {
        Savepoint beforeSave = Database.setSavepoint();
        try {
            saveRead(rel, oldStatus);
        } catch (DmlException e) {
            if (!isLockMessage(e.getMessage())) {
                throw e;
            }
            Database.rollback(beforeSave);
            return RlyReleaseStore.release(rel.Id);
        }
        return rel;
    }

    private static void saveRead(RLY_Release__c rel, String oldStatus) {
        if (lockedForTest) {
            throw new DmlException(LOCK_ERROR + ', unable to obtain exclusive access to this record');
        }
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        RlyAppendRun.saveItems(); // the components an add brought, once its run started
        if (oldStatus != 'Deployed' && rel.Status__c == 'Deployed') {
            RlyBackPromoteQueue.afterDeploy(rel);
        }
    }

    // A row lock held by another transaction, as a save or a FOR UPDATE reports it.
    private static Boolean isLockMessage(String message) {
        String text = String.valueOf(message);
        return text.contains(LOCK_ERROR) || text.contains(UNAVAILABLE);
    }

    /** @description Row locks in system mode: every viewer of a release claims its read, whatever their sharing. */
    private without sharing class SystemAccess {
        /**
         * @description Locks the release's row for this transaction and reads when it was last read.
         * @param releaseId the release
         * @return the locked row, with Last_Synced__c
         */
        public RLY_Release__c lockRow(Id releaseId) {
            if (claimLockedForTest) {
                throw new QueryException(LOCK_ERROR + ', Record Currently Unavailable');
            }
            return [SELECT Id, Last_Synced__c FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE LIMIT 1 FOR UPDATE];
        }
    }
}
