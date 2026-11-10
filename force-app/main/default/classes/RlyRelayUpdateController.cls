/**
 * @description Pipeline tab, Advanced: the Install Release Relay update card (admins only). An admin names the update
 * branch (with the build's zip in .relay-inbox/), a title and the stage to test in, then runs four steps in order:
 * the test org's check and install, then production's check and install. Each run is started by the hub through the
 * signed path (RlyGit.startPipeline), each start is logged in Recent changes to settings, and each result is read
 * from the signed result files (RlyRelayUpdateResults). Everyone else gets a card that isn't shown.
 * Every call that saves makes its callouts first.
 */
public with sharing class RlyRelayUpdateController {

    private static final String ADMINS_ONLY = 'Only Release Relay admins can install Release Relay updates.';
    private static final String PREFIX = 'Install update: ';

    /**
     * @description The card as the current user sees it.
     * @return the card (visible only for admins)
     */
    @AuraEnabled
    public static RlyRelayUpdateView.Card state() {
        try {
            return RlyRelayUpdateView.build();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, PREFIX);
        }
    }

    /**
     * @description Admins: a new update from the form: its zip found on the update branch, its tests and components read.
     * @param form branch, title, testOrgId and testsFrom (zip; org reads the tests from this org's classes)
     * @return the card
     */
    @AuraEnabled
    public static RlyRelayUpdateView.Card prepare(Map<String, String> form) {
        try {
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            RlyRelayUpdateStore.save(RlyRelayUpdatePrepare.prepare(form));
            return RlyRelayUpdateView.build();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, PREFIX);
        }
    }

    /**
     * @description Admins: starts a step of the current update, signed, and logs the start.
     * @param stepKey test-check, test-install, prod-check or prod-install
     * @return the card
     */
    @AuraEnabled
    public static RlyRelayUpdateView.Card start(String stepKey) {
        try {
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            RLY_Relay_Update__c u = RlyRelayUpdateStore.current();
            RlyRelayUpdateState.Step s = RlyRelayUpdateRuns.start(u, stepKey);
            RlyRelayUpdateStore.save(u);
            RlyRelayUpdateStore.logStart('Install update · ' + stepLabel(u, stepKey), s.requestId + ' · ' + s.branch + ' → ' + s.target);
            return RlyRelayUpdateView.build();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, PREFIX);
        }
    }

    /**
     * @description Admins: reads the running step's result and saves it.
     * @return the card
     */
    @AuraEnabled
    public static RlyRelayUpdateView.Card refresh() {
        try {
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            RLY_Relay_Update__c u = RlyRelayUpdateStore.current();
            if (u != null && RlyRelayUpdateResults.refresh(u) != null) {
                RlyRelayUpdateStore.save(u);
            }
            return RlyRelayUpdateView.build();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, PREFIX);
        }
    }

    // The step's name as the card shows it (the test org's or production's name).
    private static String stepLabel(RLY_Relay_Update__c u, String stepKey) {
        Boolean inTestOrg = stepKey == RlyRelayUpdateState.TEST_CHECK || stepKey == RlyRelayUpdateState.TEST_INSTALL;
        String org = inTestOrg ? RlyRelayUpdateView.testOrgName(u) : RlyRelayUpdateRuns.hub().Name;
        return org + (RlyRelayUpdateState.isCheck(stepKey) ? ' check' : ' install');
    }
}
