/**
 * @description Tests for files on manual steps (build 34): RlyStepFiles, RlyStepFileStore, RlyStepFileActions,
 * RlyStepFileDrafts, RlyStepFileEvidence, RlyStepFileGuard with the triggers
 * RlyContentDocumentLink and RlyContentVersion, the file methods of RlyManualStepController (removeFile, logDownload,
 * draftFiles, removeDraftFile), the board's files (RlyManualStepBoard), the lock on deleting a step (RlyManualStepEdit)
 * and the Files table of the evidence (RlyEvidenceController, RlyStepFileEvidence). A release raised from DEV1 into SIT
 * (RlyReleaseTestData) with one step and its SIT run. Each test runs through System.runAs as an active System
 * Administrator with Release Relay Admin, or as a user without Release Relay permission sets; deletes sit in try/catch.
 */
@IsTest
private class RlyStepFilesTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    /** @description The release, its step and the step's run in SIT. */
    private class Fixture {
        /** @description The release. */
        public RLY_Release__c rel;
        /** @description Its step. */
        public RLY_Manual_Step__c step;
        /** @description The step's run in SIT. */
        public RLY_Manual_Step_Run__c run;
    }

    private static Fixture fixture() {
        Fixture f = new Fixture();
        f.rel = RlyReleaseTestData.release('PR open', null);
        Id sitId = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1].Id;
        f.step = new RLY_Manual_Step__c(Release__c = f.rel.Id, Title__c = 'Load 240 USA contacts', Category__c = 'Data',
            Timing__c = 'Before_Deploy', Sequence__c = 1, Back_Promote__c = false);
        insert f.step;
        f.run = new RLY_Manual_Step_Run__c(Step__c = f.step.Id, Release__c = f.rel.Id, Org__c = sitId, Status__c = 'To_Do', Order__c = 1);
        insert f.run;
        return f;
    }

    // Uploads a file as lightning-file-upload does (linked to the record), or to the user's own library (recordId null).
    private static Id upload(Id recordId, String name) {
        ContentVersion v = new ContentVersion(Title = name, PathOnClient = name, VersionData = Blob.valueOf('Id,Name\n1,Acme'),
            FirstPublishLocationId = recordId);
        insert v;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id].ContentDocumentId;
    }

    private static String uploadProblem(Id recordId, String name) {
        try {
            upload(recordId, name);
        } catch (DmlException e) {
            return e.getMessage();
        }
        return null;
    }

    private static void approve(Id releaseId) {
        update new RLY_Release__c(Id = releaseId, Status__c = 'Approved', Approval_Status__c = 'Approved',
            Approved_By__c = UserInfo.getUserId(), Approved_On__c = System.now());
    }

    private static Integer events(Id releaseId, String eventType) {
        return [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c = :releaseId AND Event_Type__c = :eventType];
    }

    @IsTest
    static void filesShowOnTheBoardAndLockAfterApproval() {
        System.runAs(RlyTestData.admin()) {
            Fixture f = fixture();
            Id stepDoc = upload(f.step.Id, 'usa-contacts.csv');
            upload(f.run.Id, 'success-sit.pdf');
            Test.startTest();
            RlyManualSteps.StepBoard b = RlyManualStepController.getSteps(f.rel.Id);
            System.assertEquals(1, b.steps[0].files.size(), 'The step file');
            System.assert(b.steps[0].canAttach && !b.steps[0].locked, 'The raiser may still change it');
            System.assert(b.steps[0].files[0].canRemove, 'And remove it');
            System.assertEquals('usa-contacts.csv', b.steps[0].files[0].title, 'Name with its extension');
            RlyManualSteps.RunRow r = b.orgs[0].runs[0];
            System.assertEquals(1, r.proof.size(), 'The proof');
            System.assertEquals('SIT', r.proof[0].orgName, 'In SIT');
            System.assert(r.proof[0].previewable && r.canAddProof, 'A PDF previews; admins add proof');
            System.assertEquals(1, events(f.rel.Id, RlyStepFiles.EVENT_ATTACHED), 'Attached in History');
            System.assertEquals(1, events(f.rel.Id, RlyStepFiles.EVENT_PROOF), 'Proof added in History');

            approve(f.rel.Id);
            b = RlyManualStepController.getSteps(f.rel.Id);
            System.assert(b.steps[0].locked && !b.steps[0].canAttach, 'Locked after approval');
            System.assert(b.steps[0].lockText.contains('approved on'), 'Who approved, when: ' + b.steps[0].lockText);
            System.assert(!b.steps[0].files[0].canRemove, 'No remove');
            String refused = uploadProblem(f.step.Id, 'late.csv');
            System.assert(refused != null && refused.contains(RlyStepFiles.LOCK_MESSAGE), 'No new step file: ' + refused);
            System.assertEquals(null, uploadProblem(f.run.Id, 'success-sit-2.csv'), 'Proof stays open');
            Boolean versionRefused = false;
            try {
                insert new ContentVersion(ContentDocumentId = stepDoc, Title = 'usa-contacts.csv', PathOnClient = 'usa-contacts.csv',
                    VersionData = Blob.valueOf('changed'));
            } catch (DmlException e) {
                versionRefused = e.getMessage().contains(RlyStepFiles.LOCK_MESSAGE);
            }
            System.assert(versionRefused, 'No new version of a locked file');
            Boolean unlinkRefused = false;
            try {
                delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :f.step.Id];
            } catch (DmlException e) {
                unlinkRefused = e.getMessage().contains(RlyStepFiles.LOCK_MESSAGE);
            }
            System.assert(unlinkRefused, 'No removing a locked file');
            Boolean deleteRefused = false;
            try {
                RlyManualStepController.deleteStep(f.step.Id);
            } catch (AuraHandledException e) {
                deleteRefused = e.getMessage().contains('locked');
            }
            Test.stopTest();
            System.assert(deleteRefused, 'A step with locked files is not deleted');
        }
    }

    @IsTest
    static void removeFileDeletesItAndLogs() {
        System.runAs(RlyTestData.admin()) {
            Fixture f = fixture();
            Id stepDoc = upload(f.step.Id, 'mapping.sdl');
            Id proofDoc = upload(f.run.Id, 'success-sit.csv');
            Test.startTest();
            RlyManualSteps.StepBoard b;
            try {
                b = RlyManualStepController.removeFile(f.step.Id, stepDoc, f.rel.Id);
                b = RlyManualStepController.removeFile(f.run.Id, proofDoc, f.rel.Id);
            } catch (AuraHandledException e) {
                System.assert(false, 'Removed: ' + e.getMessage());
            }
            Test.stopTest();
            System.assert(b.steps[0].files.isEmpty() && b.orgs[0].runs[0].proof.isEmpty(), 'Gone from the card');
            System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id IN :new Set<Id>{ stepDoc, proofDoc }], 'Own files deleted');
            System.assertEquals(2, events(f.rel.Id, RlyStepFiles.EVENT_REMOVED), 'Removed in History');
            String again;
            try {
                RlyManualStepController.removeFile(f.step.Id, stepDoc, f.rel.Id);
            } catch (AuraHandledException e) {
                again = e.getMessage();
            }
            System.assert(again != null && again.contains('isn\'t on a manual step'), 'Already gone: ' + again);
        }
    }

    @IsTest
    static void draftFilesAreLinkedOnRaise() {
        System.runAs(RlyTestData.admin()) {
            Fixture f = fixture();
            Id draft = upload(null, 'intake-users.csv');
            Id spare = upload(null, 'steps.pdf');
            Test.startTest();
            List<RlyStepFiles.FileRow> rows = RlyManualStepController.draftFiles(new List<Id>{ draft, spare });
            System.assertEquals(2, rows.size(), 'Both draft files');
            System.assert(rows[0].canRemove && rows[0].recordId == null, 'A draft file, removable');
            System.assert(RlyManualStepController.draftFiles(null).isEmpty(), 'None asked, none given');
            RlyManualSteps.StepInput input = new RlyManualSteps.StepInput();
            input.title = f.step.Title__c;
            input.files = new List<Id>{ draft, draft };
            RlyStepFileDrafts.linkDrafts(new List<RLY_Manual_Step__c>{ f.step }, new List<RlyManualSteps.StepInput>{ input });
            RlyStepFileDrafts.linkDrafts(new List<RLY_Manual_Step__c>{ f.step }, null);
            String linkedRefusal;
            try {
                RlyManualStepController.removeDraftFile(draft);
            } catch (AuraHandledException e) {
                linkedRefusal = e.getMessage();
            }
            Boolean removed = RlyManualStepController.removeDraftFile(spare);
            Test.stopTest();
            List<ContentDocumentLink> links = [SELECT ShareType, Visibility FROM ContentDocumentLink WHERE LinkedEntityId = :f.step.Id];
            System.assertEquals(1, links.size(), 'Linked once to the saved step');
            System.assertEquals('V', links[0].ShareType, 'Viewer link');
            System.assert(linkedRefusal != null && linkedRefusal.contains('saved manual step'), 'A linked file is removed on the release page');
            System.assert(removed && [SELECT COUNT() FROM ContentDocument WHERE Id = :spare] == 0, 'Draft file deleted');
            input.files = new List<Id>{ spare };
            Boolean missing = false;
            try {
                RlyStepFileDrafts.linkDrafts(new List<RLY_Manual_Step__c>{ f.step }, new List<RlyManualSteps.StepInput>{ input });
            } catch (RlyReleaseException e) {
                missing = e.getMessage().contains('manual step 1');
            }
            System.assert(missing, 'A file that is gone is refused');
        }
    }

    @IsTest
    static void othersFollowTheRules() {
        User plain = RlyTestData.plainUser();
        Fixture f;
        Id proofDoc;
        System.runAs(RlyTestData.admin()) {
            f = fixture();
            proofDoc = upload(f.run.Id, 'success-sit.csv');
        }
        System.runAs(plain) {
            Test.startTest();
            String stepRefusal = uploadProblem(f.step.Id, 'mine.csv');
            String proofRefusal = uploadProblem(f.run.Id, 'proof.csv');
            String removeRefusal;
            try {
                RlyManualStepController.removeFile(f.run.Id, proofDoc, f.rel.Id);
            } catch (AuraHandledException e) {
                removeRefusal = e.getMessage();
            }
            String draftRefusal;
            try {
                RlyManualStepController.removeDraftFile(proofDoc);
            } catch (AuraHandledException e) {
                draftRefusal = e.getMessage();
            }
            Test.stopTest();
            System.assert(stepRefusal != null && stepRefusal.contains('person who raised'), 'Not the raiser: ' + stepRefusal);
            System.assert(proofRefusal != null && proofRefusal.contains('deployment team'), 'Not the deployment team: ' + proofRefusal);
            System.assert(removeRefusal != null && removeRefusal.contains('person who added'), 'Not who added it: ' + removeRefusal);
            System.assert(draftRefusal != null && draftRefusal.contains('uploaded'), 'Not who uploaded it: ' + draftRefusal);
        }
    }

    @IsTest
    static void downloadsAreLogged() {
        System.runAs(RlyTestData.admin()) {
            Fixture f = fixture();
            Id doc = upload(f.step.Id, 'usa-contacts.csv');
            Id loose = upload(null, 'notes.txt');
            Test.startTest();
            String url = RlyManualStepController.logDownload(doc, f.rel.Id, f.run.Org__c);
            String refusal;
            try {
                RlyManualStepController.logDownload(loose, f.rel.Id, null);
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
            Test.stopTest();
            System.assert(url.endsWith(String.valueOf(doc)), 'Download address: ' + url);
            System.assertEquals(1, events(f.rel.Id, RlyStepFiles.EVENT_DOWNLOADED), 'Downloaded in History');
            System.assert(refusal != null, 'Only files on manual steps');
        }
    }

    @IsTest
    static void evidenceListsTheFiles() {
        System.runAs(RlyTestData.admin()) {
            Fixture f = fixture();
            Id doc = upload(f.step.Id, 'usa-contacts.csv');
            upload(f.run.Id, 'success-sit.csv');
            RlyStepFileActions.remove(f.step.Id, doc);
            upload(f.step.Id, 'mapping.sdl');
            Test.startTest();
            RlyEvidenceController.EvidenceFile pdf = RlyEvidenceController.saveEvidence(f.rel.Id);
            RLY_Release__c rel = RlyReleaseStore.release(f.rel.Id);
            List<List<String>> rows = RlyStepFileEvidence.evidenceRows(rel, RlyReleaseLog.eventsOf(new Set<Id>{ rel.Id }));
            String html = RlyStepFileEvidence.html(rows);
            Map<Id, String> csv = RlyStepFileEvidence.csvFiles(new List<RLY_Release__c>{ rel });
            String csvExport = RlyEvidenceController.exportCsv('{"state":"all"}');
            Test.stopTest();
            System.assert(pdf.contentDocumentId != null, 'Evidence saved');
            System.assertEquals(3, rows.size(), 'Step file, proof, removed: ' + rows);
            System.assertEquals('SIT', rows[1][5], 'Proof by org');
            System.assertEquals('Removed', rows[2][2], 'Removed shows');
            System.assert(html.contains('<h2>Files</h2>') && html.contains('mapping.sdl'), 'Files table');
            System.assertEquals('', RlyStepFileEvidence.html(new List<List<String>>()), 'No files, no table');
            System.assert(csv.get(rel.Id).contains('success-sit.csv (') && csv.get(rel.Id).contains('proof in SIT'), 'CSV column: ' + csv);
            System.assert(csvExport.split('\r\n')[0].endsWith('"Files"'), 'CSV header ends with Files');
        }
    }

    @IsTest
    static void wordsForFiles() {
        System.runAs(RlyTestData.admin()) {
            System.assertEquals('900 B', RlyStepFiles.sizeText(900), 'Bytes');
            System.assertEquals('12 KB', RlyStepFiles.sizeText(12 * 1024), 'Kilobytes');
            System.assertEquals('1.5 MB', RlyStepFiles.sizeText(1536 * 1024), 'Megabytes');
            System.assertEquals('0 B', RlyStepFiles.sizeText(null), 'Nothing');
            System.assertEquals('a.csv', RlyStepFiles.nameOf('a.csv', 'csv'), 'Extension kept once');
            System.assertEquals('a.csv', RlyStepFiles.nameOf('a', 'csv'), 'Extension added');
            System.assertEquals('a', RlyStepFiles.nameOf('a', null), 'No extension');
            System.assert(RlyStepFiles.lockText(null).contains('the approver'), 'Unknown approver');
            System.assert(!RlyStepFiles.isLocked(null) && !RlyStepFiles.isStep(null) && !RlyStepFiles.isRun(null), 'Nothing is not locked');
            System.assertEquals(null, RlyStepFiles.proofAddRefusal(), 'Admins add proof');
        }
    }
}
