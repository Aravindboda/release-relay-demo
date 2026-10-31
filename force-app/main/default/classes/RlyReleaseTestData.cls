/**
 * @description Shared data for the release-flow tests: a route (DEV1 → SIT → hub) with a checked GitHub
 * connection, releases at a given status, result files and reloading a release.
 */
@IsTest
public with sharing class RlyReleaseTestData {

    /**
     * @description DEV1 → SIT → hub, with a checked GitHub connection.
     * @return DEV1
     */
    public static RLY_Org__c route() {
        RLY_Org__c dev = RlyTestData.org('DEV1', 'Developer', 'dev1');
        insert new List<RLY_Org__c>{ dev, RlyTestData.stage('SIT', 'sit', 1), RlyTestData.org('PROD', 'Hub', 'prod') };
        insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = 'acme/release', Named_Credential__c = 'RLY_GitHub',
            Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default',
            Code_Scan__c = true, Status__c = 'Connected');
        return dev;
    }

    /**
     * @description A release already at a status, with one Apex class and its test (route included).
     * @param status the release status
     * @param pendingRun the run it waits for (hub, check, merge) or null
     * @return the release, with Id and Name
     */
    public static RLY_Release__c release(String status, String pendingRun) {
        RLY_Org__c dev = route();
        Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Source_Org__c = dev.Id, Target_Org__c = sitId, Org_Label__c = 'DEV1',
            Target_Branch__c = 'sit', Source_Environment__c = 'dev1', Target_Environment__c = 'sit', Retrieve_Id__c = RlyFlowScenario.RETRIEVE_ID,
            Test_Classes__c = 'AccountServiceTest', Scan_Status__c = 'Pending', Validation_Status__c = 'Pending',
            Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Pending_Run__c = pendingRun,
            Checks_Requested__c = System.now().addMinutes(-1), Component_Count__c = 2);
        insert rel;
        rel = [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
        update new RLY_Release__c(Id = rel.Id, Source_Branch__c = 'feature/' + rel.Name.toLowerCase());
        insert new List<RLY_Release_Item__c>{
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService'),
            new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountServiceTest')
        };
        return rel;
    }

    /**
     * @description A step's result file, finished now.
     * @param step scan, validate, merge or deploy
     * @param body the result's own JSON members
     * @return the file's JSON
     */
    public static String result(String step, String body) {
        return '{"request":"x","step":"' + step + '",' + body + ',"finishedAt":"' + System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') + '"}';
    }

    /**
     * @description A release as saved.
     * @param relId the release
     * @return its flow fields
     */
    public static RLY_Release__c reload(Id relId) {
        return [SELECT Status__c, Source_Branch__c, Pending_Run__c, PR_Number__c, PR_URL__c, Run_URL__c, Scan_Status__c,
                       Scan_Violations__c, Scan_Blocking__c, Validation_Status__c, Error_Message__c, Approval_Status__c,
                       Deploy_Status__c, Merge_Commit__c, Scan_Bypass_Reason__c, Retrieve_Id__c, Test_Classes__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    /**
     * @description A selected component.
     * @param type metadata type
     * @param name full name
     * @return the item
     */
    public static RlyRaiseService.Item item(String type, String name) {
        RlyRaiseService.Item i = new RlyRaiseService.Item();
        i.type = type;
        i.name = name;
        i.deleted = false;
        i.standard = false;
        return i;
    }
}
