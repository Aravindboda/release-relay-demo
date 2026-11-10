/**
 * @description Tests for the consumer key protection: saved encrypted (Consumer_Key__c), kept when an edit leaves it
 * blank, required for new orgs, moved from the old Client_Id__c by the check, used for sign-in with the old field as
 * fallback, and never sent to the browser (only a masked hint). Every test runs as an existing active System
 * Administrator with Release Relay Admin through System.runAs. DML happens before Test.startTest; callouts after it.
 */
@IsTest
private class RlyConsumerKeyTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static Map<String, Object> input(String name) {
        return new Map<String, Object>{
            'Name' => name, 'Role__c' => 'Developer', 'My_Domain__c' => 'https://demo-dev-ed.develop.my.salesforce.com',
            'Login_Type__c' => 'Production', 'Username__c' => 'relay@demo.dev', 'Consumer_Key__c' => RlyTestData.CONSUMER_KEY,
            'Certificate__c' => 'release_relay', 'Git_Environment__c' => 'dev1', 'Branch__c' => 'dev1'
        };
    }

    private static RLY_Org__c keys(Id orgId) {
        return [SELECT Consumer_Key__c, Client_Id__c FROM RLY_Org__c WHERE Id = :orgId];
    }

    @IsTest
    static void savesTheKeyEncrypted() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> fields = input('DEV1');
            fields.put('Consumer_Key__c', '  ' + RlyTestData.CONSUMER_KEY + ' ');
            Id orgId = RlyOrgController.saveOrg(JSON.serialize(fields));
            RLY_Org__c saved = keys(orgId);
            System.assertEquals(RlyTestData.CONSUMER_KEY, saved.Consumer_Key__c, 'Saved, trimmed, in the encrypted field');
            System.assertEquals(null, saved.Client_Id__c, 'Nothing in the old plain field');
        }
    }

    @IsTest
    static void blankKeyKeepsTheSavedKey() {
        System.runAs(RlyTestData.admin()) {
            Id orgId = RlyOrgController.saveOrg(JSON.serialize(input('DEV1')));
            Map<String, Object> edited = input('DEV1');
            edited.put('Id', orgId);
            edited.put('Branch__c', 'dev1b');
            edited.remove('Consumer_Key__c');
            RlyOrgController.saveOrg(JSON.serialize(edited));
            edited.put('Consumer_Key__c', '');
            RlyOrgController.saveOrg(JSON.serialize(edited));
            RLY_Org__c saved = [SELECT Branch__c, Consumer_Key__c FROM RLY_Org__c WHERE Id = :orgId];
            System.assertEquals('dev1b', saved.Branch__c, 'The edit is saved');
            System.assertEquals(RlyTestData.CONSUMER_KEY, saved.Consumer_Key__c, 'A blank key keeps the saved key');

            edited.put('Consumer_Key__c', '3MVG9otherKeyAbcd');
            RlyOrgController.saveOrg(JSON.serialize(edited));
            System.assertEquals('3MVG9otherKeyAbcd', keys(orgId).Consumer_Key__c, 'A new key replaces it');
        }
    }

    @IsTest
    static void newOrgNeedsAKey() {
        System.runAs(RlyTestData.admin()) {
            Map<String, Object> fields = input('DEV1');
            fields.remove('Consumer_Key__c');
            String message;
            try {
                RlyOrgController.saveOrg(JSON.serialize(fields));
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
            System.assertNotEquals(null, message, 'A new org without a key is refused');
            List<String> problems = RlyOrgValidator.validate(new RLY_Org__c(Name = 'DEV1', Role__c = 'Developer',
                My_Domain__c = 'https://demo.my.salesforce.com', Login_Type__c = 'Production', Username__c = 'relay@demo.dev',
                Certificate__c = 'release_relay'), null);
            System.assertEquals(1, problems.size(), 'Only the key is missing: ' + problems);
            System.assert(problems[0].startsWith('Consumer key is required'), problems[0]);
        }
    }

    @IsTest
    static void checkMigratesTheOldClientId() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c legacy = RlyTestData.org('DEV1', 'Developer', 'dev1');
            legacy.Consumer_Key__c = null;
            legacy.Client_Id__c = '3MVG9legacyKeyWxyz';
            insert legacy;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyOrgCheckMock());
            Test.startTest();
            RLY_Org__c checked = RlyOrgController.checkOrg(legacy.Id);
            Test.stopTest();
            RLY_Org__c saved = keys(legacy.Id);
            System.assertEquals('3MVG9legacyKeyWxyz', saved.Consumer_Key__c, 'Moved to the encrypted field');
            System.assertEquals(null, saved.Client_Id__c, 'Cleared from the old field in the same save');
            Map<String, Object> returned = checked.getPopulatedFieldsAsMap();
            System.assert(!returned.containsKey('Consumer_Key__c') && !returned.containsKey('Client_Id__c'), 'The check returns no key');
            System.assertEquals('Connected', checked.Status__c, 'Signed in: ' + checked.Status_Message__c);
        }
    }

    @IsTest
    static void getOrgsNeverSendsTheKey() {
        System.runAs(RlyTestData.admin()) {
            Id orgId = RlyOrgController.saveOrg(JSON.serialize(input('DEV1')));
            RlyOrgController.PipelineOrgs p = RlyOrgController.getOrgs();
            Map<String, Object> fields = p.orgs[0].getPopulatedFieldsAsMap();
            System.assert(!fields.containsKey('Consumer_Key__c') && !fields.containsKey('Client_Id__c'), 'No key fields on the orgs');
            System.assert(!JSON.serialize(p).contains(RlyTestData.CONSUMER_KEY), 'The key is nowhere in what the page gets');
            System.assertEquals(RlyTestData.KEY_HINT, p.keyHints.get(orgId), 'A masked hint instead');
        }
    }

    @IsTest
    static void signInUsesTheOldFieldUntilMigrated() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c o = new RLY_Org__c(Name = 'DEV1', Client_Id__c = ' 3MVG9legacyKeyWxyz ');
            System.assertEquals('3MVG9legacyKeyWxyz', RlyOrgSession.consumerKey(o), 'Falls back to Client_Id__c');
            System.assertEquals('••••••••Wxyz', RlyOrgSession.keyHint(o), 'Hint from the old field');
            o.Consumer_Key__c = RlyTestData.CONSUMER_KEY;
            System.assertEquals(RlyTestData.CONSUMER_KEY, RlyOrgSession.consumerKey(o), 'Consumer_Key__c wins');
            System.assertEquals(null, RlyOrgSession.keyHint(new RLY_Org__c(Name = 'DEV2')), 'No key, no hint');
            System.assertEquals('••••••••', RlyOrgSession.keyHint(new RLY_Org__c(Consumer_Key__c = 'abc')), 'A short key shows no characters');
        }
    }
}
