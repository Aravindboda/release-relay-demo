/**
 * @description Tests for hotfixes (RlyHotfix, RlyRaiseRoute, RlyReleaseStart, the hotfix parts of RlyRaiseService,
 * RlyChangesController, RlyStatusReader, RlyPipelineRun and RlyPipelineOptions): a hotfix is raised from a developer org
 * with a reason; raising from a stage org is retired. Each test runs through System.runAs: as an active System
 * Administrator with Release Relay Admin (which grants RLY_Hotfix), or as a new user without it.
 * Records are inserted before Test.startTest; callouts come after it.
 */
@IsTest
private class RlyHotfixTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // DEV1 -> SIT -> UAT -> hub with a checked GitHub connection.
    private static void routeWithUat() {
        RlyReleaseTestData.route();
        RLY_Org__c uat = RlyTestData.stage('UAT', 'uat', 2);
        uat.Environment__c = 'Full_Copy';
        insert uat;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RlyRaiseService.RaiseRequest request(Id sourceOrgId) {
        RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
        req.sourceOrgId = sourceOrgId;
        req.title = 'Fix the discount';
        req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
        req.testClasses = new List<String>();
        return req;
    }

    private static String refusal(RlyRaiseService.RaiseRequest req) {
        try {
            RlyRaiseService.raise(req);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void stageSourcesAreRetired() {
        System.runAs(RlyTestData.admin()) {
            routeWithUat();
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assert(s.canHotfix, 'Admins may flag hotfixes');
            System.assert(s.stageSources.isEmpty(), 'Stage orgs aren\'t offered as sources any more');
            System.assertEquals(3, s.routeStops.size(), 'SIT, UAT and the hub are shown for context');
            System.assertEquals('PROD', RlyHotfix.nextStop(orgId('UAT'), RlyReleaseStore.routeOrgs()).Name, 'The last stage goes to the hub');
            System.assertEquals(null, RlyHotfix.nextStop(orgId('PROD'), RlyReleaseStore.routeOrgs()), 'Nothing after the hub');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assert(!s.canHotfix, 'No hotfix permission');
            System.assert(s.stageSources.isEmpty(), 'Still empty');
        }
    }

    @IsTest
    static void stageSourcesAreRefused() {
        System.runAs(RlyTestData.admin()) {
            routeWithUat();
            RlyRaiseService.RaiseRequest req = request(orgId('SIT'));
            System.assertEquals(RlyRaiseRoute.STAGE_RETIRED, refusal(req), 'Raising from a stage org is refused');
            Boolean listing = false;
            try {
                RlyChangesController.listTracked(orgId('SIT'), null);
            } catch (AuraHandledException e) {
                listing = e.getMessage().contains('developer org now');
            }
            System.assert(listing, 'Its changes can\'t be listed either');
            System.assertEquals(0, [SELECT COUNT() FROM RLY_Release__c], 'Nothing saved');
        }
    }

    @IsTest
    static void hotfixFromADeveloperOrg() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c dev = RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = request(dev.Id);
            req.isHotfix = true;
            req.hotfixReason = '  Case escalation sends duplicate emails.  ';
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = RlyReleaseTestData.reload(relId);
            System.assertEquals(true, rel.Is_Hotfix__c, 'Flagged');
            System.assertEquals('Case escalation sends duplicate emails.', rel.Hotfix_Reason__c, 'Reason trimmed');
            System.assertEquals('Release', rel.Release_Type__c, 'A release');
            System.assertEquals(orgId('SIT'), rel.Target_Org__c, 'Into the first stage like any release');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(relId);
            System.assert(d.isHotfix, 'Shown as a hotfix');
            System.assertEquals('Case escalation sends duplicate emails.', d.hotfixReason, 'With its reason');
            RlyReleasesController.Row row = RlyReleasesController.listReleases('all')[0];
            System.assert(row.isHotfix && row.hotfix, 'Listed as a hotfix');
            System.assertEquals('Release', row.releaseType, 'Type');
        }
    }

    @IsTest
    static void hotfixNeedsPermissionAndReason() {
        Id devId;
        System.runAs(RlyTestData.admin()) {
            devId = RlyReleaseTestData.route().Id;
            RlyRaiseService.RaiseRequest req = request(devId);
            req.isHotfix = true;
            req.hotfixReason = '  ';
            System.assertEquals('Say why this is a hotfix.', refusal(req), 'A reason is required');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlyRaiseService.RaiseRequest req = request(devId);
            req.isHotfix = true;
            req.hotfixReason = 'Urgent';
            System.assertEquals('Only users with the Hotfix permission can raise a hotfix.', refusal(req), 'Permission needed');
        }
    }

    @IsTest
    static void hotfixBranchStartsFromTheTarget() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.hotfixRelease('Retrieving');
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            String branch = 'hotfix/' + rel.Name.toLowerCase();
            System.assertEquals('Workflow running', saved.Status__c, 'Pipeline started: ' + saved.Error_Message__c);
            System.assertEquals(branch, saved.Source_Branch__c, 'A hotfix branch');
            System.assert(mock.callLog().contains('GET callout:RLY_GitHub/repos/acme/release/git/ref/heads/sit'),
                'From the target\'s branch, so only the hotfix goes into the pull request: ' + mock.callLog());
            System.assert(mock.bodyFor('/git/refs').contains('refs/heads/' + branch), 'Named hotfix/...');
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('validateMerged'), 'Validated merged');
        }
    }

    @IsTest
    static void approvedHotfixSyncsTheDevelopers() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.hotfixRelease('Ready for approval');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            insert RlyTestData.org('DEV2', 'Developer', 'dev2');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.approve(rel.Id, 'Urgent');
            Test.stopTest();
            System.assertEquals(new List<Object>{ 'dev1', 'dev2' }, RlyReleaseTestData.dispatchedOptions(mock).get('syncBranches'),
                'Into the first stage: every developer branch, no stage branch first');
            System.assert(!RlyReleaseTestData.dispatchedOptions(mock).containsKey('stageWins'), 'No stage-wins merge');
        }
    }
}
