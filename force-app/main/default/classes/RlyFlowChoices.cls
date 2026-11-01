/**
 * @description What happens to each flow of a release after its deploy (RLY_Release__c.Flow_Actions__c, JSON
 * [{name, choice}]): Keep (the default: as in the developer org), Activate (the hub activates the deployed version in
 * each org, RlyFlowActivation) or Inactive (left inactive, with a manual step "Activate flow <name>" in every org). A
 * promotion carries the union of its releases' choices: Activate wins over Keep; Inactive steps travel with the
 * releases that defined them (manual steps, RlyRaiseService).
 */
public with sharing class RlyFlowChoices {

    /** @description Keep as in the developer org (the default). */
    public static final String CHOICE_KEEP = 'Keep';
    /** @description Activate in each org after the deploy. */
    public static final String CHOICE_ACTIVATE = 'Activate';
    /** @description Leave inactive: a manual step to activate it. */
    public static final String CHOICE_INACTIVE = 'Inactive';
    /** @description The most flows a release can carry choices for. */
    public static final Integer MAX_FLOWS = 40;

    private static final Set<String> VALID_CHOICES = new Set<String>{ CHOICE_KEEP, CHOICE_ACTIVATE, CHOICE_INACTIVE };
    private static final Pattern FLOW_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');

    /** @description One flow's choice, as the Review step sends it and Flow_Actions__c keeps it. */
    public class FlowChoice {
        /** @description The flow's API name. */
        @AuraEnabled public String name;
        /** @description Keep, Activate or Inactive. */
        @AuraEnabled public String choice;
    }

    /**
     * @description Checks the choices sent with a new release: known flows among its items, known choices, each flow once.
     * A flow without a choice keeps the default (Keep) and isn't listed.
     * @param sent the choices, or null
     * @param flowNames the release's Flow components
     * @return the checked choices, in the order sent
     */
    public static List<FlowChoice> checked(List<FlowChoice> sent, Set<String> flowNames) {
        List<FlowChoice> out = new List<FlowChoice>();
        Set<String> seen = new Set<String>();
        for (FlowChoice c : sent == null ? new List<FlowChoice>() : sent) {
            FlowChoice one = checkedOne(c, flowNames);
            if (!seen.add(one.name.toLowerCase())) {
                throw new RlyReleaseException('The flow ' + one.name + ' has two choices.');
            }
            out.add(one);
        }
        if (out.size() > MAX_FLOWS) {
            throw new RlyReleaseException('A release can carry choices for up to ' + MAX_FLOWS + ' flows.');
        }
        return out;
    }

    // One choice: a selected flow and a known choice (blank is Keep).
    private static FlowChoice checkedOne(FlowChoice c, Set<String> flowNames) {
        String choice = c == null || String.isBlank(c.choice) ? CHOICE_KEEP : c.choice.trim();
        String name = c == null || c.name == null ? '' : c.name.trim();
        if (!VALID_CHOICES.contains(choice)) {
            throw new RlyReleaseException('Pick Keep, Activate or Leave inactive for each flow.');
        }
        if (!flowNames.contains(name)) {
            throw new RlyReleaseException('The flow choice for ' + name + ' doesn\'t match a selected flow.');
        }
        return choiceOf(name, choice);
    }

    /**
     * @description A choice.
     * @param name the flow's API name
     * @param choice Keep, Activate or Inactive
     * @return the choice
     */
    public static FlowChoice choiceOf(String name, String choice) {
        FlowChoice c = new FlowChoice();
        c.name = name;
        c.choice = choice;
        return c;
    }

    /**
     * @description Whether a name can be a flow's API name (letters, digits and underscores, starting with a letter).
     * @param name the name
     * @return true when it can
     */
    public static Boolean isFlowName(String name) {
        return name != null && FLOW_NAME.matcher(name).matches();
    }

    /**
     * @description The value to store in Flow_Actions__c.
     * @param choices the choices
     * @return the JSON, or null when there are none
     */
    public static String toField(List<FlowChoice> choices) {
        return choices == null || choices.isEmpty() ? null : JSON.serialize(choices).left(32768);
    }

    /**
     * @description A release's choices.
     * @param rel the release, with Flow_Actions__c
     * @return the choices (empty when there are none or they can't be read)
     */
    public static List<FlowChoice> fromRelease(RLY_Release__c rel) {
        List<FlowChoice> out = new List<FlowChoice>();
        if (rel == null || String.isBlank(rel.Flow_Actions__c)) {
            return out;
        }
        try {
            for (Object o : (List<Object>) JSON.deserializeUntyped(rel.Flow_Actions__c)) {
                Map<String, Object> m = o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
                String name = RlyEvidenceText.str(m.get('name'));
                String choice = RlyEvidenceText.str(m.get('choice'));
                if (name != null && VALID_CHOICES.contains(choice)) {
                    out.add(choiceOf(name, choice));
                }
            }
        } catch (Exception e) {
            return new List<FlowChoice>();
        }
        return out;
    }

    /**
     * @description The flows to activate after a release's deploy.
     * @param rel the release, with Flow_Actions__c
     * @return the flow names
     */
    public static List<String> toActivate(RLY_Release__c rel) {
        List<String> out = new List<String>();
        for (FlowChoice c : fromRelease(rel)) {
            if (c.choice == CHOICE_ACTIVATE) {
                out.add(c.name);
            }
        }
        return out;
    }

    /**
     * @description The union of several releases' choices (a promotion's, a back promote sync's): each flow once,
     * Activate over Keep, Inactive over Keep.
     * @param rels the releases, with Flow_Actions__c, in deploy order
     * @return the choices
     */
    public static List<FlowChoice> union(List<RLY_Release__c> rels) {
        Map<String, FlowChoice> byName = new Map<String, FlowChoice>();
        for (RLY_Release__c r : rels) {
            for (FlowChoice c : fromRelease(r)) {
                String key = c.name.toLowerCase();
                FlowChoice had = byName.get(key);
                if (had == null || had.choice == CHOICE_KEEP || c.choice == CHOICE_ACTIVATE) {
                    byName.put(key, c);
                }
            }
        }
        return byName.values();
    }
}
