/**
 * @description Shared test data for the Release Relay tests: the user tests run as, permission set
 * assignments, registered orgs and fake record ids built at runtime.
 */
@IsTest
public with sharing class RlyTestData {

    /** @description The consumer key test orgs are registered with. */
    public static final String CONSUMER_KEY = '3MVG9demoKeyRpu1';
    /** @description The masked hint of CONSUMER_KEY. */
    public static final String KEY_HINT = '••••••••Rpu1';
    /** @description The access token tests sign in with. */
    public static final String TOKEN = '00Dxx!token';

    /**
     * @description The active System Administrator every test runs as (System.runAs).
     * @return the user
     */
    public static User admin() {
        return [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true
                ORDER BY CreatedDate ASC LIMIT 1];
    }

    /**
     * @description Assigns a permission set to the test user, unless it already has it.
     * @param permissionSetName the permission set's API name
     */
    public static void assignPermissionSet(String permissionSetName) {
        User u = admin();
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        if (sets.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existing = [SELECT Id FROM PermissionSetAssignment
                                                  WHERE AssigneeId = :u.Id AND PermissionSetId = :sets[0].Id LIMIT 1];
        if (existing.isEmpty()) {
            System.runAs(u) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sets[0].Id);
            }
        }
    }

    /**
     * @description A registered org (not inserted), connected, with its branch as its Git environment.
     * @param name org name
     * @param role Developer, Stage or Hub
     * @param branch its branch and Git environment
     * @return the org
     */
    public static RLY_Org__c org(String name, String role, String branch) {
        return new RLY_Org__c(Name = name, Role__c = role, Branch__c = branch,
            Git_Environment__c = branch, My_Domain__c = 'https://' + name.toLowerCase() + '.my.salesforce.com',
            Login_Type__c = 'Production', Username__c = 'relay@' + name.toLowerCase() + '.demo',
            Consumer_Key__c = CONSUMER_KEY, Certificate__c = 'release_relay', Status__c = 'Connected');
    }

    /**
     * @description A stage (not inserted) at a position on the route.
     * @param name org name
     * @param branch its branch and Git environment
     * @param stageOrder its position
     * @return the org
     */
    public static RLY_Org__c stage(String name, String branch, Decimal stageOrder) {
        RLY_Org__c o = org(name, 'Stage', branch);
        o.Stage_Order__c = stageOrder;
        return o;
    }

    /**
     * @description A new active user with the System Administrator profile and no Release Relay permission sets
     * (inserted as the test user, in its own runAs, so it doesn't mix with other DML).
     * @return the user
     */
    public static User plainUser() {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User u = new User(Alias = 'rlyplain', Email = 'rly.plain@example.com', EmailEncodingKey = 'UTF-8', LastName = 'Plain',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId, TimeZoneSidKey = 'America/Chicago',
            Username = 'rly.plain.' + UserInfo.getOrganizationId() + '.' + Datetime.now().getTime() + '@example.com');
        System.runAs(admin()) {
            insert u;
        }
        return u;
    }

    /**
     * @description A 15-character fake id with a key prefix, built at runtime (for mocked org answers).
     * @param prefix the key prefix, for example 00D
     * @param n a number that tells fake ids apart
     * @return the fake id
     */
    public static String fakeId(String prefix, Integer n) {
        return prefix + String.valueOf(n).leftPad(12, '0');
    }
}
