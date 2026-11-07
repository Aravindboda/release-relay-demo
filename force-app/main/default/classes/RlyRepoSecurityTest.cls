/**
 * @description Tests for the Repository security card (build 48: RlyRepoSecurity, RlyRepoSecurityGitHub,
 * RlyRepoSecurityGitLab, through RlyRunSigningController.checkRepository): GitHub and GitLab answers are mocked
 * (RlyHttpMock); rows are in place, missing (with how to fix) or unreadable, and nothing throws. The route's orgs give
 * the environments dev1, sit and prod. Every test runs as an active System Administrator holding Release Relay Admin.
 */
@IsTest
private class RlyRepoSecurityTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Map<String, RlyRepoSecurity.Item> byKey(RlyRepoSecurity.Report r) {
        Map<String, RlyRepoSecurity.Item> out = new Map<String, RlyRepoSecurity.Item>();
        for (RlyRepoSecurity.Item i : r.items) {
            out.put(i.key, i);
        }
        return out;
    }

    private static void toGitLab() {
        RLY_Git_Connection__c c = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
        update new RLY_Git_Connection__c(Id = c.Id, Provider__c = 'GitLab', Repository__c = 'acme/salesforce', Pipeline__c = '.gitlab-ci.yml');
    }

    @IsTest
    static void gitHubProtectionsInPlaceMissingAndUnreadable() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/repos/acme/release/branches/main/protection').reply(200, '{"required_pull_request_reviews":{"required_approving_review_count":1}}')
                .match('GET', '/actions/secrets').reply(200, '{"total_count":2,"secrets":[{"name":"SF_JWT_KEY"},{"name":"RELAY_RUN_KEY"}]}')
                .match('GET', '/secrets?per_page').reply(200, '{"total_count":1,"secrets":[{"name":"RELAY_RUN_KEY"}]}')
                .match('GET', '/environments/sit/deployment-branch-policies').reply(200, '{"branch_policies":[{"name":"main","type":"branch"}]}')
                .match('GET', '/environments/sit').reply(200, '{"name":"sit","deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}')
                .match('GET', '/environments/prod').reply(200, '{"name":"prod","deployment_branch_policy":null}')
                .match('GET', '/environments/dev1').reply(403, '{"message":"Resource not accessible by personal access token"}'));
            Test.startTest();
            RlyRepoSecurity.Report r = RlyRunSigningController.checkRepository();
            Test.stopTest();
            Map<String, RlyRepoSecurity.Item> rows = byKey(r);
            System.assertEquals('GitHub', r.provider, 'Provider');
            System.assertEquals(RlyRepoSecurity.OK, rows.get('branch').state, 'main needs 1 approval: ' + rows.get('branch').detail);
            System.assertEquals(null, rows.get('branch').fix, 'No fix line when in place');
            System.assertEquals(RlyRepoSecurity.OK, rows.get('key').state, 'RELAY_RUN_KEY in every org environment: ' + rows.get('key').detail);
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('key-repo').state, 'A repository-level copy is flagged');
            System.assert(rows.get('key-repo').fix.startsWith('Move it to the environments'), 'How to fix: ' + rows.get('key-repo').fix);
            System.assertEquals(RlyRepoSecurity.OK, rows.get('env:sit').state, 'sit deploys only from main');
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('env:prod').state, 'prod open to every branch');
            System.assert(rows.get('env:prod').fix.contains('Selected branches'), 'How to fix: ' + rows.get('env:prod').fix);
            System.assertEquals(RlyRepoSecurity.UNKNOWN, rows.get('env:dev1').state, 'dev1 couldn\'t be read');
            System.assert(rows.get('env:dev1').fix.contains('Environments: read'), 'Which permission: ' + rows.get('env:dev1').fix);
            System.assertEquals(2, r.missing, 'prod and the repository-level key to fix');
            System.assertEquals(1, r.unknown, 'One unreadable');
        }
    }

    @IsTest
    static void gitHubRulesetsAndGaps() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/branches/main/protection').reply(404, '{"message":"Branch not protected"}')
                .match('GET', '/rules/branches/main').reply(200, '[{"type":"deletion"},{"type":"pull_request","parameters":{"required_approving_review_count":2}}]')
                .match('GET', '/actions/secrets').reply(200, '{"total_count":0,"secrets":[]}')
                .match('GET', '/environments/dev1/secrets').reply(403, '{"message":"Resource not accessible"}')
                .match('GET', '/environments/sit/deployment-branch-policies').reply(200, '{"branch_policies":[{"name":"main"},{"name":"feature/*"}]}')
                .match('GET', '/environments/sit').reply(200, '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}')
                .match('GET', '/environments/prod').reply(200, '{"deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}'));
            Test.startTest();
            Map<String, RlyRepoSecurity.Item> rows = byKey(RlyRunSigningController.checkRepository());
            Test.stopTest();
            System.assertEquals(RlyRepoSecurity.OK, rows.get('branch').state, 'A ruleset with 2 approvals: ' + rows.get('branch').detail);
            System.assertEquals(RlyRepoSecurity.UNKNOWN, rows.get('key').state, 'dev1\'s secrets can\'t be listed: ' + rows.get('key').detail);
            System.assertEquals(null, rows.get('key-repo'), 'No repository-level copy, no row');
            System.assert(rows.get('env:sit').detail.contains('feature/*'), 'Other branches named: ' + rows.get('env:sit').detail);
            System.assertEquals(RlyRepoSecurity.OK, rows.get('env:prod').state, 'Protected branches only');
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('env:dev1').state, 'Not in GitHub yet');
        }
    }

    @IsTest
    static void gitHubBranchWithoutReviewAndKeyMissingInOneEnvironment() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/branches/main/protection').reply(200, '{"enforce_admins":{"enabled":true}}')
                .match('GET', '/actions/secrets').reply(200, '{"secrets":[]}')
                .match('GET', '/environments/prod/secrets').reply(200, '{"secrets":[{"name":"SF_JWT_KEY"}]}')
                .match('GET', '/secrets?per_page').reply(200, '{"secrets":[{"name":"RELAY_RUN_KEY"}]}'));
            Test.startTest();
            Map<String, RlyRepoSecurity.Item> rows = byKey(RlyRunSigningController.checkRepository());
            Test.stopTest();
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('branch').state, 'Protected but no review: ' + rows.get('branch').detail);
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('key').state, 'Not in prod: ' + rows.get('key').detail);
            System.assert(rows.get('key').detail.contains('prod') && !rows.get('key').detail.contains('sit'), 'Names where it\'s missing');
            System.assert(rows.get('key').fix.contains('Add environment secret'), 'How to fix: ' + rows.get('key').fix);
        }
    }

    @IsTest
    static void gitLabProtectionsInPlaceMissingAndUnreadable() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            toGitLab();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/projects/acme/salesforce/protected_branches/main').reply(200, '{"name":"main","push_access_levels":[{"access_level":0}]}')
                .match('GET', '/approval_rules').reply(200, '[{"name":"Release","approvals_required":1}]')
                .match('GET', '/variables').reply(200, '[{"key":"SF_JWT_KEY","value":"x","masked":true,"protected":true},'
                    + '{"key":"RELAY_RUN_KEY","value":"hidden","masked":true,"protected":true}]')
                .match('GET', '/protected_environments/sit').reply(200, '{"name":"sit"}')
                .match('GET', '/protected_environments/prod').reply(404, '{"message":"404 Not found"}')
                .match('GET', '/protected_environments/dev1').reply(403, '{"message":"403 Forbidden"}'));
            Test.startTest();
            RlyRepoSecurity.Report r = RlyRunSigningController.checkRepository();
            Test.stopTest();
            Map<String, RlyRepoSecurity.Item> rows = byKey(r);
            System.assertEquals(RlyRepoSecurity.OK, rows.get('branch').state, 'Nobody pushes to main: ' + rows.get('branch').detail);
            System.assertEquals(RlyRepoSecurity.OK, rows.get('approvals').state, 'One approval required');
            System.assertEquals(RlyRepoSecurity.OK, rows.get('key').state, 'Masked and protected');
            System.assert(!JSON.serialize(r).contains('hidden'), 'The variable\'s value is never kept');
            System.assertEquals(RlyRepoSecurity.OK, rows.get('env:sit').state, 'Protected environment');
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('env:prod').state, 'Not protected');
            System.assertEquals(RlyRepoSecurity.UNKNOWN, rows.get('env:dev1').state, 'Couldn\'t read');
        }
    }

    @IsTest
    static void gitLabGaps() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            toGitLab();
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock()
                .match('GET', '/protected_branches/main').reply(200, '{"name":"main","push_access_levels":[{"access_level":30}]}')
                .match('GET', '/approval_rules').reply(403, '{"message":"403 Forbidden"}')
                .match('GET', '/approvals').reply(200, '{"approvals_before_merge":0}')
                .match('GET', '/variables').reply(200, '[{"key":"RELAY_RUN_KEY","masked":true,"protected":true,"environment_scope":"prod"}]'));
            Test.startTest();
            Map<String, RlyRepoSecurity.Item> rows = byKey(RlyRunSigningController.checkRepository());
            toGitLabMissing();
            Test.stopTest();
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('branch').state, 'Developers can push');
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('approvals').state, 'No approvals required');
            System.assertEquals(RlyRepoSecurity.MISSING, rows.get('key').state, 'Scope isn\'t *');
        }
    }

    // A second read where nothing answers: every row missing or unreadable, nothing thrown.
    private static void toGitLabMissing() {
        Test.setMock(HttpCalloutMock.class, new RlyHttpMock());
        RlyRepoSecurity.Report r = RlyRepoSecurity.check();
        System.assert(r.missing + r.unknown == r.items.size(), 'Nothing in place: ' + JSON.serialize(r));
    }

    @IsTest
    static void noConnectionOrAnotherProvider() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyRepoSecurity.Report none = RlyRepoSecurity.check();
            insert new RLY_Git_Connection__c(Provider__c = 'Bitbucket', Repository__c = 'acme/release', Named_Credential__c = 'RLY_Bitbucket',
                Pipeline__c = 'bitbucket-pipelines.yml', Pipeline_Branch__c = 'main', Status__c = 'Connected');
            RlyRepoSecurity.Report other = RlyRepoSecurity.check();
            Test.stopTest();
            System.assertEquals(1, none.missing, 'No connection yet');
            System.assertEquals(1, other.unknown, 'Bitbucket is checked by hand: ' + JSON.serialize(other));
            System.assertEquals(3, RlyRepoSecurity.num('3') + RlyRepoSecurity.num(null) + RlyRepoSecurity.num('x'), 'Numbers from answers');
        }
    }
}
