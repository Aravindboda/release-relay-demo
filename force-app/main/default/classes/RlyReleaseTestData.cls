/**
 * @description Shared data for the release-flow tests: a route (DEV1 → SIT → hub) with a checked GitHub
 * connection, releases at a given status or already deployed, result files and reloading a release.
 */
@IsTest
public with sharing class RlyReleaseTestData {

    /** @description The signing secret the Slack tests sign with. */
    public static final String SIGNING_SECRET = '8f742231b10e8888abcd99yyyzzz4f2a';

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
     * @description A hotfix already at a status: raised from DEV1 into SIT, flagged with a reason, on a hotfix branch.
     * @param status the release status
     * @return the release, with Id and Name
     */
    public static RLY_Release__c hotfixRelease(String status) {
        RLY_Release__c rel = release(status, 'hub');
        update new RLY_Release__c(Id = rel.Id, Is_Hotfix__c = true, Hotfix_Reason__c = 'Duplicate emails in production',
            Source_Branch__c = 'hotfix/' + rel.Name.toLowerCase());
        return rel;
    }

    /**
     * @description A release already deployed to an org (route included or not: the org must exist), merged with a commit.
     * @param orgName the org it was deployed to (its branch is the lower-case name)
     * @param sha its merge commit
     * @return the release, with Id and Name
     */
    public static RLY_Release__c deployedIn(String orgName, String sha) {
        Id orgId = [SELECT Id FROM RLY_Org__c WHERE Name = :orgName LIMIT 1].Id;
        Id devId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1' LIMIT 1].Id;
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Change ' + sha.left(4), Status__c = 'Deployed', Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Release_Type__c = 'Release', Source_Org__c = devId, Target_Org__c = orgId, Org_Label__c = 'DEV1',
            Target_Branch__c = orgName.toLowerCase(), Source_Environment__c = 'dev1', Target_Environment__c = orgName.toLowerCase(),
            Test_Classes__c = 'AccountServiceTest', Scan_Status__c = 'Passed', Validation_Status__c = 'Passed',
            Approval_Status__c = 'Approved', Deploy_Status__c = 'Deployed', Merge_Commit__c = sha,
            Last_Synced__c = System.now().addMinutes(-30), Component_Count__c = 1);
        insert rel;
        insert new RLY_Release_Item__c(Release__c = rel.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService' + sha.left(1));
        return [SELECT Id, Name FROM RLY_Release__c WHERE Id = :rel.Id];
    }

    /**
     * @description A 40-character commit hash made of one character.
     * @param c the character
     * @return the hash
     */
    public static String sha(String c) {
        return c.repeat(40);
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
                       Deploy_Status__c, Merge_Commit__c, Scan_Bypass_Reason__c, Retrieve_Id__c, Test_Classes__c,
                       Validation_Result__c, Deploy_Result__c, Check_Token__c, Slack_Channel_Id__c, Slack_Ts__c, Approved_Via__c,
                       Approved_By__c, Checks_Requested__c, Release_Type__c, Is_Hotfix__c, Hotfix_Reason__c, Promoted_In__c,
                       Carried_Releases__c, Second_Approved_By__c, Second_Approved_On__c, Back_Merge_Result__c, Approved_On__c,
                       Target_Org__c, Source_Org__c, Target_Branch__c, Target_Environment__c, Source_Environment__c, Component_Count__c
                FROM RLY_Release__c WHERE Id = :relId];
    }

    /**
     * @description The options of the last pipeline run the mock was asked to start.
     * @param mock the callout mock
     * @return the parsed options input
     */
    public static Map<String, Object> dispatchedOptions(RlyHttpMock mock) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'));
        Map<String, Object> inputs = (Map<String, Object>) body.get('inputs');
        return (Map<String, Object>) JSON.deserializeUntyped(String.valueOf(inputs.get('options')));
    }

    /**
     * @description A validate.json that conflicts with sit in two files; the second is marked truncated.
     * @return the result's JSON
     */
    public static String conflictResult() {
        return JSON.serialize(new Map<String, Object>{
            'status' => 'Conflict', 'message' => '2 file(s) conflict with sit',
            'conflicts' => new List<Object>{
                new Map<String, Object>{ 'file' => 'force-app/main/default/classes/AccountService.cls',
                    'merged' => 'a\n<<<<<<< mine\nb\n=======\nc\n>>>>>>> sit\n', 'mine' => 'a\nb\n', 'theirs' => 'a\nc\n' },
                new Map<String, Object>{ 'file' => 'force-app/main/default/classes/AccountServiceTest.cls',
                    'merged' => 'x', 'mine' => 'y', 'theirs' => 'z', 'truncated' => true }
            }
        });
    }

    /**
     * @description Turns Slack on for the hub (the Slack record) with these events and a signing secret.
     * @param events the selected events (; separated), or null
     * @return the record
     */
    public static RLY_Notification__c slackOn(String events) {
        RLY_Notification__c s = new RLY_Notification__c(Name = 'Slack', Channel__c = 'Slack', Enabled__c = true,
            Events__c = events, Signing_Secret__c = SIGNING_SECRET);
        insert s;
        return s;
    }

    /**
     * @description Sets where releases into the release's target org are approved, and has it post to a Slack channel.
     * @param rel the release
     * @param approvalIn Salesforce, Slack or Git
     */
    public static void targetSlack(RLY_Release__c rel, String approvalIn) {
        Id targetId = [SELECT Target_Org__c FROM RLY_Release__c WHERE Id = :rel.Id].Target_Org__c;
        update new RLY_Org__c(Id = targetId, Approval_In__c = approvalIn, Slack_Post__c = true, Slack_Channel__c = '#releases');
    }

    /**
     * @description Adds Slack Web API answers to a mock: every call succeeds with channel C123 and ts 1700.0001.
     * @param mock the mock
     * @return the mock
     */
    public static RlyHttpMock withSlack(RlyHttpMock mock) {
        return mock.match('POST', 'callout:RLY_Slack/auth.test').reply(200, '{"ok":true,"team":"Acme","user":"relay"}')
            .match('POST', 'callout:RLY_Slack/').reply(200, '{"ok":true,"channel":"C123","ts":"1700.0001"}');
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
