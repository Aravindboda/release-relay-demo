/**
 * @description Tests for Retention and Run now (RlyArchiveController, RlyArchiveService, RlyArchiveRunner,
 * RlyArchiveSettings, RlyArchiveEligible, RlyArchiveBatch, RlyArchivePass, RlyArchiveRuns): saving and reading the
 * setting, what is eligible (finished, not held by a running rollback or an open promotion, a promotion only after the
 * releases it carried), passes with their limits, Partial, Failed with the pass rolled back, Cancelled, one run at a
 * time and the refusals. Each test runs through System.runAs as the active System Administrator with Release Relay Admin
 * (or a user without it). "Later" moves the archive's clock forward so records made now count as old.
 */
@IsTest
private class RlyArchiveTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    private static RLY_Archive_Run__c reload(Id runId) {
        return [SELECT Id, Status__c, Message__c, Passes__c, Releases_Removed__c, Records_Removed__c, Storage_Freed_KB__c,
                    Oldest_Removed__c, Newest_Removed__c, Finished__c
                FROM RLY_Archive_Run__c WHERE Id = :runId];
    }

    private static Integer releaseCount() {
        return [SELECT COUNT() FROM RLY_Release__c WHERE Id != null];
    }

    @IsTest
    static void savesAndReadsRetention() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Deployed', 2);
            RlyArchiveViews.Retention first = RlyArchiveController.readRetention();
            System.assertEquals(RlyHubGuard.MODE_HUB, first.mode, 'Hub');
            System.assert(first.canEdit, 'Admins edit');
            System.assertEquals(null, first.days, 'Keep forever until set');
            System.assertEquals(null, first.eligibleReleases, 'No counts without days');
            List<String> refused = new List<String>();
            for (Integer days : new List<Integer>{ 29, 100000 }) {
                try {
                    RlyArchiveController.saveRetention(days, false);
                } catch (AuraHandledException e) {
                    refused.add(e.getMessage());
                }
            }
            try {
                RlyArchiveController.saveRetention(null, true);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            System.assertEquals(new List<String>{ RlyArchiveSettings.TOO_FEW, RlyArchiveSettings.TOO_MANY,
                RlyArchiveSettings.NEEDS_DAYS }, refused, 'Board sentences');
            Test.startTest();
            RlyArchiveViews.Retention saved = RlyArchiveController.saveRetention(1095, true);
            System.assertEquals(1095, saved.days, 'Saved');
            System.assert(saved.nightly, 'Nightly on');
            System.assertNotEquals(null, saved.changedBy, 'Who changed it');
            System.assertEquals(null, saved.previousDays, 'Was keep forever');
            System.assertEquals(0, saved.eligibleReleases, 'Nothing that old yet');
            RlyArchiveTestData.later(400);
            RlyArchiveViews.Retention lowered = RlyArchiveController.saveRetention(365, true);
            Test.stopTest();
            System.assertEquals(1095, lowered.previousDays, 'Was 1,095 days');
            System.assertEquals(2, lowered.eligibleReleases, 'Both finished releases are older than 365 days');
            System.assertEquals(2 * 5, lowered.eligibleRecords, 'Release, item, event, step, step run');
            System.assertEquals(RlyArchiveService.now().addDays(-365).date(), lowered.cutoffDate, 'Cutoff');
            RlyArchiveViews.Retention nightlyOff = RlyArchiveController.saveRetention(365, false);
            System.assertEquals(1095, nightlyOff.previousDays, 'Turning nightly off keeps the days history');
            System.assert(!nightlyOff.nightly, 'Nightly off');
        }
    }

    @IsTest
    static void previewsDays() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Rejected', 3);
            RlyArchiveTestData.later(100);
            Test.startTest();
            RlyArchiveViews.Preview blank = RlyArchiveController.previewRetention(null);
            RlyArchiveViews.Preview tooFew = RlyArchiveController.previewRetention(20);
            RlyArchiveViews.Preview ok = RlyArchiveController.previewRetention(60);
            RlyArchiveEligible.sampleSize = 1;
            RlyArchiveViews.Preview estimated = RlyArchiveController.previewRetention(60);
            Test.stopTest();
            System.assertEquals(null, blank.eligibleReleases, 'Blank: no counts');
            System.assertEquals(null, tooFew.eligibleReleases, 'Under 30: no counts');
            System.assertEquals(3, ok.eligibleReleases, 'Three rejected releases');
            System.assertEquals(15, ok.eligibleRecords, 'Five records each');
            System.assertEquals(15, estimated.eligibleRecords, 'Estimated from one release');
        }
    }

    // Deployed, Closed and Rolled back releases (eligible) and releases held back: a rollback running, an open one, one
    // carried by an open promotion and that promotion. Keys: deployed, closed, rolledBack, rollingBack, open, openPromotion,
    // carried.
    private static Map<String, RLY_Release__c> mixedReleases() {
        Map<String, RLY_Release__c> m = new Map<String, RLY_Release__c>();
        m.put('deployed', RlyArchiveTestData.finished('Deployed', 1)[0]);
        m.put('closed', RlyArchiveTestData.finished('Closed', 1)[0]);
        RLY_Release__c rolledBack = RlyArchiveTestData.release('Ready for approval');
        rolledBack.Rollback_Status__c = 'Rolled_Back';
        rolledBack.Rollback_On__c = System.now();
        RLY_Release__c rollingBack = RlyArchiveTestData.release('Deployed');
        rollingBack.Rollback_Status__c = 'Running';
        RLY_Release__c openPromotion = RlyArchiveTestData.release('PR open');
        openPromotion.Release_Type__c = 'Promotion';
        m.put('rolledBack', rolledBack);
        m.put('rollingBack', rollingBack);
        m.put('open', RlyArchiveTestData.release('Ready for approval'));
        m.put('openPromotion', openPromotion);
        insert new List<RLY_Release__c>{ rolledBack, rollingBack, m.get('open'), openPromotion };
        RLY_Release__c carried = RlyArchiveTestData.release('Deployed');
        carried.Promoted_In__c = openPromotion.Id;
        insert carried;
        m.put('carried', carried);
        RlyArchiveTestData.children(new List<RLY_Release__c>{ rolledBack, rollingBack, m.get('open'), carried });
        return m;
    }

    @IsTest
    static void runNowRemovesOnlyFinishedReleases() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            Map<String, RLY_Release__c> m = mixedReleases();
            Id onlyFile = RlyArchiveTestData.evidence(m.get('deployed').Id);
            Id sharedFile = RlyArchiveTestData.evidence(m.get('closed').Id);
            insert new ContentDocumentLink(ContentDocumentId = sharedFile, LinkedEntityId = m.get('open').Id, ShareType = 'V');
            RlyArchiveTestData.retention(30);
            RlyArchiveTestData.later(60);
            Test.startTest();
            RlyArchiveViews.Archive before = RlyArchiveController.readArchive();
            RlyArchiveViews.Run run = RlyArchiveController.startRun(30);
            RlyArchiveViews.PassResult p = RlyArchiveController.runPass(run.id, 30);
            Test.stopTest();
            System.assertEquals(3, before.eligibleReleases, 'Deployed, closed, rolled back');
            System.assertEquals(0, before.eligibleNext30, 'Nothing more in 30 days');
            System.assert(before.canView && before.canRun, 'Admin views and runs');
            System.assertEquals(RlyArchiveRuns.RUNNING, run.status, 'Started');
            System.assertEquals('Run now', run.how, 'Run now');
            System.assert(p.done, 'One pass removed everything');
            System.assertEquals(RlyArchiveRuns.SUCCEEDED, p.status, 'Succeeded');
            System.assertEquals(3, p.releases, 'Three releases');
            System.assertEquals(15, p.records, 'With their children');
            System.assertEquals(0, p.remaining, 'Nothing left');
            System.assertEquals('1 pass · all eligible removed', p.message, 'Message');
            Set<Id> left = new Map<Id, RLY_Release__c>([SELECT Id FROM RLY_Release__c WHERE Id != null]).keySet();
            System.assertEquals(new Set<Id>{ m.get('rollingBack').Id, m.get('open').Id, m.get('openPromotion').Id,
                m.get('carried').Id }, left, 'Held releases stay');
            System.assertEquals(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :onlyFile], 'Its own file goes');
            System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :sharedFile], 'A shared file stays');
            checkRemoved(m, run.id);
        }
    }

    // The eligible releases' children are gone, the others' stay, and the tab shows the run.
    private static void checkRemoved(Map<String, RLY_Release__c> m, Id runId) {
        List<Id> gone = new List<Id>{ m.get('deployed').Id, m.get('closed').Id, m.get('rolledBack').Id };
        System.assertEquals(0, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Release__c IN :gone], 'Items gone');
        System.assertEquals(0, [SELECT COUNT() FROM RLY_Release_Event__c WHERE Release__c IN :gone], 'History gone');
        System.assertEquals(0, [SELECT COUNT() FROM RLY_Manual_Step__c WHERE Release__c IN :gone], 'Steps gone');
        System.assertEquals(3, [SELECT COUNT() FROM RLY_Manual_Step_Run__c WHERE Id != null], 'Step runs of the others stay');
        RLY_Archive_Run__c row = reload(runId);
        System.assertEquals(30, row.Storage_Freed_KB__c, '2 KB per record');
        System.assertNotEquals(null, row.Oldest_Removed__c, 'Oldest');
        RlyArchiveViews.Archive after = RlyArchiveController.readArchive();
        System.assertEquals(3, after.archivedReleases, 'Archived so far');
        System.assertEquals(1, after.runCount, 'One run');
        System.assertEquals(null, after.running, 'Nothing running');
        System.assertEquals(RlyArchiveRuns.SUCCEEDED, after.lastRun.status, 'Last run');
        System.assertEquals(12, after.months.size(), '12 months');
        System.assertEquals(3, after.months[11].releases, 'This month');
        System.assertEquals(0, after.health.runs, 'Run now is not a nightly run');
    }

    @IsTest
    static void promotionGoesAfterItsReleases() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RLY_Release__c promotion = RlyArchiveTestData.release('Deployed');
            promotion.Release_Type__c = 'Promotion';
            insert promotion;
            RLY_Release__c carried = RlyArchiveTestData.release('Deployed');
            carried.Promoted_In__c = promotion.Id;
            insert carried;
            RlyArchiveTestData.children(new List<RLY_Release__c>{ promotion, carried });
            RlyArchiveTestData.retention(30);
            RlyArchiveTestData.later(60);
            Test.startTest();
            RlyArchiveViews.Run run = RlyArchiveController.startRun(30);
            RlyArchiveViews.PassResult first = RlyArchiveController.runPass(run.id, 30);
            RlyArchiveViews.PassResult second = RlyArchiveController.runPass(run.id, 30);
            Test.stopTest();
            System.assertEquals(1, first.releases, 'Only the carried release first');
            System.assertEquals(1, first.remaining, 'Then the promotion is free');
            System.assert(!first.done, 'Running');
            System.assertEquals('1 pass so far', first.message, 'Progress');
            System.assertEquals(1, second.releases, 'The promotion');
            System.assertEquals(2, second.totalReleases, 'Both');
            System.assertEquals('2 passes · all eligible removed', second.message, 'Done');
            System.assertEquals(0, releaseCount(), 'Nothing left');
        }
    }

    @IsTest
    static void passLimitsAndPartial() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Failed', 5);
            RlyArchiveTestData.retention(30);
            RlyArchiveTestData.later(60);
            RlyArchiveBatch.passReleases = 2;
            RlyArchiveRunner.maxPasses = 2;
            Test.startTest();
            RlyArchiveViews.Run run = RlyArchiveController.startRun(30);
            RlyArchiveViews.PassResult first = RlyArchiveController.runPass(run.id, 30);
            RlyArchiveBatch.passReleases = 200;
            RlyArchiveBatch.passRecords = 4;
            RlyArchiveViews.PassResult second = RlyArchiveController.runPass(run.id, 30);
            Test.stopTest();
            System.assertEquals(2, first.releases, 'Two per pass');
            System.assertEquals(3, first.remaining, 'Three left');
            System.assertEquals(1, second.releases, 'The record limit takes one release (5 records) per pass');
            System.assert(second.done, 'Stopped');
            System.assertEquals(RlyArchiveRuns.PARTIAL, second.status, 'Partial at the pass limit');
            System.assert(second.message.startsWith('Stopped at the 2-pass limit'), second.message);
            System.assertEquals(2, releaseCount(), 'Two left for the next run');
        }
    }

    @IsTest
    static void failedPassRollsBack() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Deployed', 2);
            RlyArchiveTestData.retention(30);
            RlyArchiveTestData.later(60);
            Test.startTest();
            RlyArchiveViews.Run run = RlyArchiveController.startRun(30);
            RlyArchivePass.failForTest = true;
            RlyArchiveViews.PassResult p = RlyArchiveController.runPass(run.id, 30);
            Test.stopTest();
            System.assert(p.done, 'The run stops');
            System.assertEquals(RlyArchiveRuns.FAILED, p.status, 'Failed');
            System.assert(p.message.contains('UNABLE_TO_LOCK_ROW'), p.message);
            System.assertEquals(null, p.remaining, 'Not counted after a failure');
            System.assertEquals(2, releaseCount(), 'Nothing of that pass was removed');
            System.assertEquals(2, [SELECT COUNT() FROM RLY_Release_Item__c WHERE Id != null], 'Children rolled back too');
            RLY_Archive_Run__c row = reload(run.id);
            System.assertEquals(0, row.Passes__c, 'No pass counted');
            String again;
            try {
                RlyArchiveController.runPass(run.id, 30);
            } catch (AuraHandledException e) {
                again = e.getMessage();
            }
            System.assertEquals(RlyArchiveRunner.ENDED, again, 'A failed run takes no more passes');
        }
    }

    @IsTest
    static void cancelsAndRunsOneAtATime() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.finished('Deployed', 1);
            RlyArchiveTestData.retention(30);
            RlyArchiveTestData.later(60);
            Test.startTest();
            RlyArchiveViews.Run run = RlyArchiveController.startRun(30);
            String busy;
            try {
                RlyArchiveController.startRun(30);
            } catch (AuraHandledException e) {
                busy = e.getMessage();
            }
            RlyArchiveViews.Archive going = RlyArchiveController.readArchive();
            RlyArchiveViews.Run cancelled = RlyArchiveController.cancelRun(run.id);
            RlyArchiveViews.Run again = RlyArchiveController.cancelRun(run.id);
            Test.stopTest();
            System.assertEquals(RlyArchiveRunner.BUSY, busy, 'A second run is refused');
            System.assertEquals(run.id, going.running.id, 'The page sees the run going');
            System.assertEquals(RlyArchiveRuns.CANCELLED, cancelled.status, 'Cancelled');
            System.assertEquals('Cancelled after pass 0', cancelled.message, 'Message');
            System.assertEquals(cancelled.finished, again.finished, 'A finished run stays as it is');
            System.assertEquals(1, releaseCount(), 'Nothing removed');
        }
    }

    @IsTest
    static void deadRunStopsBlocking() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.retention(30);
            RLY_Archive_Run__c stuck = RlyArchiveTestData.run(RlyArchiveRuns.RUN_NOW, RlyArchiveRuns.RUNNING, System.now());
            RlyArchiveRuns.deadMinutes = -1;
            Test.startTest();
            RlyArchiveViews.Archive a = RlyArchiveController.readArchive();
            String nothing;
            try {
                RlyArchiveController.startRun(30);
            } catch (AuraHandledException e) {
                nothing = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(null, a.running, 'A run with no pass for 15 minutes is not running');
            System.assertEquals(RlyArchiveRuns.FAILED, reload(stuck.Id).Status__c, 'Stopped as Failed');
            System.assertEquals(RlyArchiveRuns.DEAD_MESSAGE, reload(stuck.Id).Message__c, 'Why');
            System.assertEquals(RlyArchiveRunner.NOTHING, nothing, 'Not blocked: refused only because nothing is eligible');
        }
    }

    @IsTest
    static void refusesWhatTheCallerMayNotDo() {
        User plain = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
        }
        System.runAs(plain) {
            List<String> refused = new List<String>();
            try {
                RlyArchiveController.saveRetention(60, false);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            try {
                RlyArchiveController.startRun(60);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            try {
                RlyArchiveController.cancelRun(null);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            System.assertEquals(new List<String>{ RlyArchiveService.EDIT_ADMIN_ONLY, RlyArchiveService.ADMIN_ONLY,
                RlyArchiveService.ADMIN_ONLY }, refused, 'Admins only');
            System.assert(!RlyArchiveController.readRetention().canEdit, 'Reads only');
            RlyArchiveViews.Archive a = RlyArchiveController.readArchive();
            System.assert(!a.canView, 'Tab hidden');
            System.assertEquals(null, a.health, 'No numbers');
        }
    }

    @IsTest
    static void approverSeesTheArchive() {
        User approver = RlyArchiveTestData.approver();
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.retention(30);
        }
        System.runAs(approver) {
            Test.startTest();
            RlyArchiveViews.Archive a = RlyArchiveController.readArchive();
            Test.stopTest();
            System.assert(a.canView, 'Approvers see the tab');
            System.assert(!a.canRun, 'Only admins run');
            System.assertEquals(30, a.days, 'The setting');
            System.assertEquals(0, a.runCount, 'No runs yet');
        }
    }

    @IsTest
    static void confirmsTheSavedDays() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            List<String> refused = new List<String>();
            try {
                RlyArchiveController.startRun(30);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            RlyArchiveTestData.retention(30);
            try {
                RlyArchiveController.startRun(31);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            RLY_Archive_Run__c older = RlyArchiveTestData.run(RlyArchiveRuns.RUN_NOW, RlyArchiveRuns.RUNNING, System.now());
            RlyArchiveTestData.retention(60);
            try {
                RlyArchiveController.runPass(older.Id, 60);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            try {
                RlyArchiveController.runPass(null, 60);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            try {
                RlyArchiveController.cancelRun(null);
            } catch (AuraHandledException e) {
                refused.add(e.getMessage());
            }
            System.assertEquals(RlyArchiveRunner.NO_DAYS, refused[0], 'No days set');
            System.assertEquals('Type 30 to confirm: the saved number of days.', refused[1], 'Days must match');
            System.assert(refused[2].startsWith('The Retention days changed'), refused[2]);
            System.assertEquals(RlyArchiveRunner.NOT_FOUND, refused[3], 'Unknown run');
            System.assertEquals(RlyArchiveRunner.NOT_FOUND, refused[4], 'Unknown run to cancel');
        }
    }

    @IsTest
    static void sandboxGetsTheGate() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            RlyArchiveTestData.retention(30);
            RlyHubGuard.sandboxForTest = true;
            RlyHubGuard.forget();
            Test.startTest();
            RlyArchiveViews.Retention r = RlyArchiveController.readRetention();
            RlyArchiveViews.Archive a = RlyArchiveController.readArchive();
            RlyArchiveViews.Preview p = RlyArchiveController.previewRetention(60);
            String refused;
            try {
                RlyArchiveController.saveRetention(60, false);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(RlyHubGuard.MODE_SANDBOX, r.mode, 'Sandbox');
            System.assertNotEquals(null, r.gateMessage, 'Gate text');
            System.assertEquals(null, r.days, 'No retention');
            System.assertEquals(RlyHubGuard.MODE_SANDBOX, a.mode, 'Sandbox');
            System.assertEquals(null, a.health, 'No archive content');
            System.assertEquals(null, p.eligibleReleases, 'No counts');
            System.assertEquals(RlyArchiveService.COPY_MESSAGE, refused, 'Production hub only');
        }
    }

    @IsTest
    static void copyOfTheHubGetsTheBoardGate() {
        System.runAs(RlyTestData.admin()) {
            RlyArchiveTestData.hub();
            update new RLY_Org__c(Id = [SELECT Id FROM RLY_Org__c WHERE Role__c = 'Hub' LIMIT 1].Id,
                Org_Id__c = RlyTestData.fakeId('00D', 7));
            RlyHubGuard.forget();
            Test.startTest();
            RlyArchiveViews.Retention r = RlyArchiveController.readRetention();
            Test.stopTest();
            System.assertEquals(RlyHubGuard.MODE_COPY, r.mode, 'Copy of the hub');
            System.assertEquals('This org is a sandbox copy of the hub', r.gateTitle, 'Board title');
            System.assertEquals(RlyArchiveService.COPY_MESSAGE, r.gateMessage, 'Board text');
            System.assert(!r.canEdit, 'Nothing to edit here');
        }
    }
}
