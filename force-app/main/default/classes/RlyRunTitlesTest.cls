/**
 * @description Tests for build 44: RlyRunTitles (a run's name matches the hub's title exactly or with the parts pipeline
 * version 25 adds), RlyGitHub.findRun using it, and the people options (by, approvedBy, hubUrl) from RlyRunPeople.
 * Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyRunTitlesTest {

    private static final String TITLE = 'Release Relay REL-7 (hub)';

    private static RLY_Git_Connection__c connection() {
        return new RLY_Git_Connection__c(Provider__c = 'GitHub', Named_Credential__c = 'RLY_GitHub',
            Repository__c = 'acme/release', Pipeline__c = 'release-relay.yml');
    }

    private static String runJson(Integer runId, String name) {
        return '{"id":' + runId + ',"html_url":"https://github.com/acme/release/actions/runs/' + runId
            + '","display_title":"' + name + '","status":"completed","conclusion":"success"}';
    }

    @IsTest
    static void matchesExactOrWithAddedParts() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyRunTitles.matches(TITLE, TITLE), 'Exact name');
            System.assert(RlyRunTitles.matches(TITLE + ' · REL-7: Fix login', TITLE), 'With the title');
            System.assert(RlyRunTitles.matches(TITLE + ' · REL-7: Fix login · by Ann Lee', TITLE), 'With title and raiser');
            System.assert(!RlyRunTitles.matches('Release Relay REL-70 (hub)', TITLE), 'Another request');
            System.assert(!RlyRunTitles.matches(TITLE + 'x', TITLE), 'No separator');
            System.assert(!RlyRunTitles.matches('Release Relay REL-7 (merge) · REL-7: Fix', TITLE), 'Another mode');
            System.assert(!RlyRunTitles.matches(null, TITLE), 'No name');
            System.assert(!RlyRunTitles.matches(TITLE, ' '), 'No title');
        }
    }

    @IsTest
    static void findRunTakesTheNewestMatch() {
        System.runAs(RlyTestData.admin()) {
            RlyGit git = RlyGit.forConnection(connection());
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', '/runs?').reply(200, '{"workflow_runs":['
                + runJson(9, 'Release Relay REL-70 (hub) · REL-70: Other') + ',' + runJson(8, TITLE + ' · REL-7: Fix · by Ann Lee')
                + ',' + runJson(5, TITLE) + ']}'));
            Test.startTest();
            RlyGit.Run run = git.findRun(TITLE);
            RlyGit.Run none = git.findRun('Release Relay REL-8 (hub)');
            Test.stopTest();
            System.assertNotEquals(null, run, 'Found by its v25 name');
            System.assert(run.url.endsWith('/runs/8'), 'Newest matching run: ' + run.url);
            System.assertEquals(null, none, 'No run for another request');
        }
    }

    @IsTest
    static void optionsNameThePeopleAndThePage() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            update new RLY_Release__c(Id = rel.Id, Approved_By__c = UserInfo.getUserId());
            Map<String, Object> options = RlyPipelineOptions.forMode(RlyReleaseStore.release(rel.Id), 'check');
            System.assertEquals(UserInfo.getName(), options.get('by'), 'Raised by');
            System.assertEquals(UserInfo.getName(), options.get('approvedBy'), 'Approved by');
            String hubUrl = (String) options.get('hubUrl');
            System.assert(hubUrl.startsWith(URL.getOrgDomainUrl().toExternalForm()), 'Hub link: ' + hubUrl);
            System.assert(hubUrl.endsWith('/lightning/r/RLY_Release__c/' + rel.Id + '/view'), 'Release page: ' + hubUrl);
            System.assert(JSON.serialize(options).length() < 60000, 'Fits the input');
        }
    }

    @IsTest
    static void optionsLeaveOutWhatWasNotRead() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> options = new Map<String, Object>();
            RlyRunPeople.addTo(new RLY_Release__c(), options);
            System.assert(options.isEmpty(), 'Nothing read, nothing added: ' + options);
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            RLY_Release__c bare = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
            RlyRunPeople.addTo(bare, options);
            System.assert(!options.containsKey('by'), 'Raiser not read');
            System.assert(!options.containsKey('approvedBy'), 'Not approved');
            System.assert(options.containsKey('hubUrl'), 'Saved release: a link');
        }
    }
}
