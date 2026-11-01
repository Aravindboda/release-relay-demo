/**
 * @description Tests for Open org (RlyOrgLinks): the orgs on a release's route with their login addresses, the hub left
 * out, back promote orgs only when back promote is on, and nothing for users who are neither admins nor on the
 * deployment team. Every test runs via System.runAs.
 */
@IsTest
private class RlyOrgLinksTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static List<String> namesOf(List<RlyOrgLinks.OrgLink> links) {
        List<String> out = new List<String>();
        for (RlyOrgLinks.OrgLink l : links) {
            out.add(l.name);
        }
        return out;
    }

    @IsTest
    static void routeOrgsWithoutProduction() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', null);
            RLY_Org__c backOrg = RlyTestData.org('TRAINING', RlyBackPromote.ROLE, 'training');
            backOrg.My_Domain__c = 'https://training.my.salesforce.com/';
            insert backOrg;
            List<RlyOrgLinks.OrgLink> links = RlyReleasesController.getRelease(rel.Id).orgLinks;
            System.assertEquals(new List<String>{ 'DEV1', 'SIT' }, namesOf(links), 'Source then stages, no hub, back promote off');
            System.assertEquals('https://dev1.my.salesforce.com/', links[0].loginUrl, 'My Domain followed by /');
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            update new RLY_Git_Connection__c(Id = conn.Id, Back_Promote__c = true);
            links = RlyOrgLinks.forRelease(RlyReleaseStore.release(rel.Id));
            System.assertEquals(new List<String>{ 'DEV1', 'SIT', 'TRAINING' }, namesOf(links), 'Back promote orgs when on');
            System.assertEquals('https://training.my.salesforce.com/', links[2].loginUrl, 'One slash');
        }
    }

    @IsTest
    static void addressesAndRefusals() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals(null, RlyOrgLinks.loginUrlOf(null), 'No My Domain');
            System.assertEquals(null, RlyOrgLinks.loginUrlOf('http://plain.example.com'), 'Only https');
            System.assertEquals(null, RlyOrgLinks.loginUrlOf('https://'), 'No host');
            System.assertEquals('https://a.my.salesforce.com/', RlyOrgLinks.loginUrlOf(' https://a.my.salesforce.com/ '), 'Trimmed');
            System.assertEquals(0, RlyOrgLinks.forRelease(null).size(), 'No release');
        }
    }

    @IsTest
    static void nothingForOtherUsers() {
        User plain = RlyTestData.plainUser();
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = RlyReleaseTestData.release('Ready for approval', null);
        }
        System.runAs(plain) {
            System.assertEquals(0, RlyOrgLinks.forRelease(RlyReleaseStore.release(rel.Id)).size(), 'Only admins and the deployment team');
        }
    }
}
