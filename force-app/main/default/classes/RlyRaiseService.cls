/**
 * @description Raises a release: checks the request (RlyRaiseRules, RlyTestRule), starts the Metadata API retrieve in the
 * developer org and saves the release with its items. The retrieve callout comes before any DML.
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
        /** @description The selected Apex test classes. */
        public List<String> testClasses;
    }

    /**
     * @description Starts the retrieve in the developer org and saves the release.
     * @param req the request
     * @return the release Id
     */
    public static Id raise(RaiseRequest req) {
        RlyRaiseRules.checkRequest(req);
        RlyRaiseRules.Route route = RlyRaiseRules.route(req.sourceOrgId);
        Set<String> tests = RlyTestRule.testNames(req.testClasses);
        Map<String, Set<String>> byType = RlyRaiseRules.byType(req.items, route.source);
        RlyTestRule.checkTests(req.items, byType, tests);

        String retrieveId = RlyRetrieve.start(route.source, byType); // callout before any DML

        RLY_Release__c rel = buildRelease(req, route, tests);
        rel.Retrieve_Id__c = retrieveId;
        RlyReleaseStore.insertRelease(rel, buildItems(req.items));
        return rel.Id;
    }

    private static RLY_Release__c buildRelease(RaiseRequest req, RlyRaiseRules.Route route, Set<String> tests) {
        RLY_Org__c source = route.source;
        RLY_Org__c target = route.target;
        return new RLY_Release__c(
            Title__c = req.title.trim(), Description__c = req.description == null ? null : req.description.left(5000),
            Mode__c = 'Org changes', Request_Type__c = 'Changes', Status__c = 'Retrieving',
            Source_Org__c = source.Id, Target_Org__c = target.Id, Org_Label__c = source.Name.left(40),
            Target_Branch__c = target.Branch__c, Source_Environment__c = source.Git_Environment__c,
            Target_Environment__c = target.Git_Environment__c,
            Component_Count__c = req.items.size(), Deletion_Count__c = 0,
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
}
