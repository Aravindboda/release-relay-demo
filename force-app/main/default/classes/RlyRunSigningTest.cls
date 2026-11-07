/**
 * @description Tests for run signing and signed results (build 48: RlyRunSigning, RlyRunKeyStore, RlyResultSignature,
 * RlyRunSigningController): the shared test vectors (scratchpad b48-vector.json, the same the pipeline's node test
 * checks), every pipeline start signed through RlyGit, results verified (valid, tampered, missing with and without a
 * key), a rejected result leaving the release where it was, and the validated head sent to the merge as expectHead.
 * Every test runs as an active System Administrator through System.runAs; callouts are mocked (RlyHttpMock).
 */
@IsTest
private class RlyRunSigningTest {

    private static final String KEY = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
    private static final Long IAT = 1794067200L;
    private static final String HEAD = '0123456789abcdef0123456789abcdef01234567';
    private static final String RESULT_VALIDATE = '{"payload":"{\\"requestId\\":\\"REL-90001\\",\\"step\\":\\"validate\\",\\"status\\":\\"Passed\\",'
        + '\\"message\\":\\"Checked — \\\\\\"quoted\\\\\\" é\\",\\"attempt\\":2,\\"validatedTree\\":\\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\",'
        + '\\"headSha\\":\\"0123456789abcdef0123456789abcdef01234567\\",\\"testFailures\\":[],\\"runUrl\\":\\"https://github.com/o/r/actions/runs/1\\"}",'
        + '"sig":"4HEqdzvmJAo5tWB2BLXV2NVQ+QgNVPUdQ1oqqASivH8="}';
    private static final String RESULT_DEPLOY = '{"payload":"{\\"requestId\\":\\"REL-90001\\",\\"step\\":\\"deploy\\",\\"status\\":\\"Failed\\",'
        + '\\"message\\":\\"The release branch changed after validation; run the checks again.\\"}","sig":"0FXKQgZECeRTq9GmtCabnO3+SFVhFZzmKlPCulMaD4Y="}';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        RlyTestData.assignPermissionSet('RLY_Approver');
    }

    private static void saveKey() {
        insert new RLY_Run_Key__c(SetupOwnerId = UserInfo.getOrganizationId(), Key__c = KEY, Set_By__c = 'Test', Set_On__c = System.now());
    }

    private static Map<String, String> vectorOne() {
        return new Map<String, String>{ 'request_id' => 'REL-90001', 'mode' => 'deploy', 'environment' => 'release-relay-sit',
            'target_environment' => '', 'branch' => 'feature/rel-90001', 'target' => 'main',
            'title' => 'REL-90001: Fix provider search — "café" $HOME', 'components' => 'ApexClass:RlyFoo,ApexClass:RlyBar', 'deletions' => '',
            'options' => '{"tests":["RlyFooTest"],"attempt":2,"expectHead":"0123456789abcdef0123456789abcdef01234567"}' };
    }

    // A result file in the wrapper, signed with the test key.
    private static String signedFile(String requestId, String step, String payload) {
        return JSON.serialize(new Map<String, Object>{ 'payload' => payload,
            'sig' => RlyRunSigning.mac(KEY, RlyResultSignature.canonical(requestId, step, payload)) });
    }

    @IsTest
    static void signsTheSharedRunVectors() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Map<String, String> one = RlyRunSigning.sign(vectorOne(), KEY, IAT);
            String canonicalOne = RlyRunSigning.canonical(vectorOne(), vectorOne().get('options'), IAT);
            Map<String, String> two = RlyRunSigning.sign(new Map<String, String>{ 'request_id' => 'REL-90002', 'mode' => 'check',
                'environment' => 'release-relay-sit', 'target_environment' => '', 'branch' => 'feature/rel-90002', 'target' => '',
                'title' => 'Check', 'components' => '', 'deletions' => 'CustomField:Account.Old__c', 'options' => '{}' }, KEY, IAT);
            Map<String, String> blankOptions = RlyRunSigning.sign(new Map<String, String>{ 'request_id' => 'REL-90002', 'mode' => 'check',
                'environment' => 'release-relay-sit', 'branch' => 'feature/rel-90002', 'title' => 'Check',
                'deletions' => 'CustomField:Account.Old__c' }, KEY, IAT);
            Test.stopTest();
            System.assertEquals('{"tests":["RlyFooTest"],"attempt":2,"expectHead":"0123456789abcdef0123456789abcdef01234567","iat":1794067200,'
                + '"sig":"MxKHE1A6cjwpuBcxhEcavdAYtmhwYimojzVHiEuhIOI="}', one.get('options'), 'Vector 1: options sent, signature as the pipeline computes it');
            System.assertEquals('rr1\nREL-90001\ndeploy\nrelease-relay-sit\n\nfeature/rel-90001\nmain\nREL-90001: Fix provider search — "café" $HOME\n'
                + 'f05b21d7467d33c345523f2062f1959351a24ea0b4f096d7bebaac7ed3926a5d\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n'
                + 'b4ca6cce7150248d19eff0e3f7a943466270d602c5c06bc0ed7b1c0fd0369315\n1794067200', canonicalOne, 'Vector 1: canonical text');
            System.assertEquals('{"iat":1794067200,"sig":"HtL2UK2H63PVn+owztdvJ0us823rJYMri+FlLDSA/cQ="}', two.get('options'),
                'Vector 2: empty options get only iat and sig');
            System.assertEquals(two.get('options'), blankOptions.get('options'), 'Absent inputs are empty strings; blank options are {}');
            System.assertEquals('ApexClass:RlyFoo,ApexClass:RlyBar', one.get('components'), 'Other inputs unchanged');
        }
    }

    @IsTest
    static void verifiesTheSharedResultVectors() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyResultSignature.Opened validate = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(RESULT_VALIDATE, 'REL-90001', 'validate');
            RlyResultSignature.Opened deploy = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(RESULT_DEPLOY, 'REL-90001', 'deploy');
            RlyResultSignature.Opened tampered = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(RESULT_VALIDATE.replace('Passed', 'Failed'), 'REL-90001', 'validate');
            RlyResultSignature.Opened otherStep = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(RESULT_DEPLOY, 'REL-90001', 'merge');
            RlyResultSignature.Opened otherRelease = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(RESULT_DEPLOY, 'REL-90002', 'deploy');
            RlyResultSignature.Opened wrongKey = new RlyResultSignature.Checker(RlyRunSigning.newKey(), RlyResultSignature.MODE_STRICT).open(RESULT_DEPLOY, 'REL-90001', 'deploy');
            Test.stopTest();
            System.assert(validate.signed && !validate.rejected, 'Vector 1 verifies');
            System.assertEquals('Passed', validate.data.get('status'), 'Payload parsed after the check');
            System.assertEquals(HEAD, validate.data.get('headSha'), 'headSha read');
            System.assertEquals('Checked — "quoted" é', validate.data.get('message'), 'Non-ASCII and quotes kept');
            System.assert(deploy.signed && String.valueOf(deploy.data.get('status')) == 'Failed', 'Vector 2 verifies');
            System.assert(tampered.rejected && tampered.data == null, 'A changed payload is rejected');
            System.assert(otherStep.rejected, 'A result copied to another step is rejected');
            System.assert(otherRelease.rejected, 'A result copied to another release is rejected');
            System.assert(wrongKey.rejected, 'Another key is rejected');
        }
    }

    @IsTest
    static void missingSignaturesAreAcceptedOnlyWithoutAKey() {
        System.runAs(RlyTestData.admin()) {
            String plain = '{"status":"Passed","attempt":"t1"}';
            String unsignedWrapper = JSON.serialize(new Map<String, Object>{ 'payload' => plain });
            String badWrapper = JSON.serialize(new Map<String, Object>{ 'payload' => plain, 'sig' => 'AAAA' });
            Test.startTest();
            RlyResultSignature.Opened oldFileNoKey = new RlyResultSignature.Checker(null, RlyResultSignature.MODE_STRICT).open(plain, 'REL-1', 'validate');
            RlyResultSignature.Opened wrapperNoKey = new RlyResultSignature.Checker(null, RlyResultSignature.MODE_STRICT).open(RESULT_DEPLOY, 'REL-90001', 'deploy');
            RlyResultSignature.Opened oldFileWithKey = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(plain, 'REL-1', 'validate');
            RlyResultSignature.Opened unsignedWithKey = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open(unsignedWrapper, 'REL-1', 'validate');
            RlyResultSignature.Opened lenientMissing = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_LENIENT).open(unsignedWrapper, 'REL-1', 'migrate');
            RlyResultSignature.Opened lenientBad = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_LENIENT).open(badWrapper, 'REL-1', 'migrate');
            RlyResultSignature.Opened nothing = new RlyResultSignature.Checker(KEY, RlyResultSignature.MODE_STRICT).open('', 'REL-1', 'validate');
            RlyResultSignature.Opened notJson = new RlyResultSignature.Checker(null, RlyResultSignature.MODE_STRICT).open('not json', 'REL-1', 'validate');
            Map<String, Object> viaKeyStore = RlyResultSignature.lenient(plain, 'REL-1', 'compare');
            Test.stopTest();
            System.assertEquals('Passed', oldFileNoKey.data.get('status'), 'No key: an older unwrapped file is read');
            System.assertEquals('Failed', wrapperNoKey.data.get('status'), 'No key: the wrapper\'s payload is read');
            System.assert(oldFileWithKey.rejected && oldFileWithKey.data == null, 'Key set: an unsigned file is rejected');
            System.assert(unsignedWithKey.rejected, 'Key set: a wrapper without sig is rejected');
            System.assert(!lenientMissing.rejected && lenientMissing.data != null, 'Lenient files accept a missing sig');
            System.assert(lenientBad.rejected, 'Lenient files still reject a wrong sig');
            System.assert(nothing.data == null && !nothing.rejected, 'No file: nothing to read');
            System.assert(notJson.data == null, 'Not JSON: nothing to read');
            System.assertEquals('Passed', viaKeyStore.get('status'), 'No key saved in the test org: accepted');
            System.assert(RlyResultSignature.rejectedMessage('validate').startsWith(RlyResultSignature.REJECTED), 'The message the release shows');
        }
    }

    @IsTest
    static void everyPipelineStartIsSignedThroughRlyGit() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            insert new RLY_Git_Connection__c(Provider__c = 'GitLab', Repository__c = 'acme/salesforce', Named_Credential__c = 'RLY_GitLab',
                Pipeline__c = '.gitlab-ci.yml', Pipeline_Branch__c = 'main', Status__c = 'Connected');
            saveKey();
            RlyHttpMock mock = new RlyHttpMock().match('POST', '/dispatches').reply(204, '').match('POST', '/pipeline').reply(201, '{"id":1}');
            Test.setMock(HttpCalloutMock.class, mock);
            Long before = System.now().getTime() / 1000;
            Test.startTest();
            RlyGit.forConnection([SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c
                FROM RLY_Git_Connection__c WHERE Provider__c = 'GitHub' LIMIT 1]).startPipeline(vectorOne());
            RlyGit.forConnection([SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c
                FROM RLY_Git_Connection__c WHERE Provider__c = 'GitLab' LIMIT 1]).startPipeline(vectorOne());
            Test.stopTest();
            Map<String, Object> inputs = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(mock.bodyFor('/dispatches'))).get('inputs');
            String sent = String.valueOf(inputs.get('options'));
            Map<String, Object> options = (Map<String, Object>) JSON.deserializeUntyped(sent);
            Long sentIat = Long.valueOf(String.valueOf(options.get('iat')));
            String base = sent.replaceFirst(',"iat":\\d+,"sig":"[A-Za-z0-9+/=]+"\\}$', '}');
            System.assert(sentIat >= before, 'iat is now, in epoch seconds');
            System.assertEquals(vectorOne().get('options'), base, 'The pipeline\'s strip gives back what was signed');
            System.assertEquals(RlyRunSigning.mac(KEY, RlyRunSigning.canonical(vectorOne(), base, sentIat)), options.get('sig'), 'GitHub run signed');
            String gitLabBody = mock.bodyFor('/pipeline');
            System.assert(gitLabBody.contains('"variable_type":"env_var"') && gitLabBody.contains('"raw":true'), 'GitLab variables are raw: ' + gitLabBody);
            System.assert(gitLabBody.contains('\\"sig\\":'), 'GitLab run signed too: ' + gitLabBody);
            System.assert(gitLabBody.contains('$HOME'), 'The title is sent as typed');
        }
    }

    @IsTest
    static void withoutAKeyTheInputsAreUnchanged() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            Map<String, String> sent = RlyRunSigning.sign(vectorOne());
            Boolean refused = false;
            try {
                RlyRunSigning.sign(new Map<String, String>{ 'options' => '[1]' }, KEY, IAT);
            } catch (RlyGit.GitException e) {
                refused = true;
            }
            Test.stopTest();
            System.assertEquals(vectorOne().get('options'), sent.get('options'), 'No key: nothing added');
            System.assert(refused, 'Options that aren\'t a JSON object can\'t be signed');
        }
    }

    @IsTest
    static void keyRulesAndConstantTimeCompare() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            String fresh = RlyRunSigning.newKey();
            Test.stopTest();
            System.assert(RlyRunSigning.isKey(fresh), 'A new key is 32 bytes of Base64: ' + fresh);
            System.assert(RlyRunSigning.isKey(KEY), 'The vector key is one');
            System.assert(!RlyRunSigning.isKey('short') && !RlyRunSigning.isKey(null) && !RlyRunSigning.isKey(KEY.left(40) + '===='), 'Not keys');
            System.assert(RlyRunSigning.same('abc', 'abc'), 'Equal');
            System.assert(!RlyRunSigning.same('abc', 'abd') && !RlyRunSigning.same('abc', 'abcd') && !RlyRunSigning.same(null, 'a'), 'Not equal');
            System.assertEquals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', RlyRunSigning.sha256Hex(null), 'Empty text');
        }
    }

    @IsTest
    static void adminsGenerateAndSaveTheKeyOnce() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            RlyRunSigningController.Status before = RlyRunSigningController.status();
            String generated = RlyRunSigningController.generateKey();
            Boolean badRefused = false;
            try {
                RlyRunSigningController.saveKey('not-a-key');
            } catch (AuraHandledException e) {
                badRefused = true;
            }
            RlyRunSigningController.Status savedStatus = RlyRunSigningController.saveKey(generated);
            Test.stopTest();
            System.assert(!before.keySet && before.canEdit, 'No key yet; an admin may set one');
            System.assert(badRefused, 'Only a real key is saved');
            System.assert(savedStatus.keySet && savedStatus.setOn != null && savedStatus.setBy == UserInfo.getName(), 'Saved, with who and when');
            System.assertEquals(generated, RlyRunKeyStore.key(), 'Stored in the protected setting');
            System.assertEquals(null, savedStatus.provider, 'No Git connection in this test');
        }
    }

    @IsTest
    static void othersCantChangeTheKey() {
        User plain = RlyTestData.plainUser();
        System.runAs(plain) {
            Test.startTest();
            RlyRunSigningController.Status s = RlyRunSigningController.status();
            Integer refused = 0;
            try { RlyRunSigningController.generateKey(); } catch (AuraHandledException e) { refused++; }
            try { RlyRunSigningController.saveKey(KEY); } catch (AuraHandledException e) { refused++; }
            try { RlyRunSigningController.checkRepository(); } catch (AuraHandledException e) { refused++; }
            Test.stopTest();
            System.assert(!s.canEdit, 'Read-only for people who aren\'t admins');
            System.assertEquals(3, refused, 'Generate, Save and Check are for admins');
        }
    }

    @IsTest
    static void aRejectedResultLeavesTheReleaseWhereItWas() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            saveKey();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.results.put('scan', RlyReleaseTestData.result('scan', '"status":"Passed","total":0,"blocking":0'));
            scenario.results.put('validate', RlyReleaseTestData.result('validate', '"status":"Passed"'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assertEquals('Pending', saved.Validation_Status__c, 'A forged Passed doesn\'t count');
            System.assertNotEquals('Ready for approval', saved.Status__c, 'The release doesn\'t move');
            System.assert(saved.Error_Message__c != null && saved.Error_Message__c.startsWith(RlyResultSignature.REJECTED), 'Says why: ' + saved.Error_Message__c);
        }
    }

    @IsTest
    static void aSignedPassPinsTheHeadAndTheMergeExpectsIt() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            saveKey();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyFlowScenario scenario = RlyFlowScenario.forRelease(rel);
            scenario.results.put('scan', signedFile(rel.Name, 'scan', '{"status":"Passed","total":0,"blocking":0}'));
            scenario.results.put('validate', signedFile(rel.Name, 'validate', '{"status":"Passed","attempt":"tok7","headSha":"' + HEAD.toUpperCase() + '"}'));
            Test.setMock(HttpCalloutMock.class, scenario.build());
            Test.startTest();
            RlyStatusReader.advance(rel.Id);
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            Map<String, Object> mergeOptions = RlyPipelineOptions.forMode(read, 'merge');
            RLY_Release__c noField = new RLY_Release__c(Id = rel.Id);
            String reread = RlyRunKeyStore.validatedHeadOf(noField);
            Test.stopTest();
            System.assertEquals('Ready for approval', read.Status__c, 'Signed results count: ' + read.Error_Message__c);
            System.assertEquals(HEAD, read.Validated_Head__c, 'The validated head is kept (lower case)');
            System.assertEquals(HEAD, mergeOptions.get('expectHead'), 'The merge expects it');
            System.assertEquals('tok7', read.Validated_Attempt__c, 'The passing run\'s attempt is kept');
            System.assertEquals('tok7', mergeOptions.get('validationAttempt'), 'Sent for the quick deploy');
            System.assertEquals(HEAD, reread, 'Read again when the caller\'s query lacks it');
            System.assertEquals(null, RlyPipelineOptions.forMode(read, 'check').get('expectHead'), 'Only the merge sends it');
        }
    }

    @IsTest
    static void withAKeyAReleaseCheckedBeforeSigningRunsItsChecksAgain() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Ready for approval', 'check');
            saveKey();
            RLY_Release__c read = RlyReleaseStore.release(rel.Id);
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('POST', '/dispatches').reply(204, ''));
            Test.startTest();
            String error;
            try {
                RlyApprovalRuns.dispatchMerge(read, RlyGit.forConnection(RlyReleaseStore.git()));
            } catch (RlyReleaseException e) {
                error = e.getMessage();
            }
            Test.stopTest();
            System.assert(error != null && error.startsWith('Run the checks again'), 'No merge without the validated head: ' + error);
            System.assertEquals('Ready for approval', read.Status__c, 'Nothing dispatched');
        }
    }

    @IsTest
    static void runningTheChecksAgainUnpinsTheHead() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'check');
            update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Validated_Head__c = HEAD, Validated_Attempt__c = 'tok7');
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('POST', '/dispatches').reply(204, ''));
            Test.startTest();
            RlyApprovalService.rerunChecks(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = [SELECT Status__c, Validated_Head__c, Validated_Attempt__c FROM RLY_Release__c WHERE Id = :rel.Id];
            System.assertEquals('Validating', saved.Status__c, 'Checks running again');
            System.assertEquals(null, saved.Validated_Head__c, 'The new check pins the head again');
            System.assertEquals(null, saved.Validated_Attempt__c, 'And its attempt');
        }
    }
}
