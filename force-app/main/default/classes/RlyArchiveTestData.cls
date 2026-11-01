/**
 * @description Shared data for the archive tests: the hub (route and Git connection, RlyReleaseTestData), the Retention
 * setting, finished and open releases with their items, history, manual steps, step runs and an evidence file, an
 * approver, and archive runs.
 */
@IsTest
public with sharing class RlyArchiveTestData {

    /**
     * @description The hub: DEV1 → SIT → PROD with a checked GitHub connection.
     * @return the settings record (the Git connection)
     */
    public static RLY_Git_Connection__c hub() {
        RlyReleaseTestData.route();
        return settings();
    }

    /**
     * @description The settings record.
     * @return the Git connection
     */
    public static RLY_Git_Connection__c settings() {
        return [SELECT Id, Retention_Days__c, Archive_Nightly__c, Retention_Changed_On__c, Retention_Previous_Days__c,
                    Last_Nightly_Call__c, Last_Nightly_Result__c
                FROM RLY_Git_Connection__c ORDER BY CreatedDate ASC LIMIT 1];
    }

    /**
     * @description Sets the Retention days directly (no checks), nightly off.
     * @param days the days, or null
     */
    public static void retention(Integer days) {
        update new RLY_Git_Connection__c(Id = settings().Id, Retention_Days__c = days, Archive_Nightly__c = false);
    }

    /**
     * @description Sets the Retention days directly (no checks), nightly on.
     * @param days the days, or null
     */
    public static void nightly(Integer days) {
        update new RLY_Git_Connection__c(Id = settings().Id, Retention_Days__c = days, Archive_Nightly__c = true);
    }

    /**
     * @description A release between DEV1 and SIT at a status (not inserted).
     * @param status the release status
     * @return the release
     */
    public static RLY_Release__c release(String status) {
        Id devId = [SELECT Id FROM RLY_Org__c WHERE Name = 'DEV1' LIMIT 1].Id;
        Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
        return new RLY_Release__c(Title__c = status + ' change', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Release_Type__c = 'Release', Source_Org__c = devId, Target_Org__c = sitId,
            Org_Label__c = 'DEV1', Target_Branch__c = 'sit', Approval_Status__c = 'Pending');
    }

    /**
     * @description Gives each release an item, a history entry, a manual step and its step run (inserted).
     * @param rels the releases (inserted)
     */
    public static void children(List<RLY_Release__c> rels) {
        Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
        List<RLY_Release_Item__c> items = new List<RLY_Release_Item__c>();
        List<RLY_Release_Event__c> events = new List<RLY_Release_Event__c>();
        List<RLY_Manual_Step__c> steps = new List<RLY_Manual_Step__c>();
        for (RLY_Release__c r : rels) {
            items.add(new RLY_Release_Item__c(Release__c = r.Id, Metadata_Type__c = 'ApexClass', Component_Name__c = 'AccountService'));
            events.add(new RLY_Release_Event__c(Release__c = r.Id, Event_Type__c = 'Deployed', Org__c = sitId,
                Actor__c = UserInfo.getUserId(), Via__c = 'Salesforce', Detail__c = 'Deployed', Occurred_On__c = System.now()));
            steps.add(new RLY_Manual_Step__c(Release__c = r.Id, Title__c = 'Assign permission set', Category__c = 'Permissions',
                Timing__c = 'After_Deploy', Sequence__c = 1));
        }
        insert items;
        insert events;
        insert steps;
        List<RLY_Manual_Step_Run__c> runs = new List<RLY_Manual_Step_Run__c>();
        for (RLY_Manual_Step__c s : steps) {
            runs.add(new RLY_Manual_Step_Run__c(Step__c = s.Id, Release__c = s.Release__c, Org__c = sitId, Status__c = 'Done'));
        }
        insert runs;
    }

    /**
     * @description Finished releases with their children (inserted).
     * @param status the status, for example Deployed
     * @param n how many
     * @return the releases
     */
    public static List<RLY_Release__c> finished(String status, Integer n) {
        List<RLY_Release__c> rels = new List<RLY_Release__c>();
        for (Integer i = 0; i < n; i++) {
            rels.add(release(status));
        }
        insert rels;
        children(rels);
        return rels;
    }

    /**
     * @description An evidence PDF in the release's Files (linked to the release and its owner).
     * @param releaseId the release
     * @return the file's ContentDocument Id
     */
    public static Id evidence(Id releaseId) {
        ContentVersion v = new ContentVersion(Title = 'Evidence', PathOnClient = 'Evidence.pdf', VersionData = Blob.valueOf('%PDF'),
            FirstPublishLocationId = releaseId);
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    /**
     * @description Makes the archive work as if this many days had passed (everything raised now is older).
     * @param days the days
     */
    public static void later(Integer days) {
        RlyArchiveService.nowForTest = System.now().addDays(days);
    }

    /**
     * @description A new user with Release Relay Approver only (inserted in its own runAs).
     * @return the user
     */
    public static User approver() {
        User u = RlyTestData.plainUser();
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = 'RLY_Approver' LIMIT 1];
        System.runAs(RlyTestData.admin()) {
            if (!sets.isEmpty()) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sets[0].Id);
            }
        }
        return u;
    }

    /**
     * @description An archive run row (inserted).
     * @param how Nightly or Run_Now
     * @param status the status
     * @param started when it started
     * @return the row
     */
    public static RLY_Archive_Run__c run(String how, String status, Datetime started) {
        RLY_Archive_Run__c r = new RLY_Archive_Run__c(How__c = how, Status__c = status, Started__c = started,
            Finished__c = status == RlyArchiveRuns.RUNNING ? null : started.addMinutes(1), Run_By__c = UserInfo.getUserId(),
            Retention_Days__c = 30, Cutoff__c = started.addDays(-30), Passes__c = 1, Releases_Removed__c = 10,
            Records_Removed__c = 50, Storage_Freed_KB__c = 100, Message__c = status);
        insert r;
        return r;
    }
}
