/**
 * @description Test data shared by the migration tests (RlyMigrationTest, RlyMigrationPartsTest, RlyMigrationCancelTest):
 * the route with its GitHub connection, a second (GitLab) connection, and lookups of what they create.
 */
@IsTest
public class RlyMigrationTestData {

    /**
     * @description The route (GitHub connection, two days old) and a connected GitLab connection; run inside @TestSetup.
     */
    public static void connections() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            Test.setCreatedDate(gitHubId(), Datetime.now().addDays(-2));
            insert new RLY_Git_Connection__c(Name = 'GitLab group/project', Provider__c = 'GitLab', Repository__c = 'group/project',
                Named_Credential__c = 'RLY_GitLab', Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main',
                Source_Path__c = 'force-app/main/default', Status__c = 'Connected');
            RlyReleaseStore.forgetGit();
        }
    }

    /**
     * @description The GitHub connection's Id.
     * @return the Id
     */
    public static Id gitHubId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1].Id;
    }

    /**
     * @description The GitLab connection's Id.
     * @return the Id
     */
    public static Id gitLabId() {
        return [SELECT Id FROM RLY_Git_Connection__c WHERE Provider__c = 'GitLab' LIMIT 1].Id;
    }

    /**
     * @description An org's Id by name.
     * @param name the org's name
     * @return the Id
     */
    public static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    /**
     * @description A release from DEV1 into SIT at a status (not inserted).
     * @param status the status
     * @return the release
     */
    public static RLY_Release__c release(String status) {
        return new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes', Request_Type__c = 'Changes',
            Source_Org__c = orgId('DEV1'), Target_Org__c = orgId('SIT'), Org_Label__c = 'DEV1', Target_Branch__c = 'sit',
            Source_Environment__c = 'dev1', Target_Environment__c = 'sit', Scan_Status__c = 'Pending', Validation_Status__c = 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Component_Count__c = 1);
    }
}
