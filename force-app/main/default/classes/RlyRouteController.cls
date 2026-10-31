/**
 * Pipeline tab: the hub's Git connection and the route.
 *   getSetup        the Git connection and the route built from the registered orgs
 *   saveGit         add or change the Git connection (admins)
 *   checkGit        repository, default branch, pipeline files, and every route branch
 *   saveRoute       the order of the stages (admins)
 *   createBranches  creates the route branches that are missing, from the pipeline branch (admins)
 *
 * The route: developer orgs raise into the first stage; stages follow Stage_Order__c; the hub
 * (production) is the last stage. Each org's branch comes from its RLY_Org__c record.
 */
public with sharing class RlyRouteController {

    private static final Pattern NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final Pattern REF_PATTERN = Pattern.compile('^[A-Za-z0-9._/-]{1,100}$');
    private static final Pattern PATH_PATTERN = Pattern.compile('^[A-Za-z0-9_./-]{1,200}$');
    private static final Pattern PIPELINE_PATTERN = Pattern.compile('^[A-Za-z0-9_./-]{1,120}$');

    public class Setup {
        @AuraEnabled public RLY_Git_Connection__c git;
        @AuraEnabled public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        @AuraEnabled public List<RLY_Org__c> stages = new List<RLY_Org__c>();
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public Boolean isAdmin;
    }

    @AuraEnabled
    public static Setup getSetup() {
        Data data = new Data();
        Setup s = new Setup();
        s.git = data.git();
        s.isAdmin = RlyOrgController.isAdmin();
        for (RLY_Org__c o : data.orgs()) {
            if (o.Role__c == 'Developer') {
                s.developers.add(o);
            } else {
                s.stages.add(o);
            }
        }
        s.stages = ordered(s.stages);
        s.warnings = routeWarnings(s.developers, s.stages);
        return s;
    }

    /** Stages by Stage_Order__c (unordered last, by name); the hub always last. */
    @TestVisible
    private static List<RLY_Org__c> ordered(List<RLY_Org__c> stages) {
        List<RLY_Org__c> withOrder = new List<RLY_Org__c>();
        List<RLY_Org__c> rest = new List<RLY_Org__c>();
        RLY_Org__c hub;
        for (RLY_Org__c o : stages) {
            if (o.Role__c == 'Hub') {
                hub = o;
            } else if (o.Stage_Order__c != null) {
                withOrder.add(o);
            } else {
                rest.add(o);
            }
        }
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        while (!withOrder.isEmpty()) {
            Integer best = 0;
            for (Integer i = 1; i < withOrder.size(); i++) {
                if (withOrder[i].Stage_Order__c < withOrder[best].Stage_Order__c) {
                    best = i;
                }
            }
            out.add(withOrder.remove(best));
        }
        out.addAll(rest);
        if (hub != null) {
            out.add(hub);
        }
        return out;
    }

    @TestVisible
    private static List<String> routeWarnings(List<RLY_Org__c> developers, List<RLY_Org__c> stages) {
        List<String> w = new List<String>();
        if (stages.isEmpty()) {
            w.add('Register at least one stage (for example SIT) for releases to go to.');
        }
        Boolean hasHub = false;
        Set<String> branches = new Set<String>();
        List<RLY_Org__c> everyOrg = new List<RLY_Org__c>(stages);
        everyOrg.addAll(developers);
        for (RLY_Org__c o : everyOrg) {
            hasHub = hasHub || o.Role__c == 'Hub';
            if (String.isBlank(o.Branch__c)) {
                w.add(o.Name + ' has no branch: edit it and set its Git branch.');
            } else if (!branches.add(o.Branch__c.trim())) {
                w.add('Branch ' + o.Branch__c + ' is used by more than one org: each org needs its own branch.');
            }
            if (String.isBlank(o.Git_Environment__c)) {
                w.add(o.Name + ' has no Git environment: the pipeline needs it to sign in to that org.');
            }
        }
        if (!stages.isEmpty() && !hasHub) {
            w.add('Register this hub with the role Hub, so releases can be promoted to production.');
        }
        if (developers.isEmpty()) {
            w.add('Register at least one developer org to raise releases from.');
        }
        return w;
    }

    @AuraEnabled
    public static Id saveGit(String gitJson) {
        requireAdmin();
        RLY_Git_Connection__c input;
        try {
            input = (RLY_Git_Connection__c) JSON.deserialize(gitJson, RLY_Git_Connection__c.class);
        } catch (Exception e) {
            throw new AuraHandledException('The Git connection couldn\'t be read.');
        }
        List<String> problems = validate(input);
        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, '. ') + '.');
        }
        Data data = new Data();
        RLY_Git_Connection__c existing = data.git();
        RLY_Git_Connection__c row = new RLY_Git_Connection__c(
            Id = existing == null ? null : existing.Id,
            Name = input.Provider__c + ' ' + input.Repository__c.trim(),
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
        row.Name = row.Name.left(80);
        data.saveGit(row);
        return row.Id;
    }

    @TestVisible
    private static List<String> validate(RLY_Git_Connection__c g) {
        List<String> problems = new List<String>();
        if (!RlyGit.PROVIDERS.contains(g.Provider__c)) {
            problems.add('Pick a provider: GitHub, GitLab, Bitbucket or Azure DevOps');
        }
        if (String.isBlank(g.Repository__c) || g.Repository__c.trim().length() > 255) {
            problems.add('Repository is required');
        }
        if (String.isBlank(g.Named_Credential__c) || !NAME_PATTERN.matcher(g.Named_Credential__c.trim()).matches()) {
            problems.add('Named Credential must be the API name of a Named Credential, for example RLY_GitHub');
        }
        if (g.Provider__c != RlyGit.BITBUCKET && (String.isBlank(g.Pipeline__c) || !PIPELINE_PATTERN.matcher(g.Pipeline__c.trim()).matches())) {
            problems.add('Pipeline is required: the workflow file, CI file or pipeline id');
        }
        if (String.isBlank(g.Pipeline_Branch__c) || !REF_PATTERN.matcher(g.Pipeline_Branch__c.trim()).matches()) {
            problems.add('Pipeline branch is required, for example main');
        }
        if (String.isBlank(g.Source_Path__c) || !PATH_PATTERN.matcher(g.Source_Path__c.trim()).matches() || g.Source_Path__c.contains('..')) {
            problems.add('Source path must be a folder such as force-app/main/default');
        }
        if (problems.isEmpty()) {
            try {
                RlyGit.forConnection(g);
            } catch (RlyGit.GitException e) {
                problems.add(e.getMessage().removeEnd('.'));
            }
        }
        return problems;
    }

    /** Checks the repository, its pipeline files and every route branch. Callouts first, one save at the end. */
    @AuraEnabled
    public static RLY_Git_Connection__c checkGit() {
        requireAdmin();
        Data data = new Data();
        RLY_Git_Connection__c g = data.git();
        if (g == null) {
            throw new AuraHandledException('Save the Git connection first.');
        }
        RLY_Git_Connection__c out = new RLY_Git_Connection__c(Id = g.Id, Last_Checked__c = Datetime.now());
        List<String> notes = new List<String>();
        try {
            RlyGit git = RlyGit.forConnection(g);
            String defaultRef = git.defaultBranch();
            notes.add('Repository reachable. Default branch: ' + defaultRef + '.');
            if (!git.branchExists(g.Pipeline_Branch__c)) {
                throw new RlyGit.GitException('Pipeline branch ' + g.Pipeline_Branch__c + ' isn\'t in the repository.');
            }
            git.checkPipeline();
            List<String> missingFiles = new List<String>();
            for (String path : git.pipelineFiles()) {
                if (!git.fileExists(path, g.Pipeline_Branch__c)) {
                    missingFiles.add(path);
                }
            }
            if (!missingFiles.isEmpty()) {
                throw new RlyGit.GitException('Missing on ' + g.Pipeline_Branch__c + ': ' + String.join(missingFiles, ', ')
                    + '. Add the Release Relay pipeline files (Guide > Git admin).');
            }
            notes.add('Pipeline files found on ' + g.Pipeline_Branch__c + '.');
            List<String> missing = missingBranches(git, data.orgs());
            notes.add(missing.isEmpty() ? 'Every route branch exists.'
                : 'Missing branches: ' + String.join(missing, ', ') + '. Use Create missing branches.');
            out.Status__c = 'Connected';
        } catch (Exception e) {
            out.Status__c = 'Failed';
            notes.add(e.getMessage());
        }
        out.Status_Message__c = String.join(notes, '\n').left(4000);
        data.saveGit(out);
        return data.git();
    }

    private static List<String> missingBranches(RlyGit git, List<RLY_Org__c> orgs) {
        List<String> missing = new List<String>();
        Set<String> seen = new Set<String>();
        for (RLY_Org__c o : orgs) {
            if (String.isNotBlank(o.Branch__c) && seen.add(o.Branch__c.trim()) && !git.branchExists(o.Branch__c.trim())) {
                missing.add(o.Branch__c.trim());
            }
        }
        return missing;
    }

    /** Creates the missing route branches from the pipeline branch. Returns the branches created. */
    @AuraEnabled
    public static List<String> createBranches() {
        requireAdmin();
        Data data = new Data();
        RLY_Git_Connection__c g = data.git();
        if (g == null) {
            throw new AuraHandledException('Save the Git connection first.');
        }
        try {
            RlyGit git = RlyGit.forConnection(g);
            List<String> missing = missingBranches(git, data.orgs());
            for (String b : missing) {
                git.createBranch(b, g.Pipeline_Branch__c);
            }
            return missing;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Saves the stage order: stageIds first to last. The hub stays last whatever its position. */
    @AuraEnabled
    public static void saveRoute(List<Id> stageIds) {
        requireAdmin();
        Data data = new Data();
        Map<Id, RLY_Org__c> byId = new Map<Id, RLY_Org__c>(data.orgs());
        List<RLY_Org__c> rows = new List<RLY_Org__c>();
        Integer pos = 1;
        for (Id i : stageIds) {
            RLY_Org__c o = byId.get(i);
            if (o == null || o.Role__c == 'Developer') {
                throw new AuraHandledException('Only stages can be ordered on the route.');
            }
            rows.add(new RLY_Org__c(Id = i, Stage_Order__c = o.Role__c == 'Hub' ? 999 : pos++));
        }
        data.saveOrgs(rows);
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw new AuraHandledException('Changing the pipeline needs the Release Relay Admin permission set.');
        }
    }

    /** The connection and orgs are read by every hub user and changed only after the admin checks above. */
    private without sharing class Data {
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Name, Provider__c, Repository__c, Named_Credential__c, Pipeline__c,
                                                       Pipeline_Branch__c, Source_Path__c, Code_Scan__c, Status__c, Status_Message__c,
                                                       Last_Checked__c
                                                FROM RLY_Git_Connection__c ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Git_Environment__c, Status__c, Source_Tracking__c, My_Domain__c
                    FROM RLY_Org__c ORDER BY Name LIMIT 200];
        }
        public void saveGit(RLY_Git_Connection__c row) {
            upsert row;
        }
        public void saveOrgs(List<RLY_Org__c> rows) {
            update rows;
        }
    }
}
