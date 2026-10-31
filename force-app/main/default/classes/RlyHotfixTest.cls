/**
 * @description Tests for hotfixes raised from a stage org (RlyHotfix, RlyRaiseRoute, RlyReleaseStart, the hotfix parts
 * of RlyChangesController, RlyStatusReader and RlyPipelineOptions). Each test runs through System.runAs: as an active
 * System Administrator with Release Relay Admin (which grants RLY_Hotfix), or as a new user without it.
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

    @IsTest
    static void stageSourcesShowWithThePermission() {
        System.runAs(RlyTestData.admin()) {
            routeWithUat();
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assert(s.canHotfix, 'Admins may raise hotfixes');
            System.assertEquals(2, s.stageSources.size(), 'SIT and UAT have a next stop; the hub has none');
            System.assertEquals('SIT', s.stageSources[0].name, 'In route order');
            System.assertEquals('UAT', s.stageSources[0].targetName, 'SIT goes to the next stage');
            System.assertEquals('uat', s.stageSources[0].targetBranch, 'With its branch');
            System.assertEquals('PROD', s.stageSources[1].targetName, 'The last stage goes to the hub');
            System.assertEquals('prod', s.stageSources[1].targetBranch, 'The hub\'s branch');
            System.assertEquals('Full_Copy', s.stageSources[1].environment, 'Each stage keeps its environment');
            System.assertEquals(3, s.routeStops.size(), 'SIT, UAT and the hub are shown for context');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlyReleaseStart.Start s = RlyChangesController.getStart();
            System.assert(!s.canHotfix, 'No hotfix permission');
            System.assert(s.stageSources.isEmpty(), 'Stage orgs aren\'t offered');
        }
    }

    @IsTest
    static void hotfixGoesToTheNextStop() {
        System.runAs(RlyTestData.admin()) {
            routeWithUat();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyFlowScenario().build());
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = orgId('SIT');
            req.title = 'Fix the discount';
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
            req.testClasses = new List<String>();
            Test.startTest();
            Id relId = RlyReleasesController.raiseRelease(JSON.serialize(req));
            Test.stopTest();
            RLY_Release__c rel = [SELECT Target_Org__r.Name, Target_Branch__c, Target_Environment__c, Status__c, Request_Type__c, Mode__c
                                  FROM RLY_Release__c WHERE Id = :relId];
            System.assertEquals('UAT', rel.Target_Org__r.Name, 'Into the next stage, not the first one');
            System.assertEquals('uat', rel.Target_Branch__c, 'Its branch');
            System.assertEquals('Retrieving', rel.Status__c, 'Retrieving from SIT');
            System.assertEquals('Changes', rel.Request_Type__c, 'Request type unchanged');
            System.assertEquals('Org changes', rel.Mode__c, 'Mode unchanged');
            RlyReleasesController.Detail d = RlyReleasesController.getRelease(relId);
            System.assert(RlyHotfix.isHotfix(d.release), 'Shown as a hotfix');
            System.assertEquals('PROD', RlyHotfix.nextStop(orgId('UAT'), RlyReleaseStore.routeOrgs()).Name, 'The last stage goes to the hub');
            System.assertEquals(null, RlyHotfix.nextStop(orgId('PROD'), RlyReleaseStore.routeOrgs()), 'Nothing after the hub');
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
            System.assert(mock.callLog().contains('POST callout:RLY_GitHub/repos/acme/release/git/refs'), 'Branch created');
            System.assert(mock.callLog().contains('GET callout:RLY_GitHub/repos/acme/release/git/ref/heads/uat'),
                'From the target\'s branch, so only the hotfix goes into the pull request: ' + mock.callLog());
            System.assert(mock.bodyFor('/git/refs').contains('refs/heads/' + branch), 'Named hotfix/...');
            System.assertEquals(true, RlyReleaseTestData.dispatchedOptions(mock).get('validateMerged'), 'Validated merged');
            System.assertEquals(1, RlyReleasesController.listReleases('all').size(), 'Listed');
            System.assert(RlyReleasesController.listReleases('all')[0].hotfix, 'As a hotfix');
        }
    }

    @IsTest
    static void approvedHotfixSyncsTheStageAndDevelopers() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.hotfixRelease('Ready for approval');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42);
            insert RlyTestData.org('DEV2', 'Developer', 'dev2');
            RlyHttpMock mock = new RlyFlowScenario().build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.approve(rel.Id, 'Urgent');
            Test.stopTest();
            System.assertEquals(new List<Object>{ 'sit', 'dev1', 'dev2' }, RlyReleaseTestData.dispatchedOptions(mock).get('syncBranches'),
                'The stage it came from, then every developer branch');
        }
    }

    @IsTest
    static void refusedWithoutThePermission() {
        Id sitId;
        System.runAs(RlyTestData.admin()) {
            routeWithUat();
            sitId = orgId('SIT');
        }
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            RlyRaiseService.RaiseRequest req = new RlyRaiseService.RaiseRequest();
            req.sourceOrgId = sitId;
            req.title = 'Fix';
            req.items = new List<RlyRaiseService.Item>{ RlyReleaseTestData.item('Layout', 'Account-Account Layout') };
            String message;
            try {
                RlyRaiseService.raise(req);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assertEquals('Raising a hotfix from a stage org needs the Release Relay Hotfix permission.', message, 'Raise refused');
            Boolean listing = false;
            try {
                RlyChangesController.listTracked(sitId, null);
            } catch (AuraHandledException e) {
                listing = e.getMessage().contains('Hotfix permission');
            }
            System.assert(listing, 'Its changes can\'t be listed either');
        }
    }
}
