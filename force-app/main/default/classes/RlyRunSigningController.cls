/**
 * @description Pipeline tab, Run signing card (build 48): whether the hub has a run-signing key, who set it and when;
 * admins generate a new key (shown once, to copy into the repository as RELAY_RUN_KEY) and save it. The key is
 * never returned after it is saved. Also the Repository security card's check (RlyRepoSecurity).
 */
public with sharing class RlyRunSigningController {

    private static final String ADMINS_ONLY = 'Only Release Relay admins can do this.';

    /** @description What the Run signing card shows. Never the saved key. */
    public class Status {
        /** @description A key is saved: runs are signed and results must be signed. */
        @AuraEnabled public Boolean keySet = false;
        /** @description When it was saved. */
        @AuraEnabled public Datetime setOn;
        /** @description Who saved it. */
        @AuraEnabled public String setBy;
        /** @description The current user may change it (a Release Relay admin). */
        @AuraEnabled public Boolean canEdit = false;
        /** @description The Git provider of the active connection (GitHub, GitLab…), or null. */
        @AuraEnabled public String provider;
        /** @description The org environments the key goes into (GitHub environment secrets). */
        @AuraEnabled public List<String> environments = new List<String>();
    }

    /**
     * @description The card as this user sees it.
     * @return the status
     */
    @AuraEnabled
    public static Status status() {
        try {
            return statusNow();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Run signing: ');
        }
    }

    /**
     * @description Admins: a new random key (Base64 of 32 bytes), not saved yet. The page shows it once so the admin
     * can copy it into GitHub or GitLab, then saves it with saveKey.
     * @return the new key
     */
    @AuraEnabled
    public static String generateKey() {
        try {
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            return RlyRunSigning.newKey();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Run signing: ');
        }
    }

    /**
     * @description Admins: saves the key (first time, or replacing the one saved). From then on every run is signed with
     * it and only results signed with it are trusted. It is never shown again.
     * @param key the key the admin copied into the repository
     * @return the status
     */
    @AuraEnabled
    public static Status saveKey(String key) {
        try {
            RlyHubGuard.requireHub();
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            if (!RlyRunSigning.isKey(key)) {
                throw new RlyReleaseException('That isn\'t a run-signing key: press Generate and copy the key it shows.');
            }
            RlySettingsLog.Snapshot was = RlySettingsLog.read(RlySettingsLog.SECURITY); // build 50: Recent changes to settings
            RlyRunKeyStore.save(key.trim());
            RlySettingsLog.compare(was);
            return statusNow();
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Run signing: ');
        }
    }

    /**
     * @description The Repository security card: what the active Git connection's repository protects and what is
     * missing, with how to fix each. Read-only; a read that fails is shown on its row.
     * @return the report
     */
    @AuraEnabled
    public static RlyRepoSecurity.Report checkRepository() {
        try {
            RlyReleaseAccess.requireAdmin(ADMINS_ONLY);
            RlyRepoSecurity.Report report = RlyRepoSecurity.check();
            RlyPipelineSummaryStore.keepSecurity(report); // build 50: the status strip reads it without a callout
            return report;
        } catch (Exception e) {
            throw RlyReleaseException.toAura(e, 'Run signing: ');
        }
    }

    private static Status statusNow() {
        RLY_Run_Key__c r = RlyRunKeyStore.row();
        Status s = new Status();
        s.keySet = String.isNotBlank(r.Key__c);
        s.setOn = s.keySet ? r.Set_On__c : null;
        s.setBy = s.keySet ? r.Set_By__c : null;
        s.canEdit = RlyOrgController.isAdmin();
        RLY_Git_Connection__c conn = RlyReleaseStore.git();
        s.provider = conn == null ? null : conn.Provider__c;
        s.environments = RlyRepoSecurity.orgEnvironments();
        return s;
    }
}
