/**
 * @description What the Pipeline Monitor tab (rlyPipelineMonitor) reads from RlyRunMonitorController: the board (the
 * repositories, four tiles, one lane per org on the route, the active branches and the first page of runs) and older
 * pages of runs. Plain shapes only; RlyRunMonitorBoard, RlyRunMonitorBranches and RlyRunMonitorRows fill them. The run
 * is split into a virtual base and the class the page gets (the page sees one object).
 */
public with sharing class RlyRunMonitorViews {

    /** @description The whole board, read every 10 s while a run is going and every 30 s otherwise. */
    public class Board {
        /** @description The hub's Git connections (the repository picker). */
        @AuraEnabled public List<Repo> repos = new List<Repo>();
        /** @description The repository the board shows, or null for every run. */
        @AuraEnabled public String repository;
        /** @description When the board was read (server time). */
        @AuraEnabled public Datetime readAt;
        /** @description A run is queued or in progress (the page then reads again every 10 s). */
        @AuraEnabled public Boolean anyActive = false;
        /** @description The four tiles. */
        @AuraEnabled public Tiles tiles = new Tiles();
        /** @description One lane per org, grouped as on the Pipeline tab. */
        @AuraEnabled public List<Lane> lanes = new List<Lane>();
        /** @description The active branches, running and failed first. */
        @AuraEnabled public List<BranchRow> branches = new List<BranchRow>();
        /** @description Every queued or in progress run, then the newest finished runs (one page). */
        @AuraEnabled public List<Run> runs = new List<Run>();
        /** @description Older finished runs can be read (Load older runs). */
        @AuraEnabled public Boolean hasMore = false;
    }

    /** @description One Git connection in the picker. */
    public class Repo {
        /** @description The connection's record Id. */
        @AuraEnabled public Id id;
        /** @description The repository, for example owner/release-repo. */
        @AuraEnabled public String repository;
        /** @description The Git provider (GitHub, GitLab...). */
        @AuraEnabled public String provider;
    }

    /** @description The four tiles. */
    public class Tiles {
        /** @description Runs queued or in progress. */
        @AuraEnabled public Integer running = 0;
        /** @description Active branches. */
        @AuraEnabled public Integer branches = 0;
        /** @description Runs that succeeded today (the viewer's day). */
        @AuraEnabled public Integer succeededToday = 0;
        /** @description Runs that failed today (the viewer's day). */
        @AuraEnabled public Integer failedToday = 0;
    }

    /** @description One org on the route with its latest run. */
    public class Lane {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description The org's name. */
        @AuraEnabled public String name;
        /** @description development, route or backpromote: the group the lane is listed under. */
        @AuraEnabled public String groupKey;
        /** @description The group's label: Development, Route or Back promote. */
        @AuraEnabled public String groupLabel;
        /** @description The org's role in words: developer org, stage 1, production, back promote. */
        @AuraEnabled public String roleText;
        /** @description The org's GitHub environment. */
        @AuraEnabled public String environment;
        /** @description The org's latest run today (or still going), or null. */
        @AuraEnabled public Run run;
        /** @description The org's latest run before today when it had none today, or null. */
        @AuraEnabled public Run lastRun;
    }

    /** @description One active branch. */
    public class BranchRow {
        /** @description The branch. */
        @AuraEnabled public String branch;
        /** @description The release's pull request number, or null. */
        @AuraEnabled public Integer prNumber;
        /** @description open, merged or closed (from the release's status), or null without a pull request. */
        @AuraEnabled public String prState;
        /** @description The pull request's address, or null. */
        @AuraEnabled public String prUrl;
        /** @description The branch's release, or null. */
        @AuraEnabled public Id releaseId;
        /** @description That release's number. */
        @AuraEnabled public String releaseName;
        /** @description The newest activity: the latest run's start or finish, or the release's last change. */
        @AuraEnabled public Datetime lastActivity;
        /** @description Where the branch is now: the latest run's org, or the release's target org. */
        @AuraEnabled public String stage;
        /** @description running, failed, ok or idle (no run in the window). */
        @AuraEnabled public String state;
        /** @description The latest run's step, for back promote branches. */
        @AuraEnabled public String step;
        /** @description The latest run's record Id (opens its details), or null. */
        @AuraEnabled public Id runRecordId;
    }

    /** @description A pipeline run's identity and status (the base of Run, split to keep each shape small). */
    public virtual class RunBase {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description GitHub run id and attempt, for example 12345678-1. */
        @AuraEnabled public String runKey;
        /** @description The GitHub run number shown, for example 12345678. */
        @AuraEnabled public String runNumber;
        /** @description The run attempt (1 for the first try). */
        @AuraEnabled public Integer attempt;
        /** @description Queued, In progress, Succeeded, Failed or Cancelled. */
        @AuraEnabled public String status;
        /** @description The queued or in progress run is still going. */
        @AuraEnabled public Boolean active = false;
        /** @description What the run does, for example Check-only deploy. */
        @AuraEnabled public String step;
        /** @description The pipeline mode. */
        @AuraEnabled public String mode;
        /** @description The branch. */
        @AuraEnabled public String branch;
    }

    /** @description One pipeline run (RLY_Pipeline_Run__c): RunBase plus where, when and who. */
    public class Run extends RunBase {
        /** @description The org (GitHub environment) the run works in. */
        @AuraEnabled public String targetOrg;
        /** @description The release, or null. */
        @AuraEnabled public Id releaseId;
        /** @description The release's number, or the request id when the release isn't known. */
        @AuraEnabled public String releaseName;
        /** @description The release's title, or null. */
        @AuraEnabled public String releaseTitle;
        /** @description When it started. */
        @AuraEnabled public Datetime started;
        /** @description When it finished, or null. */
        @AuraEnabled public Datetime finished;
        /** @description Seconds it took, or null while it runs (the page counts from started). */
        @AuraEnabled public Integer durationSeconds;
        /** @description Who started it. */
        @AuraEnabled public String actor;
        /** @description The GitHub Actions run. */
        @AuraEnabled public String runUrl;
        /** @description Why it failed, or null. */
        @AuraEnabled public String failure;
        /** @description The run's jobs and their outcomes, when the pipeline sent them. */
        @AuraEnabled public List<Step> steps = new List<Step>();
    }

    /** @description One job of a run. */
    public class Step {
        /** @description The job, for example Check-only deploy. */
        @AuraEnabled public String name;
        /** @description success, failure, cancelled or skipped. */
        @AuraEnabled public String outcome;
        /** @description Seconds it took, or null. */
        @AuraEnabled public Integer seconds;
    }

    /** @description A page of older runs. */
    public class OlderPage {
        /** @description The runs, newest first. */
        @AuraEnabled public List<Run> runs = new List<Run>();
        /** @description Still older runs can be read. */
        @AuraEnabled public Boolean hasMore = false;
    }
}
