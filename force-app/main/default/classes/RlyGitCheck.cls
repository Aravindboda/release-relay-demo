/**
 * @description The check of the hub's Git connection: the repository and its default branch, the pipeline
 * branch and files, and every route branch. Callouts only; the caller saves.
 */
public with sharing class RlyGitCheck {

    /**
     * @description The check itself, without saving.
     * @param g the Git connection
     * @param orgs the registered orgs (for their branches)
     * @return the fields to save: status, message and when it was checked
     */
    public static RLY_Git_Connection__c run(RLY_Git_Connection__c g, List<RLY_Org__c> orgs) {
        RLY_Git_Connection__c out = new RLY_Git_Connection__c(Id = g.Id, Last_Checked__c = Datetime.now());
        List<String> notes = new List<String>();
        try {
            RlyGit git = RlyGit.forConnection(g);
            notes.add('Repository reachable. Default branch: ' + git.defaultBranch() + '.');
            checkPipeline(git, g);
            notes.add('Pipeline files found on ' + g.Pipeline_Branch__c + '.');
            List<String> missing = missingBranches(git, orgs);
            notes.add(missing.isEmpty() ? 'Every route branch exists.'
                : 'Missing branches: ' + String.join(missing, ', ') + '. Use Create missing branches.');
            out.Status__c = 'Connected';
        } catch (Exception e) {
            out.Status__c = 'Failed';
            notes.add(e.getMessage());
        }
        out.Status_Message__c = String.join(notes, '\n').left(4000);
        return out;
    }

    // The pipeline branch, the pipeline itself and its files; throws when something's missing.
    private static void checkPipeline(RlyGit git, RLY_Git_Connection__c g) {
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
    }

    /**
     * @description The route branches that aren't in the repository yet (each branch once).
     * @param git the Git provider
     * @param orgs the registered orgs
     * @return the missing branches
     */
    public static List<String> missingBranches(RlyGit git, List<RLY_Org__c> orgs) {
        List<String> missing = new List<String>();
        Set<String> seen = new Set<String>();
        for (RLY_Org__c o : orgs) {
            if (String.isNotBlank(o.Branch__c) && seen.add(o.Branch__c.trim()) && !git.branchExists(o.Branch__c.trim())) {
                missing.add(o.Branch__c.trim());
            }
        }
        return missing;
    }
}
