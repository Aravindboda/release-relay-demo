/**
 * @description Pipeline tab, several Git connections (build 45): one connection per provider (GitHub, GitLab, Bitbucket,
 * Azure DevOps), each with its own route (its developer orgs, then its stages, then the hub).
 *   getConnections       the Git connections cards: provider, repository, Named Credential, orgs, status
 *   saveConnection       add a connection (a provider not used yet) or change one (admins)
 *   checkConnection      repository, pipeline files and every branch of its route (RlyGitCheck), saved on the connection
 *   createBranchesFor    creates its route's missing branches from its pipeline branch, in parts (RlyBranchCreate)
 *   pipelineFilesFor / updatePipelineFilesFor   its pipeline files: the version packaged with the hub and its own
 *   checkBranch          whether a branch is in a connection's repository (Register / edit org: "sit exists in GitLab")
 * The main connection is the oldest active one: schedules, the nightly archive and self-update stay on it, and orgs and
 * releases without a connection count as on it.
 */
public with sharing class RlyConnectionController {

    private static final List<String> PROVIDER_ORDER = new List<String>{ 'GitHub', 'GitLab', RlyGit.BITBUCKET, 'AzureDevOps' };

    /** @description What the Git connections section shows. */
    public class Connections {
        /** @description Every connection, the main one first. */
        @AuraEnabled public List<RlyConnectionCards.Card> cards = new List<RlyConnectionCards.Card>();
        /** @description The providers without a connection yet ("Not set up · Add"). */
        @AuraEnabled public List<String> notSetUp = new List<String>();
        /** @description The current user is an admin. */
        @AuraEnabled public Boolean isAdmin;
    }

    /**
     * @description The Git connections cards.
     * @return the cards and the providers not set up
     */
    @AuraEnabled
    public static Connections getConnections() {
        Connections out = new Connections();
        out.isAdmin = RlyOrgController.isAdmin();
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        Id mainId = conns.isEmpty() ? null : conns[0].Id;
        List<RLY_Org__c> orgs = RlyConnectionStore.orgs();
        Set<String> used = new Set<String>();
        for (RLY_Git_Connection__c c : conns) {
            out.cards.add(RlyConnectionCards.card(c, mainId, orgs));
            used.add(c.Provider__c);
        }
        for (String p : PROVIDER_ORDER) {
            if (!used.contains(p)) {
                out.notSetUp.add(p);
            }
        }
        return out;
    }

    /**
     * @description Adds a connection for a provider not used yet, or changes one; it's checked next by checkConnection.
     * @param connectionJson the connection's fields as JSON (Id to change one)
     * @return the connection's Id
     */
    @AuraEnabled
    public static Id saveConnection(String connectionJson) {
        requireAdmin();
        RLY_Git_Connection__c input = readInput(connectionJson);
        List<String> problems = RlyGitValidator.validate(input);
        if (!problems.isEmpty()) {
            throw problem(String.join(problems, '. ') + '.');
        }
        String refused = RlyConnectionRules.problemOf(input, RlyConnectionStore.connections());
        if (refused != null) {
            throw problem(refused);
        }
        RLY_Git_Connection__c row = RlyConnectionCards.rowOf(input);
        row.Active__c = RlyConnectionRules.activeOf(input, input.Id == null ? null : RlyConnectionStore.byId(input.Id));
        RlyConnectionStore.save(row);
        return row.Id;
    }

    /**
     * @description Checks a connection: its repository, pipeline files and every branch of its route. Callouts first,
     * one save at the end.
     * @param connectionId the connection
     * @return its card as saved
     */
    @AuraEnabled
    public static RlyConnectionCards.Card checkConnection(Id connectionId) {
        RlyHubGuard.requireHub();
        requireAdmin();
        RLY_Git_Connection__c c = requireConnection(connectionId);
        Id mainId = mainId();
        RlyConnectionStore.save(RlyGitCheck.run(c, RlyConnectionStore.orgsOn(c.Id, mainId)));
        return RlyConnectionCards.card(requireConnection(connectionId), mainId, RlyConnectionStore.orgs());
    }

    /**
     * @description Creates a connection's missing route branches from its pipeline branch, in parts: the page calls again
     * from nextIndex until it's null.
     * @param connectionId the connection
     * @param fromIndex where this part starts (0 first)
     * @return the branches created and where the next part starts
     */
    @AuraEnabled
    public static RlyBranchCreate.Result createBranchesFor(Id connectionId, Integer fromIndex) {
        RlyHubGuard.requireHub();
        requireAdmin();
        RLY_Git_Connection__c c = requireConnection(connectionId);
        try {
            return RlyBranchCreate.part(c, RlyBranchCreate.branchesOf(RlyConnectionStore.orgsOn(c.Id, mainId())), fromIndex);
        } catch (Exception e) {
            throw problem(e.getMessage());
        }
    }

    /**
     * @description A connection's pipeline files: the version packaged with the hub and the version in its repository.
     * @param connectionId the connection
     * @return the status
     */
    @AuraEnabled
    public static RlyPipelineFiles.Status pipelineFilesFor(Id connectionId) {
        return RlyPipelineFiles.currentStatusFor(requireConnection(connectionId));
    }

    /**
     * @description Writes the packaged pipeline files for a connection's provider to its repository (admins).
     * @param connectionId the connection
     * @param how pullRequest (the default) or commit
     * @return what happened, with the pull request's or commit's link
     */
    @AuraEnabled
    public static RlyPipelineFiles.UpdateResult updatePipelineFilesFor(Id connectionId, String how) {
        RlyHubGuard.requireHub();
        requireAdmin();
        return RlyPipelineFiles.updateRepositoryFor(requireConnection(connectionId), how);
    }

    /**
     * @description Whether a branch is in a connection's repository (Register / edit org). Callouts only.
     * @param connectionId the connection (blank: the main one)
     * @param branch the branch
     * @return found, and the message the page shows
     */
    @AuraEnabled
    public static RlyConnectionCards.BranchCheck checkBranch(Id connectionId, String branch) {
        requireAdmin();
        return RlyConnectionCards.branchCheck(connectionId == null ? RlyReleaseStore.git() : RlyConnectionStore.byId(connectionId), branch);
    }

    // ---------- helpers ----------

    private static RLY_Git_Connection__c readInput(String connectionJson) {
        try {
            return (RLY_Git_Connection__c) JSON.deserialize(connectionJson, RLY_Git_Connection__c.class);
        } catch (Exception e) {
            throw problem('The Git connection couldn\'t be read.');
        }
    }

    private static RLY_Git_Connection__c requireConnection(Id connectionId) {
        RLY_Git_Connection__c c = connectionId == null ? null : RlyConnectionStore.byId(connectionId);
        if (c == null) {
            throw problem('That Git connection isn\'t there any more.');
        }
        return c;
    }

    private static Id mainId() {
        RLY_Git_Connection__c main = RlyReleaseStore.git();
        return main == null ? null : main.Id;
    }

    private static void requireAdmin() {
        if (!RlyOrgController.isAdmin()) {
            throw problem('Changing the pipeline needs the Release Relay Admin permission set.');
        }
    }

    private static AuraHandledException problem(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
