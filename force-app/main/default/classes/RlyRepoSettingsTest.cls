/**
 * @description Tests for the Pipeline tab's Per-org values and Quality gates cards: RlyRepoSettings.read and
 * RlyRepoParse. Every test runs as an existing active System Administrator through System.runAs. DML happens before
 * Test.startTest; callouts after it.
 */
@IsTest
private class RlyRepoSettingsTest {

    private static final String VALUES_URL = '/repos/acme/release/contents/.relay/values.json?ref=main';
    private static final String GATES_URL = '/repos/acme/release/contents/.relay/gates.json?ref=main';
    private static final String HELP_ONLY = '{"_help":"Read from the pipeline branch."}';

    private static void connect(String provider) {
        insert new RLY_Git_Connection__c(Provider__c = provider, Repository__c = 'acme/release', Named_Credential__c = 'RLY_Git',
            Pipeline__c = 'release-relay.yml', Pipeline_Branch__c = 'main', Source_Path__c = 'force-app/main/default',
            Code_Scan__c = true, Status__c = 'Connected');
    }

    private static RlyRepoSettings.Settings readWith(String valuesBody, String gatesBody) {
        RlyHttpMock mock = new RlyHttpMock();
        if (valuesBody != null) {
            mock.match('GET', VALUES_URL).reply(200, valuesBody);
        }
        if (gatesBody != null) {
            mock.match('GET', GATES_URL).reply(200, gatesBody);
        }
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        RlyRepoSettings.Settings s = RlyRepoSettings.read();
        Test.stopTest();
        return s;
    }

    private static Map<String, RlyRepoSettings.GateRow> byKey(List<RlyRepoSettings.GateRow> rows) {
        Map<String, RlyRepoSettings.GateRow> out = new Map<String, RlyRepoSettings.GateRow>();
        for (RlyRepoSettings.GateRow r : rows) {
            out.put(r.key, r);
        }
        return out;
    }

    @IsTest
    static void valuesAndGates() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            String valuesBody = '{"_help":"x","values":{"_HIDDEN":{"dev1":"a"},'
                + '"PAYMENT_URL":{"dev1":"https://dev.pay.example","sit":"https://sit.pay.example","prod":"https://pay.example","_note":"n"},'
                + '"PARTNER_KEY_HINT":{"dev1":"8f3a2c9d01b7aa00e91b","uat":"55d01a7e44c2","sit":12},"BROKEN":"text"}}';
            String gatesBody = '{"_help":"x","scan":{"failAtPriority":2},"coverage":{"minimumPerClass":75.5},"tests":{"requireForApex":true}}';
            RlyRepoSettings.Settings s = readWith(valuesBody, gatesBody);
            System.assertEquals(null, s.message, s.message);
            System.assertEquals('main', s.branch, 'Pipeline branch');
            System.assertNotEquals(null, s.readAt, 'Read time');
            System.assertEquals(2, s.values.size(), 'Named values, _ names and non-objects left out');
            Map<String, RlyRepoSettings.ValueRow> rows = new Map<String, RlyRepoSettings.ValueRow>();
            for (RlyRepoSettings.ValueRow r : s.values) {
                rows.put(r.name, r);
            }
            System.assertEquals(3, rows.get('PAYMENT_URL').byEnvironment.size(), '_ environments left out');
            System.assertEquals('https://sit.pay.example', rows.get('PAYMENT_URL').byEnvironment.get('sit'), 'Value per environment');
            System.assert(!rows.get('PARTNER_KEY_HINT').byEnvironment.containsKey('sit'), 'A value that isn\'t text is left out');
            System.assertEquals(4, s.environments.size(), 'Every environment once: ' + s.environments);
            System.assert(new Set<String>(s.environments).containsAll(new List<String>{ 'dev1', 'sit', 'prod', 'uat' }), 'Environments');
            Map<String, RlyRepoSettings.GateRow> gates = byKey(s.gates);
            System.assertEquals(4, s.gates.size(), 'Four gates');
            System.assertEquals('Fails at priority 2 or higher (1 = most serious)', gates.get('scan').text, 'Scan gate');
            System.assert(gates.get('scan').isSet, 'Scan set');
            System.assertEquals('Each deployed Apex class ≥ 75.5%', gates.get('perClass').text, 'Coverage per class');
            System.assert(!gates.get('orgWide').isSet, 'Org-wide not set');
            System.assert(gates.get('orgWide').text.contains('75% in production'), gates.get('orgWide').text);
            System.assertEquals('Required when a release has Apex', gates.get('tests').text, 'Tests for Apex');
        }
    }

    @IsTest
    static void emptyFiles() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            RlyRepoSettings.Settings s = readWith('{"_help":"x","values":{}}', HELP_ONLY);
            System.assert(s.values.isEmpty(), 'No values');
            System.assert(s.environments.isEmpty(), 'No environments');
            System.assert(s.gates.isEmpty(), 'Only _ keys: no gates');
            System.assertEquals(null, s.valuesError, 'Valid file');
            System.assertEquals(null, s.gatesError, 'Valid file');
        }
    }

    @IsTest
    static void missingFiles() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            RlyRepoSettings.Settings s = readWith(null, null);
            System.assertEquals(null, s.message, 'A missing file is just empty');
            System.assert(s.values.isEmpty() && s.gates.isEmpty(), 'Empty cards');
        }
    }

    @IsTest
    static void invalidFiles() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            String gatesBody = '{"scan":{"failAtPriority":2.5},"coverage":{"minimumPerClass":120,"minimumOrgWide":"75"},"tests":{"requireForApex":"yes"}}';
            RlyRepoSettings.Settings s = readWith('{"values": [1, 2', gatesBody);
            System.assert(s.valuesError.startsWith(RlyRepoSettings.VALUES_PATH), s.valuesError);
            System.assert(s.values.isEmpty(), 'No rows from a broken file');
            Map<String, RlyRepoSettings.GateRow> gates = byKey(s.gates);
            System.assert(gates.get('scan').text.startsWith('Not valid'), gates.get('scan').text);
            System.assert(gates.get('perClass').text.startsWith('Not valid'), gates.get('perClass').text);
            System.assert(gates.get('orgWide').text.startsWith('Not valid'), gates.get('orgWide').text);
            System.assert(!gates.get('tests').isSet, 'requireForApex must be true');
        }
    }

    @IsTest
    static void gatesNotAnObject() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            RlyRepoSettings.Settings s = readWith('{"values":{"A_NAME":{"sit":"value-1"}}}', '[1]');
            System.assert(s.gatesError.startsWith(RlyRepoSettings.GATES_PATH), s.gatesError);
            System.assertEquals(1, s.values.size(), 'Values still shown');
        }
    }

    @IsTest
    static void noConnection() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyRepoSettings.Settings s = RlyRepoSettings.read();
            Test.stopTest();
            System.assert(s.message.startsWith('No Git connection yet'), s.message);
            System.assertEquals(null, s.branch, 'No branch');
        }
    }

    @IsTest
    static void providerError() {
        System.runAs(RlyTestData.admin()) {
            connect('GitHub');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', VALUES_URL).reply(500, '{"message":"Server error"}'));
            Test.startTest();
            RlyRepoSettings.Settings s = RlyRepoSettings.read();
            Test.stopTest();
            System.assert(s.message.startsWith('Couldn\'t read'), s.message);
        }
    }
}
