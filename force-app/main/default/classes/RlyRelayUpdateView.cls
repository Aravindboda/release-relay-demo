/**
 * @description Install Release Relay update: what the card shows. Org names come from the route (the update's test
 * org and the hub), never from code. Built from records only (no callouts).
 */
public with sharing class RlyRelayUpdateView {

    /** @description The test org's name in the labels until a stage is chosen. */
    public static final String TEST_ORG = 'Test org';

    /** @description The card. */
    public class Card {
        /** @description The current user is a Release Relay admin (the card shows only then). */
        @AuraEnabled public Boolean visible = false;
        /** @description The Git connection's provider, or null. */
        @AuraEnabled public String provider;
        /** @description The connection's repository, or null. */
        @AuraEnabled public String repository;
        /** @description The provider can copy the zip from the hub (GitHub, GitLab). */
        @AuraEnabled public Boolean supported = false;
        /** @description The hub has a run-signing key (its runs are signed). */
        @AuraEnabled public Boolean signed = false;
        /** @description The stages an update can be tested in. */
        @AuraEnabled public List<Choice> stages = new List<Choice>();
        /** @description The hub's (production's) name. */
        @AuraEnabled public String prodName;
        /** @description The newest update, or null. */
        @AuraEnabled public UpdateView current;
    }

    /** @description A stage to test in. */
    public class Choice {
        /** @description The org record's id. */
        @AuraEnabled public String value;
        /** @description Its name. */
        @AuraEnabled public String label;
        /** @description Its install branch. */
        @AuraEnabled public String help;
    }

    /** @description One update. */
    public class UpdateView {
        /** @description Record id. */
        @AuraEnabled public String id;
        /** @description UPD-… */
        @AuraEnabled public String name;
        /** @description The update branch. */
        @AuraEnabled public String branch;
        /** @description The title. */
        @AuraEnabled public String title;
        /** @description The test org's id. */
        @AuraEnabled public String testOrgId;
        /** @description The test org's name. */
        @AuraEnabled public String testOrgName;
        /** @description The zip's path on the update branch. */
        @AuraEnabled public String zipPath;
        /** @description How many test classes each step runs. */
        @AuraEnabled public Integer testsCount = 0;
        /** @description zip or org. */
        @AuraEnabled public String testsFrom;
        /** @description How many components the checks list. */
        @AuraEnabled public Integer componentsCount = 0;
        /** @description A step is running. */
        @AuraEnabled public Boolean running = false;
        /** @description Production's install deployed. */
        @AuraEnabled public Boolean installed = false;
        /** @description The four steps, in order. */
        @AuraEnabled public List<StepView> steps = new List<StepView>();
    }

    /** @description One step. */
    public class StepView {
        /** @description test-check, test-install, prod-check or prod-install. */
        @AuraEnabled public String key;
        /** @description 1 to 4. */
        @AuraEnabled public Integer n;
        /** @description For example SIT check (the org's name). */
        @AuraEnabled public String label;
        /** @description Running, Passed, Installed, Failed, or null when not started. */
        @AuraEnabled public String status;
        /** @description The request id it ran with. */
        @AuraEnabled public String requestId;
        /** @description The run's link (https only). */
        @AuraEnabled public String runUrl;
        /** @description Tests run. */
        @AuraEnabled public Integer testsRun;
        /** @description Test failures and component errors. */
        @AuraEnabled public List<String> failures = new List<String>();
        /** @description The result's message. */
        @AuraEnabled public String message;
        /** @description It may start now. */
        @AuraEnabled public Boolean startable = false;
        /** @description The first step failed and can run again (on a new update). */
        @AuraEnabled public Boolean retry = false;
        /** @description When it started. */
        @AuraEnabled public Datetime startedAt;
        /** @description Who started it. */
        @AuraEnabled public String startedBy;
        /** @description When its result was written. */
        @AuraEnabled public String finishedAt;
    }

    /**
     * @description The card for the current user (admins only; everyone else gets visible = false and nothing else).
     * @return the card
     */
    public static Card build() {
        Card c = new Card();
        if (!RlyReleaseAccess.isAdmin()) {
            return c;
        }
        c.visible = true;
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        if (conn != null) {
            c.provider = conn.Provider__c;
            c.repository = conn.Repository__c;
            c.supported = RlyRelayUpdateGit.supports(conn.Provider__c);
        }
        c.signed = RlyRunKeyStore.key() != null;
        for (RLY_Org__c o : RlyReleaseStore.pipelineOrgs(new Set<String>{ 'Stage', 'Hub' })) {
            if (o.Role__c == 'Hub') {
                c.prodName = c.prodName == null ? o.Name : c.prodName;
            } else {
                c.stages.add(choice(o));
            }
        }
        c.current = updateView(RlyRelayUpdateStore.current(), c.prodName);
        return c;
    }

    /**
     * @description The name of the stage an update is checked and installed in, for its step labels: its org's name;
     * when the update has no org record any more (the org was removed or registered again), the stage whose Git
     * environment its test steps ran in; "Test org" only when no stage is known.
     * @param u the update (with Test_Org__r.Name when it was read from the store)
     * @return the name
     */
    public static String testOrgName(RLY_Relay_Update__c u) {
        if (u == null) {
            return TEST_ORG;
        }
        if (u.Test_Org__r != null && String.isNotBlank(u.Test_Org__r.Name)) {
            return u.Test_Org__r.Name;
        }
        String env = testEnvironment(u);
        List<RLY_Org__c> stages = RlyReleaseStore.pipelineOrgs(new Set<String>{ 'Stage' });
        for (RLY_Org__c o : stages) {
            Boolean sameEnv = env != null && String.isNotBlank(o.Git_Environment__c) && o.Git_Environment__c.trim().equalsIgnoreCase(env);
            if (o.Id == u.Test_Org__c || sameEnv) {
                return o.Name;
            }
        }
        return TEST_ORG;
    }

    // The Git environment the update's test check (or install) ran in, or null before it started.
    private static String testEnvironment(RLY_Relay_Update__c u) {
        Map<String, RlyRelayUpdateState.Step> steps = RlyRelayUpdateState.read(u);
        for (String key : new List<String>{ RlyRelayUpdateState.TEST_CHECK, RlyRelayUpdateState.TEST_INSTALL }) {
            RlyRelayUpdateState.Step s = steps.get(key);
            if (s != null && String.isNotBlank(s.environment)) {
                return s.environment.trim();
            }
        }
        return null;
    }

    private static Choice choice(RLY_Org__c o) {
        Choice ch = new Choice();
        ch.value = o.Id;
        ch.label = o.Name;
        ch.help = String.isBlank(o.Git_Environment__c) ? 'No Git environment set' : 'rly-' + o.Git_Environment__c.trim().toLowerCase() + '-install';
        return ch;
    }

    private static UpdateView updateView(RLY_Relay_Update__c u, String prodName) {
        if (u == null) {
            return null;
        }
        UpdateView v = new UpdateView();
        v.id = u.Id;
        v.name = u.Name;
        v.branch = u.Branch__c;
        v.title = u.Title__c;
        v.testOrgId = u.Test_Org__c;
        v.testOrgName = testOrgName(u);
        v.zipPath = u.Zip_Path__c;
        v.testsCount = String.isBlank(u.Tests__c) ? 0 : u.Tests__c.split(',').size();
        v.testsFrom = u.Tests_From__c;
        v.componentsCount = String.isBlank(u.Components__c) ? 0 : u.Components__c.split(',').size();
        Map<String, RlyRelayUpdateState.Step> steps = RlyRelayUpdateState.read(u);
        v.running = RlyRelayUpdateState.running(steps) != null;
        v.installed = RlyRelayUpdateState.isDone(steps.get(RlyRelayUpdateState.PROD_INSTALL));
        List<String> labels = new List<String>{ v.testOrgName + ' check', v.testOrgName + ' install',
            (prodName == null ? 'Production' : prodName) + ' check', (prodName == null ? 'Production' : prodName) + ' install' };
        for (Integer i = 0; i < RlyRelayUpdateState.ORDER.size(); i++) {
            v.steps.add(stepView(steps, i, labels[i]));
        }
        return v;
    }

    private static StepView stepView(Map<String, RlyRelayUpdateState.Step> steps, Integer i, String label) {
        String key = RlyRelayUpdateState.ORDER[i];
        StepView sv = new StepView();
        sv.key = key;
        sv.n = i + 1;
        sv.label = label;
        sv.startable = RlyRelayUpdateState.canStart(steps, key);
        sv.retry = i == 0 && RlyRelayUpdateState.canRetryFirst(steps);
        RlyRelayUpdateState.Step s = steps.get(key);
        if (s != null) {
            sv.status = s.status;
            sv.requestId = s.requestId;
            sv.runUrl = RlyRelayUpdateOutcome.https(s.runUrl);
            sv.testsRun = s.testsRun;
            sv.failures = s.failures == null ? new List<String>() : s.failures;
            sv.message = s.message;
            sv.startedAt = s.startedAt;
            sv.startedBy = s.startedBy;
            sv.finishedAt = s.finishedAt;
        }
        return sv;
    }
}
