/**
 * @description What New Release step 1 shows: the registered developer orgs (without sign-in fields), where
 * releases go (the first stage of the route), the repository, anything that blocks raising a release, and, for
 * users with the RLY_Hotfix permission, the stage orgs a hotfix can be raised from (with their next stop).
 */
public with sharing class RlyReleaseStart {

    /** @description What step 1 shows. */
    public class Start {
        /** @description Registered developer orgs, without sign-in fields. */
        @AuraEnabled public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        /** @description The first stage's name. */
        @AuraEnabled public String targetName;
        /** @description The first stage's branch. */
        @AuraEnabled public String targetBranch;
        /** @description The Git repository. */
        @AuraEnabled public String repository;
        /** @description The Git provider's name, for example GitHub (null without a connection). */
        @AuraEnabled public String provider;
        /** @description The current user's name, for Changed by me. */
        @AuraEnabled public String hubUserName;
        /** @description What blocks raising a release. */
        @AuraEnabled public List<String> problems = new List<String>();
        /** @description The current user may raise hotfixes from stage orgs. */
        @AuraEnabled public Boolean canHotfix = false;
        /** @description Stage orgs a hotfix can be raised from (only with RLY_Hotfix). */
        @AuraEnabled public List<RlyHotfix.StageSource> stageSources = new List<RlyHotfix.StageSource>();
        /** @description Stage and hub orgs, shown in their environment for context (no sign-in fields). */
        @AuraEnabled public List<RLY_Org__c> routeStops = new List<RLY_Org__c>();
    }

    /**
     * @description Reads the orgs and the Git connection and builds step 1.
     * @return what step 1 shows
     */
    public static Start build() {
        Data data = new Data();
        Start s = new Start();
        s.hubUserName = UserInfo.getName();
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        for (RLY_Org__c o : data.orgs()) {
            if (o.Role__c == 'Developer') {
                s.developers.add(o);
            } else {
                s.routeStops.add(o);
                if (o.Role__c == 'Stage') {
                    stages.add(o);
                }
            }
        }
        RLY_Org__c target = firstStage(stages);
        if (target != null) {
            s.targetName = target.Name;
            s.targetBranch = target.Branch__c;
        }
        RLY_Git_Connection__c git = data.git();
        s.repository = git == null ? null : git.Repository__c;
        s.provider = RlyGitName.labelFor(git);
        s.canHotfix = RlyHotfix.allowed();
        if (s.canHotfix) {
            s.stageSources = RlyHotfix.stageSources(RlyReleaseStore.routeOrgs());
        }
        addProblems(s, git, target);
        return s;
    }

    // The stage with the lowest order (stages without one come after).
    private static RLY_Org__c firstStage(List<RLY_Org__c> stages) {
        RLY_Org__c target;
        for (RLY_Org__c o : stages) {
            if (target == null || comesBefore(o, target)) {
                target = o;
            }
        }
        return target;
    }

    private static Boolean comesBefore(RLY_Org__c o, RLY_Org__c other) {
        return o.Stage_Order__c != null && (other.Stage_Order__c == null || o.Stage_Order__c < other.Stage_Order__c);
    }

    private static void addProblems(Start s, RLY_Git_Connection__c git, RLY_Org__c target) {
        if (git == null || git.Status__c != 'Connected') {
            s.problems.add('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        if (target == null || String.isBlank(target.Branch__c)) {
            s.problems.add('No stage to release into yet: register the first stage org with its branch (Pipeline tab).');
        }
        if (s.developers.isEmpty() && s.stageSources.isEmpty()) {
            s.problems.add('No developer org registered yet (Pipeline tab).');
        }
    }

    /** @description Registered orgs and the Git connection are shared hub records, read in system mode for every user. */
    private without sharing class Data {

        /**
         * @description Registered orgs for the page: no sign-in fields.
         * @return the orgs, by name
         */
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Git_Environment__c, Status__c, Source_Tracking__c,
                           Org_Type__c, Is_Sandbox__c, Environment__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description The hub's Git connection.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Status__c FROM RLY_Git_Connection__c
                                                WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
