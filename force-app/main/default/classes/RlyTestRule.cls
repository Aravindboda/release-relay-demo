/**
 * @description The test rule of a release: Apex needs at least one test class (no bypass), and every selected
 * test class must be in the release, so the deploys can run it (RunSpecifiedTests).
 */
public with sharing class RlyTestRule {

    private static final Set<String> APEX_TYPES = new Set<String>{ 'ApexClass', 'ApexTrigger' };

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

    private static Boolean hasApex(List<RlyRaiseService.Item> items, Set<String> tests) {
        for (RlyRaiseService.Item i : items) {
            if (APEX_TYPES.contains(i.type) && !tests.contains(i.name)) {
                return true;
            }
        }
        return false;
    }
}
