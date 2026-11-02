/**
 * @description The test rule of a release: Apex needs at least one test class (no bypass), and every selected
 * test class must be in the release, so the deploys can run it (RunSpecifiedTests). Deleting Apex needs no test class,
 * and neither do triggers that deploy switched off (Item.inactive: Status Inactive in the developer org, kept in
 * RLY_Release__c.Inactive_Triggers__c); production runs the local tests then (RlyPipelineOptions, the pipeline).
 */
public with sharing class RlyTestRule {

    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };
    private static final Integer FIELD_LENGTH = 255;

    /**
     * @description The selected test class names, trimmed, without blanks.
     * @param testClasses the names the page sent (may be null)
     * @return the names
     */
    public static Set<String> testNames(List<String> testClasses) {
        Set<String> tests = new Set<String>();
        for (String t : testClasses == null ? new List<String>() : testClasses) {
            if (String.isNotBlank(t)) {
                tests.add(t.trim());
            }
        }
        return tests;
    }

    /**
     * @description Enforces the test rule: Apex needs at least one test class, no bypass; and every
     * selected test class must be in the release.
     * @param items the selected components
     * @param byType component names by metadata type
     * @param tests the selected test class names
     */
    public static void checkTests(List<RlyRaiseService.Item> items, Map<String, Set<String>> byType, Set<String> tests) {
        if (hasApex(items, tests) && tests.isEmpty()) {
            throw new RlyReleaseException('This release has Apex but no test class. Select the test class that covers it.');
        }
        Set<String> classes = byType.containsKey('ApexClass') ? byType.get('ApexClass') : new Set<String>();
        for (String t : tests) {
            if (!classes.contains(t)) {
                throw new RlyReleaseException('Test class ' + t + ' must be in the release too.');
            }
        }
    }

    // Apex that runs: classes that aren't selected tests, and triggers that aren't switched off.
    private static Boolean hasApex(List<RlyRaiseService.Item> items, Set<String> tests) {
        for (RlyRaiseService.Item i : items) {
            if (APEX_TYPES.contains(i.type) && !tests.contains(i.name) && !isInactiveTrigger(i)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isInactiveTrigger(RlyRaiseService.Item i) {
        return i.type == 'ApexTrigger' && i.inactive == true;
    }

    /**
     * @description The value for Inactive_Triggers__c: the names already there, then the selected triggers flagged
     * inactive, each once, comma separated (cut to the field's 255 characters at a name).
     * @param items the selected components
     * @param existing the field's value so far (null for a new release)
     * @return the value, or null when there are none
     */
    public static String inactiveField(List<RlyRaiseService.Item> items, String existing) {
        List<String> names = splitNames(existing);
        for (RlyRaiseService.Item i : items == null ? new List<RlyRaiseService.Item>() : items) {
            if (i != null && isInactiveTrigger(i) && String.isNotBlank(i.name) && !names.contains(i.name.trim())) {
                names.add(i.name.trim());
            }
        }
        return joinWithin(names);
    }

    // The names comma separated, as many as fit in the field (cut at a name), or null when there are none.
    private static String joinWithin(List<String> names) {
        String out = '';
        for (String n : names) {
            String next = out == '' ? n : out + ',' + n;
            if (next.length() > FIELD_LENGTH) {
                break;
            }
            out = next;
        }
        return out == '' ? null : out;
    }

    /**
     * @description The triggers a release deploys switched off, read through the populated fields (a release read
     * without Inactive_Triggers__c has none).
     * @param rel the release
     * @return the names (empty when there are none)
     */
    public static List<String> inactiveTriggers(RLY_Release__c rel) {
        Object raw = rel == null ? null : rel.getPopulatedFieldsAsMap().get('Inactive_Triggers__c');
        return splitNames(raw == null ? null : String.valueOf(raw));
    }

    private static List<String> splitNames(String value) {
        List<String> out = new List<String>();
        for (String n : String.isBlank(value) ? new List<String>() : value.split(',')) {
            if (String.isNotBlank(n) && !out.contains(n.trim())) {
                out.add(n.trim());
            }
        }
        return out;
    }
}
