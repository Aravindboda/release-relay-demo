/**
 * @description The words of the approval rules (RlyApprovalRules): "contains a Flow and a Profile", "only reports and list
 * views", and the org card's read-only rule line.
 */
public with sharing class RlyApprovalWords {

    // How a type reads in "contains a Flow and a Profile".
    private static final Map<String, String> TYPE_WORDS = new Map<String, String>{
        'ApexClass' => 'an Apex class', 'ApexTrigger' => 'an Apex trigger', 'Flow' => 'a Flow', 'FlowDefinition' => 'a Flow',
        'Profile' => 'a Profile', 'PermissionSet' => 'a permission set', 'PermissionSetGroup' => 'a permission set group',
        'CustomPermission' => 'a custom permission', 'MutingPermissionSet' => 'a muting permission set', 'CustomObject' => 'an object',
        'CustomField' => 'a field', 'RecordType' => 'a record type', 'ValidationRule' => 'a validation rule' };
    // How a type reads in "only reports and list views".
    private static final Map<String, String> PLURALS = new Map<String, String>{
        'Report' => 'reports', 'Dashboard' => 'dashboards', 'ListView' => 'list views', 'Layout' => 'page layouts',
        'FlexiPage' => 'Lightning pages', 'EmailTemplate' => 'email templates', 'CustomLabels' => 'custom labels',
        'CustomLabel' => 'custom labels', 'StaticResource' => 'static resources', 'LightningComponentBundle' => 'Lightning components',
        'CustomTab' => 'tabs', 'CustomApplication' => 'apps', 'QuickAction' => 'quick actions', 'ReportType' => 'report types' };

    /**
     * @description What in the release needs an approver under Selected_Types, in words.
     * @param c what the release contains
     * @param wanted the org's Approval_Types__c
     * @return the parts, for example "is a hotfix", "contains a Flow and deletions"
     */
    public static List<String> matches(RlyApprovalRules.Contents c, Set<String> wanted) {
        List<String> out = new List<String>();
        if (c.hotfix && wanted.contains(RlyApprovalRules.TYPE_HOTFIX)) {
            out.add('is a hotfix');
        }
        List<String> parts = typeWords(c.metadataTypes, wanted);
        if (c.deletes && wanted.contains(RlyApprovalRules.TYPE_DELETIONS)) {
            parts.add('deletions');
        }
        if (c.manualSteps && wanted.contains(RlyApprovalRules.TYPE_MANUAL)) {
            parts.add('manual steps');
        }
        if (!parts.isEmpty()) {
            out.add('contains ' + joined(parts));
        }
        return out;
    }

    private static List<String> typeWords(Set<String> types, Set<String> wanted) {
        List<String> sorted = new List<String>(types);
        sorted.sort();
        List<String> out = new List<String>();
        for (String t : sorted) {
            String word = TYPE_WORDS.containsKey(t) ? TYPE_WORDS.get(t) : t;
            if (wanted.contains(RlyApprovalRules.bucketOf(t)) && !out.contains(word)) {
                out.add(word);
            }
        }
        return out;
    }

    /**
     * @description "only reports and list views" (or "nothing that needs an approver").
     * @param c what the release contains
     * @return the words
     */
    public static String onlyText(RlyApprovalRules.Contents c) {
        List<String> sorted = new List<String>(c.metadataTypes);
        sorted.sort();
        List<String> words = new List<String>();
        for (String t : sorted) {
            String word = PLURALS.containsKey(t) ? PLURALS.get(t) : t;
            if (!words.contains(word)) {
                words.add(word);
            }
        }
        if (c.deletes) {
            words.add('deletions');
        }
        return words.isEmpty() ? 'nothing that needs an approver' : 'only ' + joined(words);
    }

    /**
     * @description "a", "a and b", "a, b and c".
     * @param parts the parts
     * @return the words
     */
    public static String joined(List<String> parts) {
        if (parts.size() <= 1) {
            return parts.isEmpty() ? '' : parts[0];
        }
        List<String> head = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            head.add(parts[i]);
        }
        return String.join(head, ', ') + ' and ' + parts[parts.size() - 1];
    }

    /**
     * @description The org card's read-only line, for example "Only when the release contains: Flows, Deletions".
     * @param org the org
     * @return the line
     */
    public static String ruleText(RLY_Org__c org) {
        String rule = RlyApprovalRules.ruleOf(org);
        if (rule != RlyApprovalRules.RULE_SELECTED) {
            return RlyApprovalRules.RULE_LABELS.get(rule);
        }
        List<String> labels = new List<String>();
        Set<String> chosen = RlyApprovalRules.typesOf(org);
        for (String t : RlyApprovalRules.TYPES) {
            if (chosen.contains(t)) {
                labels.add(RlyApprovalRules.TYPE_LABELS.get(t));
            }
        }
        return 'Only when the release contains: ' + String.join(labels, ', ');
    }
}
