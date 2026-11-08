/**
 * @description End-to-end test probe: a small class the release tests move along the route.
 */
public with sharing class E2EProbe {
    /**
     * @description Returns a fixed label so the test can assert the deployed version.
     * @return the probe label
     */
    public static String label() {
        return 'E2E probe v1';
    }
}
