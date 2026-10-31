/**
 * @description Pipeline tab: the hub's Git connection and the route.
 *   getSetup        the Git connection and the route built from the registered orgs
 *   saveGit         add or change the Git connection (admins)
 *   checkGit        repository, default branch, pipeline files, and every route branch (RlyGitCheck)
 *   saveRoute       the order of the stages (admins)
 *   createBranches  creates the route branches that are missing, from the pipeline branch (admins)
 *   getPipelineFiles     the packaged pipeline files' version and the repository's (RlyPipelineFiles)
 *   updatePipelineFiles  writes the packaged pipeline files to the repository, by pull request or commit (admins)
 *   getBackPromote       back promote: on or off and each back promote org (RlyBackPromote); starts queued syncs first
 *   setBackPromote, saveBackPromoteOrg, syncNow   back promote settings and Sync now (admins)
 *
 * The route (RlyRouteRules): developer orgs raise into the first stage; stages follow Stage_Order__c;
 * the hub (production) is the last stage. Each org's branch comes from its RLY_Org__c record.
 */
public with sharing class RlyRouteController {

    /** @description What the Pipeline tab shows about Git and the route. Orgs carry no sign-in fields. */
    public class Setup {
        /** @description The Git connection, or null. */
        @AuraEnabled public RLY_Git_Connection__c git;
        /** @description Developer orgs. */
        @AuraEnabled public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        /** @description Stages in route order, the hub last. */
        @AuraEnabled public List<RLY_Org__c> stages = new List<RLY_Org__c>();
        /** @description Back promote orgs (after the hub, never on the route itself). */
        @AuraEnabled public List<RLY_Org__c> backPromoteOrgs = new List<RLY_Org__c>();
        /** @description What's missing from the route. */
        @AuraEnabled public List<String> warnings = new List<String>();
        /** @description The current user is an admin. */
        @AuraEnabled public Boolean isAdmin;
    }

    /**
     * @description The Git connection and the route.
     * @return the setup
     */
    @AuraEnabled
    public static Setup getSetup() {
        Data data = new Data();
        Setup s = new Setup();
        s.git = data.git();
        s.isAdmin = RlyOrgController.isAdmin();
        for (RLY_Org__c o : data.orgs()) {
            if (o.Role__c == 'Developer') {
                s.developers.add(o);
            } else if (o.Role__c == RlyBackPromote.ROLE) {
                s.backPromoteOrgs.add(o);
            } else {
                s.stages.add(o);
            }
        }
        s.stages = RlyRouteRules.ordered(s.stages);
        s.warnings = RlyRouteRules.warnings(s.developers, s.stages);
        return s;
    }

    /**
     * @description Adds or changes the hub's one Git connection; it's checked next by checkGit.
     * @param gitJson the connection's fields as JSON
     * @return the connection's Id
     */
    @AuraEnabled
    public static Id saveGit(String gitJson) {
        requireAdmin();
        RLY_Git_Connection__c input = readInput(gitJson);
        List<String> problems = RlyGitValidator.validate(input);
        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, '. ') + '.');
        }
        Data data = new Data();
        RLY_Git_Connection__c existing = data.git();
        RLY_Git_Connection__c row = new RLY_Git_Connection__c(
            Id = existing == null ? null : existing.Id,
            Name = (input.Provider__c + ' ' + input.Repository__c.trim()).left(80),
            Provider__c = input.Provider__c,
            Repository__c = input.Repository__c.trim(),
            Named_Credential__c = input.Named_Credential__c.trim(),
            Pipeline__c = String.isBlank(input.Pipeline__c) ? null : input.Pipeline__c.trim(),
            Pipeline_Branch__c = input.Pipeline_Branch__c.trim(),
            Source_Path__c = input.Source_Path__c.trim().removeEnd('/'),
            Code_Scan__c = input.Code_Scan__c != false,
            Status__c = 'Not checked',
            Status_Message__c = null
        );
        data.saveGit(row);
        return row.Id;
    }

    private static RLY_Git_Connection__c readInput(String gitJson) {
        try {
            return (RLY_Git_Connection__c) JSON.deserialize(gitJson, RLY_Git_Connection__c.class);
        } catch (Exception e) {
            throw new AuraHandledException('The Git connection couldn\'t be read.');
        }
    }

    /**
     * @description Checks the repository, its pipeline files and every route branch. Callouts first, one save at the end.
     * @return the connection as saved
     */
    @AuraEnabled
    public static RLY_Git_Connection__c checkGit() {
        requireAdmin();
        Data data = new Data();
        RLY_Git_Connection__c g = requireGit(data);
        data.saveGit(RlyGitCheck.run(g, data.orgs()));
        return data.git();
    }

    /**
     * @description Creates the missing route branches from the pipeline branch.
     * @return the branches created
     */
    @AuraEnabled
    public static List<String> createBranches() {
        requireAdmin();
        Data data = new Data();
        RLY_Git_Connection__c g = requireGit(data);
        try {
            RlyGit git = RlyGit.forConnection(g);
            List<String> missing = RlyGitCheck.missingBranches(git, data.orgs());
            for (String b : missing) {
                git.createBranch(b, g.Pipeline_Branch__c);
            }
            return missing;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves the stage order: stageIds first to last. The hub stays last whatever its position.
     * @param stageIds the stages, first to last
     */
    @AuraEnabled
    public static void saveRoute(List<Id> stageIds) {
        requireAdmin();
        Data data = new Data();
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>(data.orgs());
        List<RLY_Org__c> rows = new List<RLY_Org__c>();
        Integer pos = 1;
        for (Id i : stageIds) {
            RLY_Org__c o = byId.get(i);
            if (o == null || !RlyRouteRules.isStage(o)) {
                throw new AuraHandledException('Only stages can be ordered on the route.');
            }
            rows.add(new RLY_Org__c(Id = i, Stage_Order__c = o.Role__c == 'Hub' ? 999 : pos++));
        }
        data.saveOrgs(rows);
    }

    /**
     * @description The pipeline files: the version packaged with the hub, the version in the repository, every file.
     * @return the status
     */
    @AuraEnabled(cacheable=false)
    public static RlyPipelineFiles.Status getPipelineFiles() {
        return RlyPipelineFiles.currentStatus();
    }

    /**
     * @description Writes the hub's packaged pipeline files to the repository (admins).
     * @param how pullRequest (the default): a branch and a pull request into the pipeline branch; commit: straight to it
     * @return what happened, with the pull request's or commit's link
     */
    @AuraEnabled
    public static RlyPipelineFiles.UpdateResult updatePipelineFiles(String how) {
        requireAdmin();
        return RlyPipelineFiles.updateRepository(how);
    }

    /**
     * @description Back promote: starts the queued syncs and reads the running ones (callouts, then saves), then the board.
     * @return the board
     */
    @AuraEnabled
    public static RlyBackPromote.BackPromoteBoard getBackPromote() {
        RlyBackPromoteRun.catchUp();
        return RlyBackPromote.board();
    }

    /**
     * @description Turns back promote on or off (admins).
     * @param state on or off
     * @return the board
     */
    @AuraEnabled
    public static RlyBackPromote.BackPromoteBoard setBackPromote(String state) {
        RlyBackPromote.setEnabled(state);
        return RlyBackPromote.board();
    }

    /**
     * @description Saves a back promote org's settings (admins).
     * @param settingsJson {orgId, whenValue: Manual|After_Deploy, approval}
     * @return the board
     */
    @AuraEnabled
    public static RlyBackPromote.BackPromoteBoard saveBackPromoteOrg(String settingsJson) {
        RlyBackPromote.saveOrgSettings(settingsJson);
        return RlyBackPromote.board();
    }

    /**
     * @description Sync now (admins): saves a sync of the hub's changes to the org. It waits for an approver when the org
     * asks for one; otherwise it starts on the next read of the board (getBackPromote) or of its page.
     * @param orgId the back promote org
     * @return the sync release's Id
     */
    @AuraEnabled
    public static Id syncNow(Id orgId) {
        return RlyBackPromoteQueue.queueSync(orgId);
    }

    private static RLY_Git_Connection__c requireGit(Data data) {
        RLY_Git_Connection__c g = data.git();
        if (g == null) {
            throw new AuraHandledException('Save the Git connection first.');
        }
        return g;
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw new AuraHandledException('Changing the pipeline needs the Release Relay Admin permission set.');
        }
    }

    /** @description The connection and orgs are shared hub records: read in system mode, changed only after the admin checks above. */
    private without sharing class Data {

        /**
         * @description The hub's Git connection.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Name, Provider__c, Repository__c, Named_Credential__c, Pipeline__c,
                                                       Pipeline_Branch__c, Source_Path__c, Code_Scan__c, Status__c, Status_Message__c,
                                                       Last_Checked__c, Back_Promote__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Registered orgs for the route: no sign-in fields.
         * @return the orgs, by name
         */
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Git_Environment__c, Status__c, Source_Tracking__c, My_Domain__c,
                           Environment__c, Hotfix_Two_Approvers__c, Back_Promote_When__c, Back_Promote_Approval__c, Synced_On__c, Sync_Status__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Saves the Git connection (admins only; checked by the callers).
         * @param row the fields to save
         */
        public void saveGit(RLY_Git_Connection__c row) {
            upsert as system row;
        }

        /**
         * @description Saves the stage order (admins only; checked by the caller).
         * @param rows the orgs with their Stage_Order__c
         */
        public void saveOrgs(List<RLY_Org__c> rows) {
            update as system rows;
        }
    }
}
