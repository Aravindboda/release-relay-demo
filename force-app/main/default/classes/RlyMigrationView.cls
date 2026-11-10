/**
 * @description What the Migration tab shows (build 46): one migration, step by step. Built by RlyMigrationViews from the
 * saved migration, without callouts.
 */
public with sharing class RlyMigrationView {

    /** @description The whole page. */
    public class View {
        /** @description The migration record, or null before one is started. */
        @AuraEnabled public Id id;
        /** @description MIG- and 13 digits. */
        @AuraEnabled public String migrationId;
        /** @description Open, Switched, Finished or Cancelled (blank before one is started). */
        @AuraEnabled public String status;
        /** @description The step the wizard is on (1 to 8). */
        @AuraEnabled public Integer step = 1;
        /** @description The current (active) connection. */
        @AuraEnabled public Conn current;
        /** @description The new connection, once configured. */
        @AuraEnabled public Conn target;
        /** @description What the current connection holds. */
        @AuraEnabled public Holds holds = new Holds();
        /** @description The methods for this pair and the one picked. */
        @AuraEnabled public Choose choose = new Choose();
        /** @description The dry run and the run. */
        @AuraEnabled public RunView run = new RunView();
        /** @description What moved and what didn't. */
        @AuraEnabled public Moved moved = new Moved();
        /** @description The new and old setup checklists. */
        @AuraEnabled public Setup setup = new Setup();
        /** @description Each org against its branch in the new repository. */
        @AuraEnabled public List<OrgRow> orgs = new List<OrgRow>();
        /** @description What Switch now needs. */
        @AuraEnabled public Gate gate = new Gate();
        /** @description Who did each step and when, and the report. */
        @AuraEnabled public Log log = new Log();
        /** @description The releases Switch now cancelled (build 54). */
        @AuraEnabled public List<CancelledRelease> cancelled = new List<CancelledRelease>();
    }

    /** @description A Git connection as the page shows it. */
    public class Conn {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description GitHub, GitLab, Bitbucket or AzureDevOps. */
        @AuraEnabled public String provider;
        /** @description The provider's name for people (Azure DevOps). */
        @AuraEnabled public String providerLabel;
        /** @description owner/repository, group/project... */
        @AuraEnabled public String repository;
        /** @description The Named Credential. */
        @AuraEnabled public String namedCredential;
        /** @description The pipeline file. */
        @AuraEnabled public String pipelineFile;
        /** @description The pipeline branch. */
        @AuraEnabled public String pipelineBranch;
        /** @description Not checked, Connected or Failed. */
        @AuraEnabled public String status;
        /** @description The last check's notes. */
        @AuraEnabled public String statusMessage;
        /** @description The repository on the web. */
        @AuraEnabled public String webUrl;
        /** @description The hub's active connection. */
        @AuraEnabled public Boolean active = false;
    }

    /** @description What the current connection holds. */
    public class Holds {
        /** @description Its branches (the first page). */
        @AuraEnabled public List<String> branches = new List<String>();
        /** @description More branches than listed. */
        @AuraEnabled public Boolean more = false;
        /** @description When the branches were read. */
        @AuraEnabled public Datetime readOn;
        /** @description The registered orgs and their branches. */
        @AuraEnabled public List<OrgRow> orgs = new List<OrgRow>();
        /** @description Releases still open on it. */
        @AuraEnabled public List<OpenRelease> open = new List<OpenRelease>();
        /** @description The new repository's check: reachable, empty or holding branches. */
        @AuraEnabled public String targetCheck;
        /** @description How many branches the new repository holds (null before the check). */
        @AuraEnabled public Integer targetBranches;
    }

    /** @description A release still open on the current connection. */
    public class OpenRelease {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description REL-00052. */
        @AuraEnabled public String name;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description Its status. */
        @AuraEnabled public String status;
        /** @description Its pull or merge request. */
        @AuraEnabled public String url;
        /** @description A pipeline run is going for it (build 54: the switch doesn't stop it). */
        @AuraEnabled public Boolean running = false;
    }

    /** @description A release Switch now cancelled (build 54), as kept on the migration. */
    public class CancelledRelease {
        /** @description The record. */
        @AuraEnabled public Id id;
        /** @description REL-00052. */
        @AuraEnabled public String name;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description Its status before. */
        @AuraEnabled public String before;
        /** @description Its pull or merge request on the old provider. */
        @AuraEnabled public String url;
        /** @description The pull or merge request was closed with the comment. */
        @AuraEnabled public Boolean closed = false;
        /** @description A pipeline run was going for it. */
        @AuraEnabled public Boolean running = false;
        /** @description What couldn't be done, in words (blank when everything worked). */
        @AuraEnabled public String note;
    }

    /** @description The methods for this pair. */
    public class Choose {
        /** @description lift, importer or fresh (blank before one is picked). */
        @AuraEnabled public String method;
        /** @description Each method, possible or not, with pros, cons and the clicks. */
        @AuraEnabled public List<RlyMigrationMethods.Method> methods = new List<RlyMigrationMethods.Method>();
    }

    /** @description The dry run and the run. */
    public class RunView {
        /** @description dry or run: the latest one started. */
        @AuraEnabled public String kind;
        /** @description Started, In progress, Ready, Not ready, Succeeded or Failed. */
        @AuraEnabled public String status;
        /** @description The latest run's request id. */
        @AuraEnabled public String runId;
        /** @description The latest run in the current pipeline. */
        @AuraEnabled public String runUrl;
        /** @description The latest run is still going. */
        @AuraEnabled public Boolean running = false;
        /** @description The dry run's findings. */
        @AuraEnabled public Summary dry;
        /** @description The run's (or the verify's) findings. */
        @AuraEnabled public Summary result;
    }

    /** @description A run's findings. */
    public class Summary {
        /** @description Succeeded, Failed or In progress. */
        @AuraEnabled public String status;
        /** @description The dry run says the real run can go. */
        @AuraEnabled public Boolean ready = false;
        /** @description What stops it. */
        @AuraEnabled public List<String> problems = new List<String>();
        /** @description The run's message. */
        @AuraEnabled public String message;
        /** @description Branches, tags, commits and size, in words. */
        @AuraEnabled public String counts;
        /** @description Read ✓ · push ✓, in words. */
        @AuraEnabled public String access;
        /** @description Empty, or holding n branches and tags. */
        @AuraEnabled public String targetState;
        /** @description The Release Relay branches found and missing. */
        @AuraEnabled public List<Named> named = new List<Named>();
        /** @description Progress, 0 to 100, while it goes. */
        @AuraEnabled public Integer percent = 0;
        /** @description The phase while it goes. */
        @AuraEnabled public String phase;
    }

    /** @description A Release Relay branch in the dry run. */
    public class Named {
        /** @description The branch. */
        @AuraEnabled public String name;
        /** @description In the current repository. */
        @AuraEnabled public Boolean inSource = false;
        /** @description In the new repository. */
        @AuraEnabled public Boolean inTarget = false;
    }

    /** @description What moved and what didn't. */
    public class Moved {
        /** @description Each branch and tag with both commits. */
        @AuraEnabled public List<RefRow> rows = new List<RefRow>();
        /** @description Branches · tags · commits on the main branch, in words. */
        @AuraEnabled public String counts;
        /** @description How many refs match, of how many. */
        @AuraEnabled public String matched;
        /** @description Every ref matches. */
        @AuraEnabled public Boolean allMatch = false;
        /** @description More refs than listed. */
        @AuraEnabled public Integer more = 0;
        /** @description Open pull or merge requests in the current repository (they don't move). */
        @AuraEnabled public List<RlyMigrationRepo.OpenRequest> requests = new List<RlyMigrationRepo.OpenRequest>();
        /** @description What else stays with the old provider. */
        @AuraEnabled public List<String> stays = new List<String>();
        /** @description A fresh start compares files (trees), not commits. */
        @AuraEnabled public Boolean fresh = false;
    }

    /** @description One branch or tag in What moved. */
    public class RefRow {
        /** @description branch or tag. */
        @AuraEnabled public String kind;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Its Release Relay role (pipeline branch, SIT's branch...), or blank. */
        @AuraEnabled public String role;
        /** @description The commit in the current repository. */
        @AuraEnabled public String source;
        /** @description The commit in the new repository. */
        @AuraEnabled public String target;
        /** @description The two match (fresh start: the seeded commit is there). */
        @AuraEnabled public Boolean match = false;
        /** @description The branch in the new repository. */
        @AuraEnabled public String url;
    }

    /** @description The checklists. */
    public class Setup {
        /** @description Do in the new setup. */
        @AuraEnabled public List<RlyMigrationChecklist.Item> newItems = new List<RlyMigrationChecklist.Item>();
        /** @description Do in the old setup. */
        @AuraEnabled public List<RlyMigrationChecklist.Item> oldItems = new List<RlyMigrationChecklist.Item>();
        /** @description Names to enter only when the old setup has them. */
        @AuraEnabled public String optionalNames;
        /** @description How many new setup items are done. */
        @AuraEnabled public Integer newDone = 0;
        /** @description How many old setup items are done. */
        @AuraEnabled public Integer oldDone = 0;
        /** @description Where the copy's token goes in the current pipeline, and what it needs. */
        @AuraEnabled public String tokenHint;
    }

    /** @description A registered org and its check against the new repository. */
    public class OrgRow {
        /** @description The org. */
        @AuraEnabled public Id id;
        /** @description Its name. */
        @AuraEnabled public String name;
        /** @description Developer, Stage or Hub. */
        @AuraEnabled public String role;
        /** @description Its branch. */
        @AuraEnabled public String branch;
        /** @description read by the pipeline, or read by the hub in parts. */
        @AuraEnabled public String how;
        /** @description Not checked, Running, In sync, Differs or Failed. */
        @AuraEnabled public String status;
        /** @description How many components differ, or why it failed. */
        @AuraEnabled public String detail;
        /** @description The latest check's id. */
        @AuraEnabled public String syncId;
        /** @description drift or parts. */
        @AuraEnabled public String mode;
    }

    /** @description What Switch now needs. */
    public class Gate {
        /** @description Every condition holds. */
        @AuraEnabled public Boolean ready = false;
        /** @description Every condition holds but open releases: Switch now can cancel them (build 54). */
        @AuraEnabled public Boolean readyIfCancelled = false;
        /** @description Each condition. */
        @AuraEnabled public List<Condition> conditions = new List<Condition>();
        /** @description The reason the admin accepted the listed differences, if any. */
        @AuraEnabled public String acceptReason;
        /** @description When the hub switched. */
        @AuraEnabled public Datetime switchedOn;
    }

    /** @description One condition of Switch now. */
    public class Condition {
        /** @description What it is. */
        @AuraEnabled public String label;
        /** @description It holds. */
        @AuraEnabled public Boolean ok = false;
        /** @description Why not, or the details. */
        @AuraEnabled public String detail;
        /** @description Not met, but Switch now can settle it (open releases, build 54). */
        @AuraEnabled public Boolean warn = false;
    }

    /** @description Who did what, and the report. */
    public class Log {
        /** @description Every step's event, newest first. */
        @AuraEnabled public List<Event> events = new List<Event>();
        /** @description The Migration report's download address, once finished. */
        @AuraEnabled public String reportUrl;
        /** @description When it was finished. */
        @AuraEnabled public Datetime finishedOn;
        /** @description The current user is a Release Relay admin. */
        @AuraEnabled public Boolean isAdmin = false;
    }

    /** @description One event. */
    public class Event {
        /** @description The step. */
        @AuraEnabled public String step;
        /** @description What happened. */
        @AuraEnabled public String what;
        /** @description Who did it. */
        @AuraEnabled public String who;
        /** @description When. */
        @AuraEnabled public Datetime stamp;
    }
}
