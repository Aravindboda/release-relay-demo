/**
 * @description Retention (the Pipeline tab's Retention section, rlyPipeline) and the Archive tab (rlyArchive). Every
 * method is imperative (not cacheable: the numbers change after each pass) and works through RlyArchiveService and
 * RlyArchiveRunner, which check the org (production hub only) and the caller (admins edit and run; approvers see the
 * Archive tab). Run now is a loop in the page: startRun, then runPass until done (cancel = no next call, then cancelRun).
 */
public with sharing class RlyArchiveController {

    /**
     * @description The Retention section: the setting, its last change, what is eligible now and the last nightly call.
     * @return the section (only the org gate outside the production hub)
     */
    @AuraEnabled
    public static RlyArchiveViews.Retention readRetention() {
        return RlyArchiveService.readRetention();
    }

    /**
     * @description What a days value would make eligible, shown under the field before Save.
     * @param days the days typed (blank or fewer than 30 gives no counts)
     * @return the preview
     */
    @AuraEnabled
    public static RlyArchiveViews.Preview previewRetention(Integer days) {
        return RlyArchiveService.previewRetention(days);
    }

    /**
     * @description Saves the Retention setting (admins): days blank (keep forever) or 30 or more; nightly needs days.
     * @param days the days, or null
     * @param nightly archive every night
     * @return the section after saving
     */
    @AuraEnabled
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters') // the Retention section sends the toggle as a Boolean (page contract)
    public static RlyArchiveViews.Retention saveRetention(Integer days, Boolean nightly) {
        RlyArchiveSettings.Choice c = new RlyArchiveSettings.Choice();
        c.days = days;
        c.nightly = nightly == true;
        return RlyArchiveService.saveRetention(c);
    }

    /**
     * @description The Archive tab.
     * @return the page (only the org gate outside the production hub)
     */
    @AuraEnabled
    public static RlyArchiveViews.Archive readArchive() {
        return RlyArchiveService.readArchive();
    }

    /**
     * @description Starts Run now (admins).
     * @param days the days typed to confirm (must be the saved days)
     * @return the run
     */
    @AuraEnabled
    public static RlyArchiveViews.Run startRun(Integer days) {
        return RlyArchiveRunner.startRun(days);
    }

    /**
     * @description One pass of Run now (admins).
     * @param runId the run
     * @param days the days typed to confirm
     * @return the pass's result
     */
    @AuraEnabled
    public static RlyArchiveViews.PassResult runPass(Id runId, Integer days) {
        return RlyArchiveRunner.runPass(runId, days);
    }

    /**
     * @description Cancels Run now after the pass going (admins).
     * @param runId the run
     * @return the run
     */
    @AuraEnabled
    public static RlyArchiveViews.Run cancelRun(Id runId) {
        return RlyArchiveRunner.cancelRun(runId);
    }
}
