/**
 * @description Build 55: the nightly read of every registered org's installed packages, in the pipeline's nightly
 * archive call (RlyArchiveNightly), next to the Credentials refresh. The night's first call reads (callouts only, one
 * query per org after its sign-in, which the Credentials check has usually just made) before the archive pass touches
 * anything; saveAfter saves the read and adds "packages" to the answer. Only in the production hub and for the
 * pipeline's admin user. Never throws: a failed read never stops the archive.
 */
public with sharing class RlyOrgPackageNightly {

    /**
     * @description Reads the packages (callouts only) on the night's first call.
     * @param body the call's body ({"runUrl", "runId"})
     * @return the read, or null when this call doesn't read
     */
    public static RlySyncPackages.Packages readFirst(String body) {
        try {
            if (!RlyCredentialNightly.isFirstCall(body) || !RlyArchiveService.onHub() || !RlyOrgController.isAdmin()) {
                return null;
            }
            List<RLY_Org__c> orgs = RlyOrgPackageStore.orgs();
            return orgs.isEmpty() ? null : RlySyncPackages.gather(RlySyncRoute.topDown(orgs));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Saves the read and says what it found in the answer.
     * @param p the read, or null
     * @param answer the archive call's answer
     */
    public static void saveAfter(RlySyncPackages.Packages p, Map<String, Object> answer) {
        if (p == null || answer == null) {
            return;
        }
        if (!p.orgs.isEmpty() && p.errors.size() == p.orgs.size()) {
            answer.put('packages', 'Not read: ' + p.errors.values()[0]); // nothing read: the last good read stays
            return;
        }
        try {
            RlySyncPackages.saveRead(p, RlyOrgPackageStore.orgs());
            answer.put('packages', summary(p));
        } catch (Exception e) {
            answer.put('packages', 'Not saved: ' + e.getMessage());
        }
    }

    /**
     * @description A short summary of a read (packages with a namespace).
     * @param p the read
     * @return for example "3 packages in 4 orgs, 1 org not read"
     */
    public static String summary(RlySyncPackages.Packages p) {
        Integer read = p.orgs.size() - p.errors.size();
        Integer managed = 0;
        for (RlySyncPackages.PackageRow row : p.packages) {
            managed += RlyOrgPackages.isNamespace(row.namespace) ? 1 : 0;
        }
        String text = managed + (managed == 1 ? ' package' : ' packages') + ' in ' + read
            + (read == 1 ? ' org' : ' orgs');
        if (!p.errors.isEmpty()) {
            text += ', ' + p.errors.size() + (p.errors.size() == 1 ? ' org' : ' orgs') + ' not read';
        }
        return text;
    }
}
