/**
 * @description Saves an org's approval rule from the Pipeline tab's org Edit modal (RlyOrgController.saveOrg):
 * Approval_Rule__c (Always, Selected_Types or Never) and Approval_Types__c (the kinds of change that need an approver).
 * Only keys present in the JSON count (a deserialized record can't tell a missing field from a default). The hub org
 * (role Hub, production) can't be Never; Selected_Types needs at least one type. A new org without a rule gets Always.
 */
public with sharing class RlyApprovalRuleOrg {

    /** @description Refused for the hub org. */
    public static final String HUB_NEVER = 'Production always needs approval: pick Always or Only when…';
    /** @description Refused for Selected_Types without a type. */
    public static final String NO_TYPES = 'Pick at least one kind of change that needs approval';

    private static final String RULE_KEY = 'Approval_Rule__c';
    private static final String TYPES_KEY = 'Approval_Types__c';

    /**
     * @description Copies the rule and types the page sent onto the row to save, and checks them against the row's role.
     * @param row the row to save, with Id and Role__c
     * @param orgJson the JSON the page sent
     * @param saved the org as saved, or null for a new org
     */
    public static void apply(RLY_Org__c row, String orgJson, RLY_Org__c saved) {
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(orgJson);
        String rule = sent.containsKey(RULE_KEY) ? textOf(sent.get(RULE_KEY)) : RlyApprovalRules.ruleOf(saved);
        Set<String> types = sent.containsKey(TYPES_KEY) ? typesOf(sent.get(TYPES_KEY)) : RlyApprovalRules.typesOf(saved);
        rule = String.isBlank(rule) ? RlyApprovalRules.RULE_ALWAYS : rule;
        check(row, rule, types);
        row.Approval_Rule__c = rule;
        row.Approval_Types__c = rule == RlyApprovalRules.RULE_SELECTED ? ordered(types) : null;
    }

    private static void check(RLY_Org__c row, String rule, Set<String> types) {
        if (!RlyApprovalRules.RULE_LABELS.containsKey(rule)) {
            throw refused('Pick an approval rule: Always, Only when the release contains…, or Never.');
        }
        if (rule == RlyApprovalRules.RULE_NEVER && row.Role__c == 'Hub') {
            throw refused(HUB_NEVER + '.');
        }
        if (rule == RlyApprovalRules.RULE_SELECTED && types.isEmpty()) {
            throw refused(NO_TYPES + '.');
        }
        checkTypes(types);
    }

    private static void checkTypes(Set<String> types) {
        for (String t : types) {
            if (!RlyApprovalRules.TYPE_LABELS.containsKey(t)) {
                throw refused('Unknown kind of change: ' + t + '.');
            }
        }
    }

    private static AuraHandledException refused(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /**
     * @description Fills the Pipeline tab's approval rule choices and each org's rule in words.
     * @param p the Pipeline tab's payload, with orgs read
     */
    public static void fill(RlyOrgController.PipelineOrgs p) {
        for (String rule : RlyApprovalRules.RULES) {
            p.approvalRuleOptions.add(new RlyOrgController.ApprovalOption(rule, RlyApprovalRules.RULE_LABELS.get(rule)));
        }
        for (String t : RlyApprovalRules.TYPES) {
            p.approvalTypeOptions.add(new RlyOrgController.ApprovalOption(t, RlyApprovalRules.TYPE_LABELS.get(t)));
        }
        for (RLY_Org__c o : p.orgs) {
            p.approvalRules.put(o.Id, RlyApprovalWords.ruleText(o));
        }
    }

    // A list (checkbox group value) or a string separated by ; or ,.
    private static Set<String> typesOf(Object value) {
        Set<String> out = new Set<String>();
        List<Object> parts = value instanceof List<Object> ? (List<Object>) value : new List<Object>();
        if (value instanceof String) {
            for (String piece : String.valueOf(value).replace(',', ';').split(';')) {
                parts.add(piece);
            }
        }
        for (Object p : parts) {
            String t = textOf(p);
            if (String.isNotBlank(t)) {
                out.add(t.trim());
            }
        }
        return out;
    }

    private static String textOf(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    // In the page's order, joined with ; (multi-select picklist).
    private static String ordered(Set<String> types) {
        List<String> out = new List<String>();
        for (String t : RlyApprovalRules.TYPES) {
            if (types.contains(t)) {
                out.add(t);
            }
        }
        return String.join(out, ';');
    }
}
