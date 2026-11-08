/**
 * @description Tests for Install Release Relay update (RlyRelayUpdateController, RlyRelayUpdateRuns, RlyRelayUpdateGit,
 * RlyRelayUpdateZip, RlyRelayUpdateResults, RlyRelayUpdateState, RlyRelayUpdateView, RlyRelayUpdateStore): preparing an
 * update from a zip built here (Compression.ZipWriter), the signed check and install dispatches, the zip copied without
 * downloading it (GitHub git data, GitLab cherry-pick and move), results read from signed files, the step order, and
 * admins only. Every test runs as an active System Administrator through System.runAs; callouts are mocked; DML comes
 * before Test.startTest and the callouts after it.
 */
@IsTest
private class RlyRelayUpdateTest {

    private static final String KEY = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
    private static final String REQ = 'REL-1762560014233';
    private static final String HEAD = '0123456789abcdef0123456789abcdef01234567';
    private static final String ZIP_LIST = '[{"type":"file","name":"build52.zip","path":".relay-inbox/build52.zip","sha":"b10b5a","size":1200},'
        + '{"type":"file","name":"notes.txt","path":".relay-inbox/notes.txt","sha":"n1","size":10}]';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    /** @description Answers the zip's bytes for a blob download, everything else from the table. */
    private class ZipMock implements HttpCalloutMock {
        private final RlyHttpMock table;
        private final Blob zip;

        /**
         * @description A mock.
         * @param table the other answers
         * @param zip the zip's bytes
         */
        ZipMock(RlyHttpMock table, Blob zip) {
            this.table = table;
            this.zip = zip;
        }

        /**
         * @description Answers a callout.
         * @param req the request
         * @return the answer
         */
        public HttpResponse respond(HttpRequest req) {
            if (req.getEndpoint().contains('/blobs/')) {
                table.calls.add(req.getMethod() + ' ' + req.getEndpoint());
                HttpResponse res = new HttpResponse();
                res.setStatusCode(200);
                res.setBodyAsBlob(zip);
                return res;
            }
            return table.respond(req);
        }
    }

    private static Blob buildZip() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('package.xml', Blob.valueOf('<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata">'
            + '<types><members>RlyFoo</members><members>RlyFooTest</members><name>ApexClass</name></types>'
            + '<types><members>RLY_X__c</members><members>*</members><name>CustomObject</name></types><version>63.0</version></Package>'));
        writer.addEntry('classes/RlyFoo.cls', Blob.valueOf('public class RlyFoo {}'));
        writer.addEntry('classes/RlyFooTest.cls', Blob.valueOf('@IsTest private class RlyFooTest {}'));
        writer.addEntry('classes/RlyFooTest.cls-meta.xml', Blob.valueOf('<ApexClass/>'));
        return writer.getArchive();
    }

    private static void saveKey() {
        insert new RLY_Run_Key__c(SetupOwnerId = UserInfo.getOrganizationId(), Key__c = KEY, Set_By__c = 'Test', Set_On__c = System.now());
    }

    private static Id stageId() {
        return [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
    }

    private static RlyRelayUpdateState.Step step(String requestId, String status, String token) {
        RlyRelayUpdateState.Step s = new RlyRelayUpdateState.Step();
        s.requestId = requestId;
        s.branch = 'feature/rly-update-' + requestId.toLowerCase();
        s.target = 'rly-sit-install';
        s.environment = 'sit';
        s.status = status;
        s.token = token;
        s.startedAt = System.now().addMinutes(-5);
        return s;
    }

    private static RLY_Relay_Update__c updateWith(Map<String, RlyRelayUpdateState.Step> steps) {
        RLY_Relay_Update__c u = new RLY_Relay_Update__c(Branch__c = 'feature/relay-build-52', Title__c = 'Build 52', Test_Org__c = stageId(),
            Zip_Path__c = '.relay-inbox/build52.zip', Zip_Sha__c = 'b10b5a', Tests__c = 'RlyFooTest', Tests_From__c = 'zip',
            Components__c = 'ApexClass:RlyFoo');
        RlyRelayUpdateState.write(u, steps);
        return u;
    }

    private static String signed(String requestId, String step, Map<String, Object> payload) {
        String text = JSON.serialize(payload);
        return JSON.serialize(new Map<String, Object>{ 'payload' => text, 'sig' => RlyRunSigning.mac(KEY, RlyResultSignature.canonical(requestId, step, text)) });
    }

    // A finished check run (mode hub) with a conclusion.
    private static String runs(String requestId, String conclusion) {
        return JSON.serialize(new Map<String, Object>{ 'workflow_runs' => new List<Object>{ new Map<String, Object>{ 'id' => 42,
            'html_url' => 'https://github.com/acme/release/actions/runs/42', 'display_title' => 'Release Relay ' + requestId + ' (hub) · x',
            'status' => 'completed', 'conclusion' => conclusion } } });
    }

    private static Map<String, Object> inputsOf(RlyHttpMock mock) {
        return (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'))).get('inputs');
    }

    @IsTest
    static void preparesFromTheZip() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHttpMock table = new RlyHttpMock().match('GET', '/contents/.relay-inbox').reply(200, ZIP_LIST);
            Test.setMock(HttpCalloutMock.class, new ZipMock(table, buildZip()));
            Id sit = stageId();
            Test.startTest();
            RlyRelayUpdateView.Card card = RlyRelayUpdateController.prepare(new Map<String, String>{ 'branch' => ' feature/relay-build-52 ',
                'title' => 'Build 52', 'testOrgId' => sit, 'testsFrom' => 'zip' });
            Test.stopTest();
            RLY_Relay_Update__c u = RlyRelayUpdateStore.current();
            System.assertEquals('feature/relay-build-52', u.Branch__c, 'The branch, trimmed');
            System.assertEquals('.relay-inbox/build52.zip', u.Zip_Path__c, 'The one zip (other files left out)');
            System.assertEquals('b10b5a', u.Zip_Sha__c, 'Its Git object');
            System.assertEquals('RlyFooTest', u.Tests__c, 'The zip\'s test classes');
            System.assertEquals('zip', card.current.testsFrom, 'Tests came from the zip');
            System.assertEquals('ApexClass:RlyFoo,ApexClass:RlyFooTest,CustomObject:RLY_X__c', u.Components__c, 'package.xml members, no wildcard');
            System.assert(card.current.steps[0].startable && !card.current.steps[1].startable, 'Only the first step opens on a prepared update');
            System.assertEquals('SIT check', card.current.steps[0].label, 'Labels come from the route');
            System.assertEquals('PROD install', card.current.steps[3].label, 'Production is the hub org');
        }
    }

    @IsTest
    static void startsTheTestCheckSigned() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            saveKey();
            insert updateWith(new Map<String, RlyRelayUpdateState.Step>());
            RlyHttpMock table = new RlyHttpMock()
                .match('GET', '/git/ref/heads/rly-sit-install').reply(200, '{"object":{"sha":"head1"}}')
                .match('GET', '/git/commits/head1').reply(200, '{"tree":{"sha":"tree1"}}')
                .match('POST', '/git/trees').reply(201, '{"sha":"tree2"}')
                .match('POST', '/git/commits').reply(201, '{"sha":"commit2"}')
                .match('POST', '/git/refs').reply(201, '{"ref":"x"}')
                .match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, table);
            Test.startTest();
            RlyRelayUpdateView.Card card = RlyRelayUpdateController.start(RlyRelayUpdateState.TEST_CHECK);
            Test.stopTest();
            Map<String, Object> inputs = inputsOf(table);
            String options = String.valueOf(inputs.get('options'));
            System.assertEquals('hub', inputs.get('mode'), 'A check runs in mode hub');
            System.assertEquals('rly-sit-install', inputs.get('target'), 'The test org\'s install branch');
            System.assertEquals('sit', inputs.get('environment'), 'The test org\'s Git environment');
            System.assert(String.valueOf(inputs.get('request_id')).startsWith('REL-'), 'A REL id');
            System.assert(String.valueOf(inputs.get('branch')).startsWith('feature/rly-update-rel-'), 'The hub\'s own branch');
            System.assertEquals('ApexClass:RlyFoo', inputs.get('components'), 'The update\'s components');
            System.assert(options.contains('"selfUpdate":true') && options.contains('"tests":["RlyFooTest"]'), 'selfUpdate and the tests: ' + options);
            System.assert(options.contains('"sig":"'), 'The run is signed');
            System.assert(table.bodyFor('/git/trees').contains('"sha":"b10b5a"') && table.bodyFor('/git/trees').contains('.relay-inbox/REL-'),
                'The zip\'s object is put under the request id');
            System.assertEquals(RlyRelayUpdateState.RUNNING, card.current.steps[0].status, 'Running');
            System.assert(card.current.running && !card.current.steps[1].startable, 'Nothing else starts while it runs');
            System.assertEquals(1, [SELECT COUNT() FROM RLY_Settings_Change__c WHERE Section__c = 'Advanced' AND What__c LIKE 'Install update%'],
                'The start is logged');
        }
    }

    @IsTest
    static void refreshReadsTheSignedCheckResult() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            saveKey();
            RLY_Relay_Update__c u = updateWith(new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step(REQ, RlyRelayUpdateState.RUNNING, 'tok1') });
            insert u;
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/runs?event=workflow_dispatch').reply(200, runs(REQ, 'success'))
                .match('GET', 'results/' + REQ + '/validate.json').reply(200, signed(REQ, 'validate', new Map<String, Object>{
                    'status' => 'Passed', 'attempt' => 'tok1', 'testsRun' => 576, 'headSha' => HEAD, 'testFailures' => new List<Object>(),
                    'runUrl' => 'https://github.com/acme/release/actions/runs/42', 'finishedAt' => '2026-11-08T00:38:43.858Z' }));
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyRelayUpdateView.Card card = RlyRelayUpdateController.refresh();
            Test.stopTest();
            RlyRelayUpdateView.StepView checkStep = card.current.steps[0];
            System.assertEquals(RlyRelayUpdateState.PASSED, checkStep.status, 'The check passed');
            System.assertEquals(576, checkStep.testsRun, 'Tests run');
            System.assertEquals('https://github.com/acme/release/actions/runs/42', checkStep.runUrl, 'The run link');
            System.assert(card.current.steps[1].startable, 'The install opens once the check passed');
            System.assert(!card.current.steps[2].startable, 'Production waits for the test install');
            System.assertEquals(HEAD, RlyRelayUpdateState.read(RlyRelayUpdateStore.current()).get(RlyRelayUpdateState.TEST_CHECK).head,
                'The validated head is kept for the install');
        }
    }

    @IsTest
    static void installMergesPinnedToTheCheck() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyRelayUpdateState.Step check = step(REQ, RlyRelayUpdateState.PASSED, 'tok1');
            check.head = HEAD;
            insert updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => check });
            RlyHttpMock mock = new RlyHttpMock().match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyRelayUpdateView.Card card = RlyRelayUpdateController.start(RlyRelayUpdateState.TEST_INSTALL);
            Test.stopTest();
            Map<String, Object> inputs = inputsOf(mock);
            String options = String.valueOf(inputs.get('options'));
            System.assertEquals('merge', inputs.get('mode'), 'An install merges');
            System.assertEquals(REQ, inputs.get('request_id'), 'With its check\'s id');
            System.assertEquals('', inputs.get('components'), 'No components for a merge');
            System.assert(options.contains('"validationAttempt":"tok1"') && options.contains('"expectHead":"' + HEAD + '"'), 'Pinned to the check: ' + options);
            System.assertEquals(RlyRelayUpdateState.RUNNING, card.current.steps[1].status, 'The install runs');
        }
    }

    @IsTest
    static void productionCheckCopiesTheSameZipFromTheHubBranch() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            insert updateWith(new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step(REQ, RlyRelayUpdateState.PASSED, 'tok1'),
                RlyRelayUpdateState.TEST_INSTALL => step(REQ, RlyRelayUpdateState.INSTALLED, 'tok2') });
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/git/ref/heads/release-relay-hub').reply(200, '{"object":{"sha":"hub1"}}')
                .match('GET', '/git/commits/hub1').reply(200, '{"tree":{"sha":"tree1"}}')
                .match('POST', '/git/trees').reply(201, '{"sha":"tree2"}')
                .match('POST', '/git/commits').reply(201, '{"sha":"commit2"}')
                .match('POST', '/git/refs').reply(201, '{}')
                .match('POST', '/dispatches').reply(204, '');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyRelayUpdateController.start(RlyRelayUpdateState.PROD_CHECK);
            Test.stopTest();
            Map<String, Object> inputs = inputsOf(mock);
            System.assertEquals(RlyRelayUpdateRuns.PROD_TARGET, inputs.get('target'), 'Production\'s target');
            System.assertEquals('prod', inputs.get('environment'), 'The hub\'s Git environment');
            System.assertNotEquals(REQ, inputs.get('request_id'), 'Its own request id');
            System.assert(mock.bodyFor('/git/trees').contains('"sha":"b10b5a"'), 'The same zip object the test org checked');
        }
    }

    @IsTest
    static void failuresAndRunsWithoutResults() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/runs?event=workflow_dispatch').reply(200, runs('REL-1', 'failure'))
                .match('GET', 'results/REL-2/validate.json').reply(200, JSON.serialize(new Map<String, Object>{ 'status' => 'Failed', 'attempt' => 't2',
                    'testsRun' => 10, 'message' => '2 test failure(s)', 'runUrl' => 'http://not-https.example',
                    'testFailures' => new List<Object>{ new Map<String, Object>{ 'name' => 'RlyFooTest', 'method' => 'works', 'message' => 'Assertion Failed' } },
                    'componentErrors' => new List<Object>{ new Map<String, Object>{ 'type' => 'ApexClass', 'name' => 'RlyFoo', 'line' => 3, 'problem' => 'Bad' } } }))
                .match('GET', 'results/REL-3/raise.json').reply(200, '{"status":"Failed","attempt":"t3","message":"No zip on the branch"}')
                .match('GET', 'results/REL-4/deploy.json').reply(200, '{"status":"Deployed","attempt":"t4","testsRun":0}')
                .match('GET', 'results/REL-5/validate.json').reply(200, '{"status":"Passed","attempt":"other"}');
            Test.setMock(HttpCalloutMock.class, mock);
            RLY_Relay_Update__c noResult = updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => step('REL-1', RlyRelayUpdateState.RUNNING, 't1') });
            RLY_Relay_Update__c failed = updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => step('REL-2', RlyRelayUpdateState.RUNNING, 't2') });
            RLY_Relay_Update__c raiseFailed = updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => step('REL-3', RlyRelayUpdateState.RUNNING, 't3') });
            RLY_Relay_Update__c installed = updateWith(new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step('REL-4', RlyRelayUpdateState.PASSED, 't0'),
                RlyRelayUpdateState.TEST_INSTALL => step('REL-4', RlyRelayUpdateState.RUNNING, 't4') });
            RLY_Relay_Update__c earlier = updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => step('REL-5', RlyRelayUpdateState.RUNNING, 't5') });
            Test.startTest();
            RlyRelayUpdateResults.refresh(noResult);
            RlyRelayUpdateResults.refresh(failed);
            RlyRelayUpdateResults.refresh(raiseFailed);
            RlyRelayUpdateResults.refresh(installed);
            RlyRelayUpdateResults.refresh(earlier);
            String idle = RlyRelayUpdateResults.refresh(updateWith(new Map<String, RlyRelayUpdateState.Step>()));
            Test.stopTest();
            RlyRelayUpdateState.Step a = RlyRelayUpdateState.read(noResult).get(RlyRelayUpdateState.TEST_CHECK);
            RlyRelayUpdateState.Step b = RlyRelayUpdateState.read(failed).get(RlyRelayUpdateState.TEST_CHECK);
            System.assertEquals(RlyRelayUpdateState.FAILED, a.status, 'A finished run without a result fails the step');
            System.assert(a.message.contains('failure'), 'With the run\'s conclusion: ' + a.message);
            System.assertEquals(RlyRelayUpdateState.FAILED, b.status, 'A failed validation');
            System.assertEquals(2, b.failures.size(), 'The test failure and the component error');
            System.assertEquals('RlyFooTest.works: Assertion Failed', b.failures[0], 'Class.method: message');
            System.assertEquals('ApexClass RlyFoo (line 3): Bad', b.failures[1], 'Type name (line): problem');
            System.assertEquals(null, b.runUrl, 'Links only when https');
            System.assertEquals('No zip on the branch', RlyRelayUpdateState.read(raiseFailed).get(RlyRelayUpdateState.TEST_CHECK).message, 'A failed raise fails the check');
            System.assertEquals(RlyRelayUpdateState.INSTALLED, RlyRelayUpdateState.read(installed).get(RlyRelayUpdateState.TEST_INSTALL).status, 'Deployed is installed');
            System.assertEquals(RlyRelayUpdateState.RUNNING, RlyRelayUpdateState.read(earlier).get(RlyRelayUpdateState.TEST_CHECK).status, 'Another run\'s result is ignored');
            System.assertEquals(null, idle, 'Nothing runs, nothing read');
            RlyRelayUpdateView.Card card = RlyRelayUpdateView.build();
            System.assert(card.visible && card.stages.size() == 1, 'One stage to test in');
        }
    }

    @IsTest
    static void unsignedResultsAreRejectedWithAKey() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            saveKey();
            RlyHttpMock mock = new RlyHttpMock().match('GET', 'results/REL-7/validate.json').reply(200, '{"status":"Passed","attempt":"t7"}');
            Test.setMock(HttpCalloutMock.class, mock);
            RLY_Relay_Update__c u = updateWith(new Map<String, RlyRelayUpdateState.Step>{ RlyRelayUpdateState.TEST_CHECK => step('REL-7', RlyRelayUpdateState.RUNNING, 't7') });
            Test.startTest();
            RlyRelayUpdateResults.refresh(u);
            Test.stopTest();
            RlyRelayUpdateState.Step s = RlyRelayUpdateState.read(u).get(RlyRelayUpdateState.TEST_CHECK);
            System.assertEquals(RlyRelayUpdateState.RUNNING, s.status, 'An unsigned result never moves the step');
            System.assert(s.message.startsWith(RlyResultSignature.REJECTED), 'It says why');
        }
    }

    @IsTest
    static void stepsRunInOrder() {
        System.runAs(RlyTestData.admin()) {
            Map<String, RlyRelayUpdateState.Step> none = new Map<String, RlyRelayUpdateState.Step>();
            Map<String, RlyRelayUpdateState.Step> checkFailed = new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step(REQ, RlyRelayUpdateState.FAILED, 't') };
            Map<String, RlyRelayUpdateState.Step> installFailed = new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step(REQ, RlyRelayUpdateState.PASSED, 't'),
                RlyRelayUpdateState.TEST_INSTALL => step(REQ, RlyRelayUpdateState.FAILED, 't2') };
            Map<String, RlyRelayUpdateState.Step> running = new Map<String, RlyRelayUpdateState.Step>{
                RlyRelayUpdateState.TEST_CHECK => step(REQ, RlyRelayUpdateState.RUNNING, 't') };
            Test.startTest();
            Boolean firstOpen = RlyRelayUpdateState.canStart(none, RlyRelayUpdateState.TEST_CHECK);
            Boolean secondClosed = RlyRelayUpdateState.canStart(none, RlyRelayUpdateState.TEST_INSTALL);
            Boolean retry = RlyRelayUpdateState.canRetryFirst(checkFailed);
            Boolean installAgain = RlyRelayUpdateState.canStart(installFailed, RlyRelayUpdateState.TEST_INSTALL);
            Boolean checkAgainClosed = RlyRelayUpdateState.canStart(installFailed, RlyRelayUpdateState.TEST_CHECK);
            Boolean whileRunning = RlyRelayUpdateState.canStart(running, RlyRelayUpdateState.TEST_INSTALL);
            Boolean unknown = RlyRelayUpdateState.canStart(none, 'deploy');
            Map<String, RlyRelayUpdateState.Step> unreadable = RlyRelayUpdateState.read(new RLY_Relay_Update__c(Steps__c = 'not json'));
            Test.stopTest();
            System.assert(firstOpen && !secondClosed, 'Only the first step opens on a new update');
            System.assert(retry, 'A failed first step runs again on a new update');
            System.assert(installAgain, 'A failed install runs again');
            System.assert(!checkAgainClosed, 'An earlier step doesn\'t start once a later one has');
            System.assert(!whileRunning, 'Nothing starts while a step runs');
            System.assert(!unknown, 'Unknown steps never start');
            System.assert(unreadable.isEmpty(), 'Unreadable steps read as none');
            System.assertEquals(RlyRelayUpdateState.PROD_CHECK, RlyRelayUpdateState.checkOf(RlyRelayUpdateState.PROD_INSTALL), 'Production install merges production check');
        }
    }

    @IsTest
    static void readsTheZip() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyRelayUpdateZip.Contents c = RlyRelayUpdateZip.read(buildZip());
            String nested = RlyRelayUpdateZip.testName('hub/classes/RlyBarTest.cls');
            String notTest = RlyRelayUpdateZip.testName('classes/RlyTestData.cls');
            String meta = RlyRelayUpdateZip.testName('classes/RlyFooTest.cls-meta.xml');
            String joined = RlyRelayUpdateZip.joined(new List<String>{ 'ApexClass:A', 'ApexClass:B', 'ApexClass:Ccccc' }, 25);
            Test.stopTest();
            System.assertEquals(new List<String>{ 'RlyFooTest' }, c.tests, 'Only *Test classes, not their meta files');
            System.assertEquals(3, c.components.size(), 'Members without the wildcard');
            System.assertEquals('RlyBarTest', nested, 'A zip with a top folder');
            System.assertEquals(null, notTest, 'A class that doesn\'t end in Test');
            System.assertEquals(null, meta, 'A meta file');
            System.assertEquals('ApexClass:A,ApexClass:B', joined, 'Whole entries within the limit');
        }
    }

    @IsTest
    static void gitLabCopiesWithCherryPickAndMove() {
        System.runAs(RlyTestData.admin()) {
            RlyHttpMock table = new RlyHttpMock()
                .match('GET', '/repository/tree').reply(200, '[{"type":"blob","name":"build52.zip","path":".relay-inbox/build52.zip","id":"g1"}]')
                .match('GET', '/repository/commits?ref_name').reply(200, '[{"id":"c1"}]')
                .match('POST', '/repository/branches').reply(201, '{}')
                .match('POST', '/cherry_pick').reply(201, '{}')
                .match('POST', '/repository/commits').reply(201, '{}');
            Test.setMock(HttpCalloutMock.class, new ZipMock(table, buildZip()));
            RlyGit git = RlyGit.forConnection(new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/release',
                Named_Credential__c = 'RLY_GitLab', Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main'));
            Test.startTest();
            RlyRelayUpdateGit g = new RlyRelayUpdateGit(git);
            RlyRelayUpdateGit.ZipFile z = g.findZip('feature/relay-build-52');
            Blob zip = g.download(z);
            RlyRelayUpdateState.Step s = new RlyRelayUpdateState.Step();
            s.requestId = 'REL-1';
            s.branch = 'feature/rly-update-rel-1';
            s.target = 'release-relay-hub';
            g.copyTo(z, s);
            Boolean bitbucket = RlyRelayUpdateGit.supports('Bitbucket');
            Test.stopTest();
            System.assertEquals('c1', z.commitSha, 'The commit that added the zip');
            System.assertEquals(1, RlyRelayUpdateZip.read(zip).tests.size(), 'The zip was downloaded');
            System.assert(table.callLog().contains('/repository/commits/c1/cherry_pick'), 'Cherry-picked onto the new branch: ' + table.callLog());
            System.assert(table.bodyFor('/repository/commits').contains('"action":"move"'), 'Renamed without its content');
            System.assert(!bitbucket, 'Bitbucket isn\'t supported yet');
        }
    }

    @IsTest
    static void prepareChecksItsInputs() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyHttpMock table = new RlyHttpMock().match('GET', '/contents/.relay-inbox').reply(404, '{}');
            Test.setMock(HttpCalloutMock.class, table);
            Id sit = stageId();
            List<String> errors = new List<String>();
            Test.startTest();
            for (Map<String, String> form : new List<Map<String, String>>{
                new Map<String, String>{ 'branch' => 'bad branch', 'title' => 'x', 'testOrgId' => sit },
                new Map<String, String>{ 'branch' => 'feature/x', 'title' => '', 'testOrgId' => sit },
                new Map<String, String>{ 'branch' => 'feature/x', 'title' => 'x', 'testOrgId' => '' },
                new Map<String, String>{ 'branch' => 'feature/x', 'title' => 'x', 'testOrgId' => sit, 'testsFrom' => 'org' } }) {
                try {
                    RlyRelayUpdateController.prepare(form);
                    errors.add('none');
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
            List<String> orgTests = RlyRelayUpdateStore.orgTestClasses();
            Test.stopTest();
            System.assert(errors[0].contains('update branch'), 'Branch checked: ' + errors[0]);
            System.assert(errors[1].contains('title'), 'Title checked: ' + errors[1]);
            System.assert(errors[2].contains('Pick the org'), 'Org checked: ' + errors[2]);
            System.assert(errors[3].contains('relay-inbox'), 'No zip on the branch: ' + errors[3]);
            System.assert(orgTests.contains('RlyRelayUpdateTest'), 'The org\'s own Release Relay test classes');
        }
    }

    @IsTest
    static void adminsOnly() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            Test.startTest();
            RlyRelayUpdateView.Card card = RlyRelayUpdateController.state();
            String refused;
            try {
                RlyRelayUpdateController.start(RlyRelayUpdateState.TEST_CHECK);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assert(!card.visible && card.current == null, 'The card isn\'t shown to anyone else');
            System.assert(refused != null && refused.contains('Only Release Relay admins'), 'Starting is refused: ' + refused);
        }
    }
}
