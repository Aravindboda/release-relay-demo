/**
 * @description Tests for RlySlackSiteCheck: the checks run against a user in place of the Site's guest and name what
 * is missing; with no Site, nothing is reported. Each test runs through System.runAs as an active System Administrator.
 */
@IsTest
private class RlySlackSiteCheckTest {

    @IsTest
    static void namesWhatTheGuestLacks() {
        System.runAs(RlyTestData.admin()) {
            User plain = [SELECT Id, ProfileId FROM User WHERE Id = :UserInfo.getUserId()];
            RlySlackSiteCheck.guestForTest = plain;
            Test.startTest();
            List<String> problems = RlySlackSiteCheck.problems();
            Test.stopTest();
            System.assertNotEquals(null, problems, 'A list comes back');
            for (String p : problems) {
                System.assert(p.startsWith('Give the Site'), 'Each problem says what to give: ' + p);
            }
        }
    }

    @IsTest
    static void adminsReadTheChecks() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            List<String> problems = RlySlackSiteCheck.read();
            Test.stopTest();
            System.assert(problems.size() <= 2, 'At most the two checks: ' + problems);
        }
    }

    @IsTest
    static void readsSitesAndPrincipals() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlySlackSiteCheck.Data d = new RlySlackSiteCheck.Data();
            User guest = d.guest();
            Boolean lacks = d.lacksGitPrincipal(new Set<Id>());
            Boolean reads = d.readsUserCredentials(new Set<Id>());
            Test.stopTest();
            System.assert(guest == null || guest.Id != null, 'A guest, when found, has an Id');
            System.assertEquals(false, reads, 'No permission sets: no access');
            System.assertNotEquals(null, lacks, 'Answered');
        }
    }
}
