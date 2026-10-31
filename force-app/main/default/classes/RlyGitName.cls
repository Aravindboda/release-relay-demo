/**
 * @description The Git provider's name as people know it (GitHub, GitLab, Bitbucket, Azure DevOps), read from the
 * provider class of a Git connection: the "In <provider>" approval option, the release page and New Release.
 */
public with sharing class RlyGitName {

    /**
     * @description The provider's name for a Git connection.
     * @param c the Git connection, or null
     * @return for example GitHub, or null when there's no usable connection
     */
    public static String labelFor(RLY_Git_Connection__c c) {
        if (c == null || String.isBlank(c.Provider__c) || String.isBlank(c.Named_Credential__c)) {
            return null;
        }
        try {
            return RlyGit.forConnection(c).providerLabel();
        } catch (RlyGit.GitException e) {
            return null;
        }
    }
}
