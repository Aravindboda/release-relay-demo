/**
 * @description Adds changes from the release's developer org to an open release (who and when: RlyAppendRules): a normal release (not a promotion,
 * back promote or manual-steps-only release) with an open pull request whose checks failed or that waits for approval
 * (not approved yet), by the user who raised it or an admin. The new components are retrieved the way a raise retrieves
 * them (the callout before any DML); the release goes back to Retrieving with its approval cleared, and the reader
 * (RlyStatusReader, RlyAppendRun) commits .relay-inbox/<REL>-add-<k>.zip to its branch and runs the pipeline in mode hub
 * with append, so the open pull request updates and the checks run again. Tests: the release's and the new ones.
 */
public with sharing class RlyAppendService {

    /** @description What the builder sends in append mode. */
    public class AppendRequest {
        /** @description The release to add to. */
        public Id releaseId;
        /** @description The components to add. */
        public List<RlyRaiseService.Item> items;
        /** @description The components to delete. */
        public List<RlyRaiseService.Item> deletions;
        /** @description The test classes added (they must be among the components added). */
        public List<String> testClasses;
    }

    /** @description What the builder needs to start in append mode. */
    public class AppendStart {
        /** @description The release. */
        @AuraEnabled public Id releaseId;
        /** @description Its number. */
        @AuraEnabled public String name;
        /** @description Its title. */
        @AuraEnabled public String title;
        /** @description The developer org it came from. */
        @AuraEnabled public Id sourceOrgId;
        /** @description Its name. */
        @AuraEnabled public String sourceName;
        /** @description The target org's name. */
        @AuraEnabled public String targetName;
        /** @description The target branch. */
        @AuraEnabled public String targetBranch;
        /** @description What's in the release already (deleted true for its deletions). */
        @AuraEnabled public List<Map<String, Object>> components = new List<Map<String, Object>>();
        /** @description Its test classes. */
        @AuraEnabled public List<String> tests = new List<String>();
    }

    /**
     * @description The release, what's in it and where it goes, for the builder.
     * @param releaseId the release
     * @return the start
     */
    public static AppendStart start(Id releaseId) {
        RLY_Release__c rel = RlyAppendRules.checked(releaseId);
        AppendStart s = new AppendStart();
        s.releaseId = rel.Id;
        s.name = rel.Name;
        s.title = rel.Title__c;
        s.sourceOrgId = rel.Source_Org__c;
        s.sourceName = rel.Source_Org__r == null ? null : rel.Source_Org__r.Name;
        s.targetName = rel.Target_Org__r == null ? null : rel.Target_Org__r.Name;
        s.targetBranch = rel.Target_Branch__c;
        s.tests = RlyReleasePhase.tests(rel);
        for (RLY_Release_Item__c i : RlyReleaseStore.items(rel.Id)) {
            s.components.add(new Map<String, Object>{ 'type' => i.Metadata_Type__c, 'name' => i.Component_Name__c,
                'deleted' => i.Is_Deletion__c == true });
        }
        return s;
    }

    /**
     * @description Starts the retrieve of the new components and saves the release waiting for it.
     * @param req the request
     * @return the release Id
     */
    public static Id append(AppendRequest req) {
        RlyHubGuard.requireHub();
        RLY_Release__c rel = RlyAppendRules.checked(req == null ? null : req.releaseId);
        RLY_Org__c source = RlyRaiseRoute.source(rel.Source_Org__c);
        Set<String> inRelease = RlyAppendRules.keysIn(rel.Id);
        List<RlyRaiseService.Item> added = RlyAppendRules.notIn(RlyDeletionRules.added(RlyAppendRules.asRaise(req)), inRelease);
        List<String> deletions = RlyAppendRules.newDeletions(req, source, inRelease);
        if (added.isEmpty() && deletions.isEmpty()) {
            throw new RlyReleaseException('Pick at least one component that isn\'t in ' + rel.Name + ' yet.');
        }
        Map<String, Set<String>> byType = RlyRaiseRules.byType(added, source);
        Set<String> tests = RlyAppendRules.newTests(req, rel);
        if (!tests.isEmpty() || RlyReleasePhase.tests(rel).isEmpty()) {
            RlyTestRule.checkTests(added, byType, tests);
        }

        String retrieveId = byType.isEmpty() ? null : RlyRetrieve.start(source, byType); // callout before any DML

        RLY_Release__c prior = rel.clone(true, true, true, true);
        RlyAppendRun.State st = RlyAppendRun.stateOf(rel);
        st.adds += 1;
        st.pending = true;
        st.fromOrg = source.Name;
        st.components = keysOf(added);
        st.deletions = deletions;
        st.tests = new List<String>(tests);
        RlyAppendRun.writeState(rel, st);
        reopen(rel, retrieveId);
        RlySlackCardSync.notifyChange(prior, rel); // the Slack callouts come before the saves
        RlyReleaseStore.save(rel);
        RlySlack.saveResults();
        RlyReleaseLog.add(rel, 'Raised', 'Added ' + words(st) + ' from ' + source.Name + ': ' + names(st))
            .inOrg(source.Id).byActor(UserInfo.getUserId(), RlyReleaseLog.VIA_SALESFORCE);
        RlyReleaseLog.flush();
        return rel.Id;
    }

    // Back to Retrieving, its checks and approval cleared like Check again (the checks run again after the add).
    private static void reopen(RLY_Release__c rel, String retrieveId) {
        rel.Retrieve_Id__c = retrieveId;
        rel.Status__c = 'Retrieving';
        rel.Pending_Run__c = null;
        rel.Error_Message__c = null;
        rel.Checks_Requested__c = System.now();
        rel.Scan_Status__c = RlyScanRule.statusFor(RlyReleaseStore.git(), RlyScanRule.targetOf(rel));
        rel.Validation_Status__c = String.isBlank(rel.Target_Environment__c) ? 'Not configured' : 'Pending';
        rel.Scan_Bypassed_By__c = null;
        rel.Scan_Bypass_Reason__c = null;
        rel.Approval_Status__c = 'Pending';
        rel.Approved_By__c = null;
        rel.Approved_On__c = null;
        rel.Approved_Via__c = null;
        rel.Second_Approved_By__c = null;
        rel.Second_Approved_On__c = null;
        rel.Last_Synced__c = System.now();
    }

    private static List<String> keysOf(List<RlyRaiseService.Item> items) {
        List<String> out = new List<String>();
        for (RlyRaiseService.Item i : items) {
            out.add(i.type.left(80) + ':' + i.name.left(255));
        }
        return out;
    }

    // "1 component", "2 components and 1 deletion".
    private static String words(RlyAppendRun.State st) {
        Integer n = st.components.size();
        Integer d = st.deletions.size();
        String added = n == 0 ? '' : n + (n == 1 ? ' component' : ' components');
        String deleted = d == 0 ? '' : d + (d == 1 ? ' deletion' : ' deletions');
        return String.isBlank(added) || String.isBlank(deleted) ? added + deleted : added + ' and ' + deleted;
    }

    // The names, up to five, then "and n more".
    private static String names(RlyAppendRun.State st) {
        List<String> everything = new List<String>();
        for (String k : st.components) {
            everything.add(k.substringAfter(':'));
        }
        for (String k : st.deletions) {
            everything.add(k.substringAfter(':') + ' (deleted)');
        }
        List<String> shown = new List<String>();
        for (Integer i = 0; i < everything.size() && i < RlyDeletions.SHOWN; i++) {
            shown.add(everything[i]);
        }
        Integer more = everything.size() - shown.size();
        return String.join(shown, ', ') + (more > 0 ? ' and ' + more + ' more' : '');
    }
}
