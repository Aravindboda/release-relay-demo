/**
 * @description Raises a release: checks the request (RlyRaiseRules, RlyTestRule), starts the Metadata API retrieve in the
 * developer org and saves the release with its items. A request flagged as a hotfix needs the RLY_Hotfix permission and
 * a reason (RlyHotfix.reason). The retrieve callout comes before any DML. Deletions (Type:Name, in Deletions__c and as items
 * with Is_Deletion__c) need no retrieve: a release with only deletions is saved Retrieving without a retrieve id, and
 * the next read commits its marker file instead of a zip (RlyStatusReader). Manual steps sent with it are checked
 * before the callout and saved with their runs in the first stage after the release (RlyManualStepRuns.addToRaised).
 */
public with sharing class RlyRaiseService {

    /** @description One selected component. */
    public class Item {
        /** @description Metadata type. */
        public String type;
        /** @description Full name. */
        public String name;
        /** @description Deleted in the developer org. */
        public Boolean deleted;
        /** @description A standard object, field or picklist. */
        public Boolean standard;
    }

    /** @description What the New Release page sends. */
    public class RaiseRequest {
        /** @description The developer org the changes come from. */
        public Id sourceOrgId;
        /** @description Release title (up to 200 characters). */
        public String title;
        /** @description Optional description. */
        public String description;
        /** @description The selected components. */
        public List<Item> items;
        /** @description The components to delete (type and name). */
        public List<Item> deletions;
        /** @description The selected Apex test classes. */
        public List<String> testClasses;
        /** @description Flagged as a hotfix (needs the RLY_Hotfix permission). */
        public Boolean isHotfix;
        /** @description Why it's a hotfix (required for a hotfix, up to 255 characters). */
        public String hotfixReason;
        /** @description Manual steps that travel with the release (up to 50), in order. */
        public List<RlyManualSteps.StepInput> manualSteps;
    }

    /**
     * @description Starts the retrieve in the developer org and saves the release.
     * @param req the request
     * @return the release Id
     */
    public static Id raise(RaiseRequest req) {
        RlyRaiseRules.checkRequest(req);
        String hotfixReason = RlyHotfix.reason(req);
        RlyRaiseRules.Route route = RlyRaiseRules.route(req.sourceOrgId);
        List<Item> added = RlyDeletionRules.added(req);
        List<String> deletions = RlyDeletionRules.deletions(req, route.source);
        Set<String> tests = RlyTestRule.testNames(req.testClasses);
        Map<String, Set<String>> byType = RlyRaiseRules.byType(added, route.source);
        RlyTestRule.checkTests(added, byType, tests);
        List<RLY_Manual_Step__c> steps = RlyManualStepRules.fromInputs(req.manualSteps);

        String retrieveId = byType.isEmpty() ? null : RlyRetrieve.start(route.source, byType); // callout before any DML

        RLY_Release__c rel = buildRelease(req, route, tests);
        rel.Retrieve_Id__c = retrieveId;
        rel.Is_Hotfix__c = hotfixReason != null;
        rel.Hotfix_Reason__c = hotfixReason;
        rel.Component_Count__c = added.size();
        rel.Deletion_Count__c = deletions.size();
        rel.Deletions__c = deletions.isEmpty() ? null : String.join(deletions, ',');
        List<RLY_Release_Item__c> items = buildItems(added);
        items.addAll(deletionItems(deletions));
        RlyReleaseStore.insertRelease(rel, items);
        RlyManualStepRuns.addToRaised(rel, steps, route.target);
        return rel.Id;
    }

    private static RLY_Release__c buildRelease(RaiseRequest req, RlyRaiseRules.Route route, Set<String> tests) {
        RLY_Org__c source = route.source;
        RLY_Org__c target = route.target;
        return new RLY_Release__c(
            Title__c = req.title.trim(), Description__c = req.description == null ? null : req.description.left(5000),
            Mode__c = 'Org changes', Request_Type__c = 'Changes', Release_Type__c = RlyPromotion.TYPE_RELEASE, Status__c = 'Retrieving',
            Source_Org__c = source.Id, Target_Org__c = target.Id, Org_Label__c = source.Name.left(40),
            Target_Branch__c = target.Branch__c, Source_Environment__c = source.Git_Environment__c,
            Target_Environment__c = target.Git_Environment__c,
            Test_Classes__c = String.join(new List<String>(tests), ','),
            Scan_Status__c = route.git.Code_Scan__c ? 'Pending' : 'Not configured',
            Validation_Status__c = String.isBlank(target.Git_Environment__c) ? 'Not configured' : 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Last_Synced__c = System.now());
    }

    private static List<RLY_Release_Item__c> buildItems(List<Item> selected) {
        List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        for (Item i : selected) {
            items.add(new RLY_Release_Item__c(Metadata_Type__c = i.type.left(80), Component_Name__c = i.name.left(255),
                Change_Type__c = 'Modified', Source__c = 'Detected'));
        }
        return items;
    }

    private static List<RLY_Release_Item__c> deletionItems(List<String> deletions) {
        List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        for (String k : deletions) {
            items.add(new RLY_Release_Item__c(Metadata_Type__c = k.substringBefore(':').left(80), Component_Name__c = k.substringAfter(':').left(255),
                Change_Type__c = 'Modified', Source__c = 'Detected', Is_Deletion__c = true));
        }
        return items;
    }
}
