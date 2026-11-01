/**
 * @description Approval rules per target org (RLY_Org__c.Approval_Rule__c): Always (the default), Selected_Types (only
 * when the release contains one of Approval_Types__c) or Never (deploys when the checks pass). The mapping of metadata
 * types to the kinds of change (buckets) lives here: Apex, Flows, Profiles_Permissions, Objects_Fields, Deletions,
 * Manual_Steps, Hotfix, and Other for anything not in another bucket. A hotfix into an org that needs two approvers
 * always needs them, whatever the rule says.
 */
public with sharing class RlyApprovalRules {

    /** @description Approval_Rule__c: every release needs an approver (the default; blank means this too). */
    public static final String RULE_ALWAYS = 'Always';
    /** @description Approval_Rule__c: only releases that contain one of the org's Approval_Types__c. */
    public static final String RULE_SELECTED = 'Selected_Types';
    /** @description Approval_Rule__c: no approver; the release deploys when its checks pass. */
    public static final String RULE_NEVER = 'Never';
    /** @description Every rule, in the order the page shows them. */
    public static final List<String> RULES = new List<String>{ RULE_ALWAYS, RULE_SELECTED, RULE_NEVER };
    /** @description Bucket: Apex classes and triggers. */
    public static final String TYPE_APEX = 'Apex';
    /** @description Bucket: flows. */
    public static final String TYPE_FLOWS = 'Flows';
    /** @description Bucket: profiles, permission sets and the like. */
    public static final String TYPE_PERMISSIONS = 'Profiles_Permissions';
    /** @description Bucket: objects, fields, record types and validation rules. */
    public static final String TYPE_OBJECTS = 'Objects_Fields';
    /** @description Bucket: the release deletes components. */
    public static final String TYPE_DELETIONS = 'Deletions';
    /** @description Bucket: the release has manual steps. */
    public static final String TYPE_MANUAL = 'Manual_Steps';
    /** @description Bucket: the release is a hotfix. */
    public static final String TYPE_HOTFIX = 'Hotfix';
    /** @description Bucket: anything not in another bucket. */
    public static final String TYPE_OTHER = 'Other';
    /** @description Every bucket, in the order the page shows them. */
    public static final List<String> TYPES = new List<String>{ TYPE_APEX, TYPE_FLOWS, TYPE_PERMISSIONS, TYPE_OBJECTS,
        TYPE_DELETIONS, TYPE_MANUAL, TYPE_HOTFIX, TYPE_OTHER };
    /** @description The page's label of each bucket. */
    public static final Map<String, String> TYPE_LABELS = new Map<String, String>{
        TYPE_APEX => 'Apex classes and triggers', TYPE_FLOWS => 'Flows', TYPE_PERMISSIONS => 'Profiles and permission sets',
        TYPE_OBJECTS => 'Objects and fields', TYPE_DELETIONS => 'Deletions', TYPE_MANUAL => 'Manual steps',
        TYPE_HOTFIX => 'Hotfixes', TYPE_OTHER => 'Anything else' };
    /** @description The page's label of each rule. */
    public static final Map<String, String> RULE_LABELS = new Map<String, String>{
        RULE_ALWAYS => 'Always', RULE_SELECTED => 'Only when the release contains…', RULE_NEVER => 'Never: deploy when the checks pass' };

    private static final Map<String, String> BUCKET_OF_TYPE = new Map<String, String>{
        'ApexClass' => TYPE_APEX, 'ApexTrigger' => TYPE_APEX, 'Flow' => TYPE_FLOWS, 'FlowDefinition' => TYPE_FLOWS,
        'Profile' => TYPE_PERMISSIONS, 'PermissionSet' => TYPE_PERMISSIONS, 'PermissionSetGroup' => TYPE_PERMISSIONS,
        'CustomPermission' => TYPE_PERMISSIONS, 'MutingPermissionSet' => TYPE_PERMISSIONS, 'CustomObject' => TYPE_OBJECTS,
        'CustomField' => TYPE_OBJECTS, 'RecordType' => TYPE_OBJECTS, 'ValidationRule' => TYPE_OBJECTS };
    /** @description Whether a release needs an approver, and why. */
    public class Decision {
        /** @description True when an approver must approve it. */
        public Boolean needed = true;
        /** @description For example "Needs approval: contains a Flow and a Profile" or "Approved automatically: only reports". */
        public String reason;
    }

    /** @description What a release contains, as the rule reads it. */
    public class Contents {
        /** @description The metadata types it deploys (not its deletions). */
        public Set<String> metadataTypes = new Set<String>();
        /** @description It deletes components. */
        public Boolean deletes = false;
        /** @description It has manual steps. */
        public Boolean manualSteps = false;
        /** @description It is a hotfix. */
        public Boolean hotfix = false;
    }

    /**
     * @description The bucket of a metadata type.
     * @param metadataType for example ApexClass
     * @return Apex, Flows, Profiles_Permissions, Objects_Fields or Other
     */
    public static String bucketOf(String metadataType) {
        return BUCKET_OF_TYPE.containsKey(metadataType) ? BUCKET_OF_TYPE.get(metadataType) : TYPE_OTHER;
    }

    /**
     * @description An org's rule (blank is Always).
     * @param org the org, with Approval_Rule__c (or null)
     * @return Always, Selected_Types or Never
     */
    public static String ruleOf(RLY_Org__c org) {
        return org == null || String.isBlank(org.Approval_Rule__c) ? RULE_ALWAYS : org.Approval_Rule__c;
    }

    /**
     * @description An org's Approval_Types__c as a set.
     * @param org the org (or null)
     * @return the buckets
     */
    public static Set<String> typesOf(RLY_Org__c org) {
        Set<String> out = new Set<String>();
        if (org != null && String.isNotBlank(org.Approval_Types__c)) {
            for (String t : org.Approval_Types__c.split(';')) {
                out.add(t.trim());
            }
        }
        return out;
    }

    /**
     * @description What a release contains: its items' types, deletions, manual steps and hotfix flag.
     * @param rel the release, with Id, Is_Hotfix__c and Deletion_Count__c
     * @return the contents
     */
    public static Contents contentsOf(RLY_Release__c rel) {
        Contents c = new Contents();
        for (RLY_Release_Item__c i : RlyReleaseStore.items(rel.Id)) {
            if (i.Is_Deletion__c == true) {
                c.deletes = true;
            } else if (String.isNotBlank(i.Metadata_Type__c)) {
                c.metadataTypes.add(i.Metadata_Type__c);
            }
        }
        c.deletes = c.deletes || (rel.Deletion_Count__c != null && rel.Deletion_Count__c > 0);
        c.manualSteps = RlyManualStepGate.counts(rel).total() > 0;
        c.hotfix = RlyHotfix.isHotfix(rel);
        return c;
    }

    /**
     * @description Whether the release needs an approver in its target org, and why.
     * @param rel the release, with Target_Org__r (Name, Approval_Rule__c, Approval_Types__c, Hotfix_Two_Approvers__c)
     * @return the decision
     */
    public static Decision decide(RLY_Release__c rel) {
        return decideFor(rel, contentsOf(rel));
    }

    /**
     * @description Whether a release with these contents needs an approver in its target org, and why.
     * @param rel the release, with Target_Org__r
     * @param c what it contains
     * @return the decision
     */
    public static Decision decideFor(RLY_Release__c rel, Contents c) {
        Decision d = new Decision();
        RLY_Org__c target = rel.Target_Org__r;
        String orgName = target == null ? 'the target org' : target.Name;
        String rule = ruleOf(target);
        if (RlyTwoApprovers.needsTwo(rel)) {
            d.reason = 'Needs approval: a hotfix into ' + orgName + ' needs two approvers';
        } else if (rule == RULE_NEVER) {
            d.needed = false;
            d.reason = 'Approved automatically: ' + orgName + ' deploys when the checks pass';
        } else if (rule == RULE_SELECTED) {
            List<String> matched = RlyApprovalWords.matches(c, typesOf(target));
            d.needed = !matched.isEmpty();
            d.reason = d.needed ? 'Needs approval: ' + RlyApprovalWords.joined(matched) : 'Approved automatically: ' + RlyApprovalWords.onlyText(c);
        } else {
            d.reason = 'Always needs approval in ' + orgName;
        }
        return d;
    }
}
