/**
 * @description Several Git connections (build 45): what the Pipeline tab's Git connections cards and the org modal's
 * connection picker show, built from the connection records (no callouts: the provider class gives its name, web
 * address and what it calls a pull request).
 */
public with sharing class RlyConnectionCards {

    private static final Pattern BRANCH_PATTERN = Pattern.compile('^[A-Za-z0-9._/-]{1,100}$');

    /** @description Whether a branch is in a connection's repository. */
    public class BranchCheck {
        /** @description It's there. */
        @AuraEnabled public Boolean found = false;
        /** @description The provider's name. */
        @AuraEnabled public String provider;
        /** @description For example "sit exists in GitLab". */
        @AuraEnabled public String message;
    }

    /** @description A connection an org can be registered on (the org modal's picker). */
    public class Choice {
        /** @description The connection. */
        @AuraEnabled public Id id;
        /** @description For example GitLab release-relay-group/release-relay-gitlab. */
        @AuraEnabled public String label;
        /** @description Its provider's name, for example GitLab. */
        @AuraEnabled public String provider;
        /** @description It's in use (only active connections can take orgs). */
        @AuraEnabled public Boolean active;
        /** @description The hub's main connection (orgs without one are on it). */
        @AuraEnabled public Boolean isMain;
    }

    /** @description One Git connections card. */
    public class Card {
        /** @description The connection. */
        @AuraEnabled public Id id;
        /** @description GitHub, GitLab, Bitbucket or AzureDevOps. */
        @AuraEnabled public String provider;
        /** @description The provider's name as people know it. */
        @AuraEnabled public String providerLabel;
        /** @description owner/repo or group/project. */
        @AuraEnabled public String repository;
        /** @description Not checked, Connected or Failed. */
        @AuraEnabled public String status;
        /** @description The connection's own fields: Named Credential, pipeline file and branch, source path, code scan, last check. */
        @AuraEnabled public RLY_Git_Connection__c record;
        /** @description In use. */
        @AuraEnabled public Boolean active;
        /** @description The main connection. */
        @AuraEnabled public Boolean isMain;
        /** @description Its developer and stage orgs, by name. */
        @AuraEnabled public List<String> orgNames = new List<String>();
        /** @description The repository's web address, or null. */
        @AuraEnabled public String webUrl;
        /** @description Pull request or Merge request. */
        @AuraEnabled public String changeRequestLabel;
    }

    /**
     * @description The connections an org can be on, the main one first.
     * @return the choices
     */
    public static List<Choice> choices() {
        List<Choice> out = new List<Choice>();
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        for (RLY_Git_Connection__c c : conns) {
            Choice ch = new Choice();
            ch.id = c.Id;
            ch.label = RlyPromoteConnection.labelOf(conns, c.Id);
            ch.provider = RlyGitName.labelFor(c);
            ch.active = c.Active__c == true;
            ch.isMain = c.Id == conns[0].Id;
            out.add(ch);
        }
        return out;
    }

    /**
     * @description One connection's card.
     * @param c the connection
     * @param mainId the main connection's Id
     * @param orgs the registered orgs
     * @return the card
     */
    public static Card card(RLY_Git_Connection__c c, Id mainId, List<RLY_Org__c> orgs) {
        Card k = new Card();
        k.id = c.Id;
        k.record = c;
        k.provider = c.Provider__c;
        k.repository = c.Repository__c;
        k.status = c.Status__c;
        k.active = c.Active__c == true;
        k.isMain = c.Id == mainId;
        for (RLY_Org__c o : orgs) {
            if (o.Role__c != 'Hub' && o.Role__c != RlyBackPromote.ROLE && RlyConnectionRoutes.connectionIdOf(o, mainId) == c.Id) {
                k.orgNames.add(o.Name);
            }
        }
        try {
            RlyGit git = RlyGit.forConnection(c);
            k.providerLabel = git.providerLabel();
            k.webUrl = git.webUrl();
            k.changeRequestLabel = git.changeRequestLabel();
        } catch (Exception e) {
            k.providerLabel = c.Provider__c;
        }
        return k;
    }

    /**
     * @description The row to save from what the page sent (checked by RlyGitValidator first). Saving always asks for a
     * new check.
     * @param input the connection as sent
     * @return the row (Active__c is set by the caller)
     */
    public static RLY_Git_Connection__c rowOf(RLY_Git_Connection__c input) {
        return new RLY_Git_Connection__c(Id = input.Id,
            Name = (input.Provider__c + ' ' + input.Repository__c.trim()).left(80),
            Provider__c = input.Provider__c, Repository__c = input.Repository__c.trim(),
            Named_Credential__c = input.Named_Credential__c.trim(),
            Pipeline__c = String.isBlank(input.Pipeline__c) ? null : input.Pipeline__c.trim(),
            Pipeline_Branch__c = input.Pipeline_Branch__c.trim(), Source_Path__c = input.Source_Path__c.trim().removeEnd('/'),
            Code_Scan__c = input.Code_Scan__c != false, Status__c = 'Not checked', Status_Message__c = null);
    }

    /**
     * @description Whether a branch is in a connection's repository (Register / edit org). Callouts only.
     * @param c the connection, or null
     * @param branch the branch
     * @return found, and the message the page shows ("sit exists in GitLab")
     */
    public static BranchCheck branchCheck(RLY_Git_Connection__c c, String branch) {
        BranchCheck r = new BranchCheck();
        if (String.isBlank(branch) || !BRANCH_PATTERN.matcher(branch.trim()).matches() || branch.contains('..')) {
            r.message = 'Type a branch name such as sit.';
            return r;
        }
        if (c == null) {
            r.message = 'Save the Git connection first.';
            return r;
        }
        String b = branch.trim();
        try {
            RlyGit git = RlyGit.forConnection(c);
            r.provider = git.providerLabel();
            r.found = git.branchExists(b);
            r.message = r.found ? b + ' exists in ' + r.provider : b + ' isn\'t in ' + r.provider + ' yet: Create missing branches makes it.';
        } catch (Exception e) {
            r.message = 'Couldn\'t check the branch: ' + e.getMessage();
        }
        return r;
    }
}
