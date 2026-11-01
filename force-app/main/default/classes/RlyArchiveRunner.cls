/**
 * @description Makes archive runs, one pass per call (no async Apex): Run now from the Archive tab (startRun, runPass
 * until done, cancelRun) and the nightly calls (RlyArchiveNightly). A pass removes up to 200 releases and 4,000 records
 * (RlyArchiveBatch, RlyArchivePass) under a savepoint: a failed pass rolls back that pass only and the run becomes
 * Failed, while what earlier passes removed stays removed. A run ends Succeeded when nothing eligible is left and
 * Partial after 25 passes. Only admins in the production hub (RlyArchiveService) start and continue runs; one run at a
 * time (RlyArchiveRuns.running).
 */
public with sharing class RlyArchiveRunner {

    /** @description Why a second run is refused. */
    public static final String BUSY = 'Another archive run is going. Wait for it to finish.';
    /** @description Why a run is refused when nothing is eligible (board wording). */
    public static final String NOTHING = 'Nothing is eligible.';
    /** @description Why a run is refused without days (board wording). */
    public static final String NO_DAYS = 'Set the number of days on the Pipeline tab first.';
    /** @description Why a pass is refused on a run that has ended. */
    public static final String ENDED = 'This run has finished.';
    /** @description Why a run id isn't known. */
    public static final String NOT_FOUND = 'That run wasn\'t found.';

    /** @description Most passes per run; then it stops as Partial. */
    @TestVisible
    private static Integer maxPasses = 25;

    /**
     * @description Starts Run now (admins, production hub): the days must be the saved days, no other run may be going
     * and something must be eligible.
     * @param days the days typed to confirm
     * @return the run, Running with no passes yet
     */
    public static RlyArchiveViews.Run startRun(Integer days) {
        RlyArchiveService.requireAdmin(RlyArchiveService.ADMIN_ONLY);
        RlyArchiveService.requireHub();
        Integer saved = savedDays(days);
        if (RlyArchiveRuns.running() != null) {
            throw RlyArchiveService.failure(BUSY);
        }
        Datetime cut = RlyArchiveService.cutoff(saved);
        if (RlyArchiveEligible.countReleases(cut) == 0) {
            throw RlyArchiveService.failure(NOTHING);
        }
        RLY_Archive_Run__c run = RlyArchiveRuns.start(RlyArchiveRuns.RUN_NOW, saved, null);
        return RlyArchiveRuns.view(RlyArchiveRuns.find(run.Id));
    }

    /**
     * @description One pass of Run now (admins, production hub).
     * @param runId the run startRun returned
     * @param days the days typed to confirm (the saved days, and the run's)
     * @return the pass's result
     */
    public static RlyArchiveViews.PassResult runPass(Id runId, Integer days) {
        RlyArchiveService.requireAdmin(RlyArchiveService.ADMIN_ONLY);
        RlyArchiveService.requireHub();
        Integer saved = savedDays(days);
        RLY_Archive_Run__c run = RlyArchiveRuns.find(runId);
        if (run == null) {
            throw RlyArchiveService.failure(NOT_FOUND);
        }
        if (run.Status__c != RlyArchiveRuns.RUNNING) {
            throw RlyArchiveService.failure(ENDED);
        }
        if (RlyArchiveRuns.whole(run.Retention_Days__c) != saved) {
            throw RlyArchiveService.failure('The Retention days changed since this run started. Start a new run.');
        }
        return pass(run);
    }

    /**
     * @description Cancels Run now between passes (admins): "Cancelled after pass N". A finished run stays as it is.
     * @param runId the run
     * @return the run
     */
    public static RlyArchiveViews.Run cancelRun(Id runId) {
        RlyArchiveService.requireAdmin(RlyArchiveService.ADMIN_ONLY);
        RLY_Archive_Run__c run = RlyArchiveRuns.find(runId);
        if (run == null) {
            throw RlyArchiveService.failure(NOT_FOUND);
        }
        RlyArchiveRuns.cancel(run);
        return RlyArchiveRuns.view(RlyArchiveRuns.find(runId));
    }

    /**
     * @description Makes one pass of a Running run and settles it: Succeeded when nothing eligible is left, Partial at
     * the pass limit, Failed (this pass rolled back, earlier passes stay) when the pass throws.
     * @param run the run (Running)
     * @return the pass's result
     */
    public static RlyArchiveViews.PassResult pass(RLY_Archive_Run__c run) {
        Integer passNo = RlyArchiveRuns.whole(run.Passes__c) + 1;
        RLY_Archive_Run__c work = run.clone(true, false, false, false);
        Savepoint sp = Database.setSavepoint();
        RlyArchiveViews.PassResult p;
        try {
            RlyArchivePass.Outcome o = RlyArchivePass.remove(RlyArchiveBatch.nextPass(run.Cutoff__c));
            RlyArchiveRuns.addPass(work, o);
            Integer remaining = RlyArchiveEligible.countReleases(run.Cutoff__c);
            settle(work, remaining, o.releases);
            RlyArchiveRuns.save(work);
            p = result(work, o);
            p.remaining = remaining;
        } catch (Exception e) {
            Database.rollback(sp);
            RLY_Archive_Run__c failed = run.clone(true, false, false, false);
            RlyArchiveRuns.finish(failed, RlyArchiveRuns.FAILED, 'Pass ' + passNo + ' failed: ' + e.getMessage()
                + ' Nothing was removed in that pass.');
            RlyArchiveRuns.save(failed);
            p = result(failed, new RlyArchivePass.Outcome());
            p.remaining = null;
        }
        p.pass = passNo;
        return p;
    }

    // Ends the run when nothing is left, at the pass limit, or when a pass removed nothing (it never loops forever).
    private static void settle(RLY_Archive_Run__c run, Integer remaining, Integer removed) {
        Integer passes = RlyArchiveRuns.whole(run.Passes__c);
        String passWords = String.valueOf(passes) + (passes == 1 ? ' pass' : ' passes');
        if (remaining == 0) {
            RlyArchiveRuns.finish(run, RlyArchiveRuns.SUCCEEDED, passWords + ' · all eligible removed' + runNumber(run));
        } else if (passes >= maxPasses) {
            RlyArchiveRuns.finish(run, RlyArchiveRuns.PARTIAL, 'Stopped at the ' + maxPasses
                + '-pass limit; the rest goes at the next run' + runNumber(run));
        } else if (removed == 0) {
            RlyArchiveRuns.finish(run, RlyArchiveRuns.PARTIAL, 'Stopped: nothing could be removed in pass ' + passes);
        } else {
            run.Message__c = passWords + ' so far';
        }
    }

    // " · run #123" from a GitHub Actions run address, or nothing.
    private static String runNumber(RLY_Archive_Run__c run) {
        String url = run.Pipeline_Run_Url__c;
        if (String.isBlank(url) || !url.contains('/runs/')) {
            return '';
        }
        String num = url.substringAfterLast('/runs/').substringBefore('/');
        return num.isNumeric() ? ' · run #' + num : '';
    }

    private static RlyArchiveViews.PassResult result(RLY_Archive_Run__c run, RlyArchivePass.Outcome o) {
        RlyArchiveViews.PassResult p = new RlyArchiveViews.PassResult();
        p.runId = run.Id;
        p.releases = o.releases;
        p.records = o.records;
        p.totalReleases = RlyArchiveRuns.whole(run.Releases_Removed__c);
        p.totalRecords = RlyArchiveRuns.whole(run.Records_Removed__c);
        p.status = run.Status__c;
        p.message = run.Message__c;
        p.done = run.Status__c != RlyArchiveRuns.RUNNING;
        return p;
    }

    // The saved days, which the days typed must match.
    private static Integer savedDays(Integer days) {
        Integer saved = RlyArchiveSettings.days(RlyArchiveSettings.read());
        if (saved == null) {
            throw RlyArchiveService.failure(NO_DAYS);
        }
        if (days != saved) {
            throw RlyArchiveService.failure('Type ' + saved + ' to confirm: the saved number of days.');
        }
        return saved;
    }
}
