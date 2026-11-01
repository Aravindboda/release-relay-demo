/**
 * @description What the Retention section (rlyPipeline) and the Archive tab (rlyArchive) read from RlyArchiveController:
 * the Retention setting, a preview of a days value, the Archive tab's numbers, one run, the nightly job's health, one
 * month of the chart and the result of one pass. Plain shapes only; RlyArchiveService fills them. Long shapes are
 * split into a virtual base and the class the page gets (the page sees one object).
 */
public with sharing class RlyArchiveViews {

    /** @description The Retention section: the setting, its last change and what is eligible now. */
    public class Retention {
        /** @description 'hub', 'sandbox', 'copy' or 'setup' (RlyHubGuard). */
        @AuraEnabled public String mode;
        /** @description The org gate's title outside the hub, or null. */
        @AuraEnabled public String gateTitle;
        /** @description The org gate's text outside the hub, or null. */
        @AuraEnabled public String gateMessage;
        /** @description The viewer is a Release Relay admin (can edit). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description Days finished releases are kept, or null to keep them forever. */
        @AuraEnabled public Integer days;
        /** @description Archive every night is on. */
        @AuraEnabled public Boolean nightly = false;
        /** @description Releases finished before this day are eligible, or null when no days are set. */
        @AuraEnabled public Date cutoffDate;
        /** @description Finished releases eligible now, or null when no days are set. */
        @AuraEnabled public Integer eligibleReleases;
        /** @description About how many records go with them, or null when no days are set. */
        @AuraEnabled public Integer eligibleRecords;
        /** @description When the setting was last changed, or null. */
        @AuraEnabled public Datetime changedOn;
        /** @description Who last changed it, or null. */
        @AuraEnabled public String changedBy;
        /** @description The days before the last change, or null. */
        @AuraEnabled public Integer previousDays;
        /** @description When the Git pipeline's scheduled job last called, or null. */
        @AuraEnabled public Datetime lastNightlyCall;
        /** @description What that call did, for example "Skipped: nightly is off", or null. */
        @AuraEnabled public String lastNightlyResult;
    }

    /** @description What a days value would make eligible (before Save). */
    public class Preview {
        /** @description The days previewed. */
        @AuraEnabled public Integer days;
        /** @description Releases finished before this day would be eligible, or null. */
        @AuraEnabled public Date cutoffDate;
        /** @description Finished releases that would be eligible, or null. */
        @AuraEnabled public Integer eligibleReleases;
        /** @description About how many records go with them, or null. */
        @AuraEnabled public Integer eligibleRecords;
    }

    /** @description The Archive tab's setting, live counts and totals (Archive adds the rest). */
    public virtual class ArchiveNumbers {
        /** @description The Retention days, or null when none are set. */
        @AuraEnabled public Integer days;
        /** @description Archive every night is on. */
        @AuraEnabled public Boolean nightly = false;
        /** @description Releases finished before this day are eligible, or null. */
        @AuraEnabled public Date cutoffDate;
        /** @description Finished releases eligible now, or null when no days are set. */
        @AuraEnabled public Integer eligibleReleases;
        /** @description About how many records go with them, or null when no days are set. */
        @AuraEnabled public Integer eligibleRecords;
        /** @description Releases that become eligible in the next 30 days, or null when no days are set. */
        @AuraEnabled public Integer eligibleNext30;
        /** @description Releases removed by every run so far. */
        @AuraEnabled public Integer archivedReleases = 0;
        /** @description Records removed by every run so far. */
        @AuraEnabled public Integer archivedRecords = 0;
        /** @description Data storage freed so far, in KB (2 KB per record). */
        @AuraEnabled public Integer freedKB = 0;
        /** @description How many runs there have been. */
        @AuraEnabled public Integer runCount = 0;
        /** @description When the first run started, or null. */
        @AuraEnabled public Datetime firstRun;
    }

    /** @description The Archive tab. */
    public class Archive extends ArchiveNumbers {
        /** @description 'hub', 'sandbox', 'copy' or 'setup' (RlyHubGuard). */
        @AuraEnabled public String mode;
        /** @description The org gate's title outside the hub, or null. */
        @AuraEnabled public String gateTitle;
        /** @description The org gate's text outside the hub, or null. */
        @AuraEnabled public String gateMessage;
        /** @description The viewer may see the tab: an admin or an approver. */
        @AuraEnabled public Boolean canView = false;
        /** @description The viewer may press Run now: an admin, in the production hub. */
        @AuraEnabled public Boolean canRun = false;
        /** @description The newest run, or null. */
        @AuraEnabled public Run lastRun;
        /** @description The run going now, or null. */
        @AuraEnabled public Run running;
        /** @description The nightly job's health. */
        @AuraEnabled public Health health;
        /** @description Releases archived per month, the last 12 calendar months, oldest first. */
        @AuraEnabled public List<MonthBar> months = new List<MonthBar>();
        /** @description Every run, newest first (at most 500). */
        @AuraEnabled public List<Run> runs = new List<Run>();
    }

    /** @description What one archive run removed (Run adds who, when and how). */
    public virtual class RunNumbers {
        /** @description The Retention days it used. */
        @AuraEnabled public Integer days;
        /** @description Passes made. */
        @AuraEnabled public Integer passes;
        /** @description Releases removed. */
        @AuraEnabled public Integer releases;
        /** @description Records removed. */
        @AuraEnabled public Integer records;
        /** @description Data storage freed, in KB. */
        @AuraEnabled public Integer freedKB;
        /** @description When the oldest release it removed had finished, or null. */
        @AuraEnabled public Datetime oldest;
        /** @description When the newest release it removed had finished, or null. */
        @AuraEnabled public Datetime newest;
    }

    /** @description One archive run (its summary row). */
    public class Run extends RunNumbers {
        /** @description The run's record Id. */
        @AuraEnabled public Id id;
        /** @description Its number, for example AR-00012. */
        @AuraEnabled public String name;
        /** @description When it started. */
        @AuraEnabled public Datetime started;
        /** @description When it finished, or null while it runs. */
        @AuraEnabled public Datetime finished;
        /** @description 'Nightly' or 'Run now'. */
        @AuraEnabled public String how;
        /** @description Who ran it: the admin, or "Git pipeline job" for a nightly run. */
        @AuraEnabled public String runBy;
        /** @description Running, Succeeded, Failed, Partial or Cancelled. */
        @AuraEnabled public String status;
        /** @description What happened, in words. */
        @AuraEnabled public String message;
        /** @description The GitHub Actions run that made a nightly call, or null. */
        @AuraEnabled public String pipelineUrl;
    }

    /** @description The nightly job's health: nightly runs of the last 30 days and the last call. */
    public class Health {
        /** @description Nightly runs in the last 30 days. */
        @AuraEnabled public Integer runs = 0;
        /** @description Of those, succeeded (Nothing to remove included). */
        @AuraEnabled public Integer succeeded = 0;
        /** @description Of those, failed. */
        @AuraEnabled public Integer failed = 0;
        /** @description Of those, partial. */
        @AuraEnabled public Integer partial = 0;
        /** @description When the scheduled job last called, or null. */
        @AuraEnabled public Datetime lastCall;
        /** @description What that call did, or null. */
        @AuraEnabled public String lastCallResult;
        /** @description Nights missed: nightly on and no call for more than 26 hours; 0 otherwise. */
        @AuraEnabled public Integer missedNights = 0;
        /** @description The newest failed nightly run of the last 30 days, or null. */
        @AuraEnabled public Run lastFailure;
    }

    /** @description One month of the chart. */
    public class MonthBar {
        /** @description The year, for example 2026. */
        @AuraEnabled public Integer year;
        /** @description The month, 1 to 12. */
        @AuraEnabled public Integer month;
        /** @description Its short name, for example Nov. */
        @AuraEnabled public String label;
        /** @description Releases archived in runs that started that month. */
        @AuraEnabled public Integer releases = 0;
    }

    /** @description The result of one pass. */
    public class PassResult {
        /** @description The run. */
        @AuraEnabled public Id runId;
        /** @description The pass just made (1 for the first). */
        @AuraEnabled public Integer pass;
        /** @description Releases this pass removed. */
        @AuraEnabled public Integer releases = 0;
        /** @description Records this pass removed. */
        @AuraEnabled public Integer records = 0;
        /** @description Releases the run has removed so far. */
        @AuraEnabled public Integer totalReleases = 0;
        /** @description Records the run has removed so far. */
        @AuraEnabled public Integer totalRecords = 0;
        /** @description Releases still eligible (null after a failed pass). */
        @AuraEnabled public Integer remaining = 0;
        /** @description The run has finished: no more passes. */
        @AuraEnabled public Boolean done = false;
        /** @description The run's status after this pass. */
        @AuraEnabled public String status;
        /** @description The run's message after this pass. */
        @AuraEnabled public String message;
    }
}
