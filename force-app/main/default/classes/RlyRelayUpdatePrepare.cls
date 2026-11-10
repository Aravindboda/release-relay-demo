/**
 * @description Install Release Relay update: a new update from the card's form. The update branch's one zip in
 * .relay-inbox/ (its Git object is kept, so every check copies that same file even if the branch changes later), its
 * tests (each *Test class in the zip; when the zip can't be read here, this org's Release Relay test classes) and its
 * package.xml members. Callouts only: the caller saves the update.
 */
public with sharing class RlyRelayUpdatePrepare {

    /** @description Read the tests from the zip. */
    public static final String FROM_ZIP = 'zip';
    /** @description Read the tests from the org's own classes. */
    public static final String FROM_ORG = 'org';
    private static final Pattern BRANCH_PATTERN = Pattern.compile('[A-Za-z0-9._/-]{1,100}');
    private static final Integer MAX_TITLE = 150;

    /**
     * @description A new update from the card's form, ready to save.
     * @param form branch, title, testOrgId and testsFrom (zip, or org when the zip couldn't be read last time)
     * @return the update, not saved
     */
    public static RLY_Relay_Update__c prepare(Map<String, String> form) {
        Map<String, String> f = form == null ? new Map<String, String>() : form;
        String branch = checkedBranch(f.get('branch'));
        String title = checkedTitle(f.get('title'));
        RLY_Org__c org = RlyRelayUpdateRuns.stage(f.get('testOrgId'));
        RlyRelayUpdateRuns.environmentOf(org);
        if (RlyRelayUpdateState.running(RlyRelayUpdateState.read(RlyRelayUpdateStore.current())) != null) {
            throw new RlyReleaseException('A step of the current update is still running. Wait for its result first.');
        }
        RlyRelayUpdateGit g = new RlyRelayUpdateGit(RlyRelayUpdateRuns.git());
        RlyRelayUpdateGit.ZipFile z = g.findZip(branch);
        RLY_Relay_Update__c u = new RLY_Relay_Update__c(Branch__c = branch, Title__c = title, Test_Org__c = org.Id, Zip_Path__c = z.path,
            Zip_Sha__c = z.sha, Zip_Commit__c = z.commitSha, Steps__c = '{}');
        addTests(u, f.get('testsFrom') == FROM_ORG ? null : contentsOf(g, z));
        return u;
    }

    // The zip's tests and components; the org's Release Relay test classes when the zip couldn't be read or has none.
    private static void addTests(RLY_Relay_Update__c u, RlyRelayUpdateZip.Contents c) {
        Boolean fromZip = c != null && !c.tests.isEmpty();
        List<String> tests = fromZip ? c.tests : RlyRelayUpdateStore.orgTestClasses();
        if (tests.isEmpty()) {
            throw new RlyReleaseException('No test classes found in the zip or in this org, so the update can\'t be checked.');
        }
        u.Tests__c = String.join(tests, ',');
        u.Tests_From__c = fromZip ? FROM_ZIP : FROM_ORG;
        u.Components__c = c == null ? '' : RlyRelayUpdateZip.joined(c.components, RlyRelayUpdateZip.MAX_COMPONENT_CHARS);
    }

    private static String checkedBranch(String value) {
        String branch = String.isBlank(value) ? '' : value.trim();
        if (!BRANCH_PATTERN.matcher(branch).matches() || branch.contains('..')) {
            throw new RlyReleaseException('Enter the update branch: letters, digits and . _ / - only.');
        }
        return branch;
    }

    private static String checkedTitle(String value) {
        String title = String.isBlank(value) ? '' : value.trim();
        if (String.isBlank(title) || title.length() > MAX_TITLE) {
            throw new RlyReleaseException('Enter a title (up to ' + MAX_TITLE + ' characters).');
        }
        return title;
    }

    // The zip's tests and components, or null when it can't be read here (too big for the heap, or not a zip).
    private static RlyRelayUpdateZip.Contents contentsOf(RlyRelayUpdateGit g, RlyRelayUpdateGit.ZipFile z) {
        try {
            Blob zip = g.download(z);
            return zip == null ? null : RlyRelayUpdateZip.read(zip);
        } catch (Exception e) {
            return null;
        }
    }
}
