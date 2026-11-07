/**
 * @description Creating the missing route branches in parts (build 37). Each branch is one check and, when missing, one
 * create (two calls), so a hub with many developer orgs could pass the 100-callout limit in one request. A part checks at
 * most MAX_CHECKS branches and creates at most MAX_CREATES, in branch-name order from a position the page passes back
 * (nextIndex), until done. Callouts only.
 */
public with sharing class RlyBranchCreate {

    /** @description Most branches checked in one call. */
    public static final Integer MAX_CHECKS = 40;
    /** @description Most branches created in one call. */
    public static final Integer MAX_CREATES = 20;

    /** @description What one part did. */
    public class Result {
        /** @description The branches created in this part. */
        @AuraEnabled public List<String> created = new List<String>();
        /** @description Where the next part starts, or null when every branch was checked. */
        @AuraEnabled public Integer nextIndex;
        /** @description How many route branches there are. */
        @AuraEnabled public Integer total = 0;
    }

    /**
     * @description The route's branches, each once, sorted.
     * @param orgs the registered orgs
     * @return the branch names
     */
    public static List<String> branchesOf(List<RLY_Org__c> orgs) {
        Set<String> seen = new Set<String>();
        for (RLY_Org__c o : orgs) {
            if (String.isNotBlank(o.Branch__c)) {
                seen.add(o.Branch__c.trim());
            }
        }
        List<String> out = new List<String>(seen);
        out.sort();
        return out;
    }

    /**
     * @description One part: checks the branches from a position and creates the missing ones from the pipeline branch.
     * @param conn the Git connection (its pipeline branch is where new branches start)
     * @param branches the route's branches (branchesOf)
     * @param fromIndex where to start, from 0
     * @return what was created and where the next part starts
     */
    public static Result part(RLY_Git_Connection__c conn, List<String> branches, Integer fromIndex) {
        RlyGit git = RlyGit.forConnection(conn);
        String fromRef = conn.Pipeline_Branch__c;
        Result r = new Result();
        r.total = branches.size();
        Integer i = fromIndex == null || fromIndex < 0 ? 0 : fromIndex;
        Integer checks = 0;
        while (i < branches.size() && checks < MAX_CHECKS && r.created.size() < MAX_CREATES) {
            String b = branches[i];
            checks++;
            if (!git.branchExists(b)) {
                git.createBranch(b, fromRef);
                r.created.add(b);
            }
            i++;
        }
        r.nextIndex = i < branches.size() ? i : null;
        return r;
    }
}
