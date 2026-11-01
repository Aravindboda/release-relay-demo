/**
 * @description Tests for the shared status reads (RlySharedRead, via RlyStatusReader.advance and RlyReleasesController.refreshRelease):
 * a release read less than RlySharedRead.FRESH_SECONDS ago is returned as saved with no callouts, an older one is read
 * and moved along, and a save that meets a row lock held by another viewer returns the saved release instead of an
 * error. A stale release is claimed first (FOR UPDATE, freshness checked again on the locked row; a lock that can't be
 * had returns the saved release), and Check now reads again once the last read is over 5 s old. Each test runs as an
 * active System Administrator via System.runAs.
 */
@IsTest
private class RlySharedReadTest {

    @IsTest
    static void freshReleaseIsNotReadAgain() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            update new RLY_Release__c(Id = rel.Id, Last_Synced__c = System.now().addSeconds(-5));
            Datetime readAt = syncedAt(rel.Id);
            RlySharedRead.shareReads = true;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(0, mock.calls.size(), 'No callouts while the last read is fresh: ' + mock.callLog());
            System.assertEquals('Retrieving', d.release.Status__c, 'The saved status');
            System.assertEquals(readAt, syncedAt(rel.Id), 'Not saved again');
            System.assert(d.running, 'Still running, so the page keeps checking');
        }
    }

    @IsTest
    static void staleReleaseIsReadAndMovedAlong() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            update new RLY_Release__c(Id = rel.Id, Last_Synced__c = System.now().addSeconds(-(RlySharedRead.FRESH_SECONDS + 40)));
            RlySharedRead.shareReads = true;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Release__c moved = RlyStatusReader.advance(rel.Id);
            Test.stopTest();
            RLY_Release__c saved = RlyReleaseTestData.reload(rel.Id);
            System.assert(!mock.calls.isEmpty(), 'An old read is read again');
            System.assertEquals('Workflow running', moved.Status__c, 'Moved along: ' + moved.Error_Message__c);
            System.assertEquals('Workflow running', saved.Status__c, 'And saved');
            System.assert(RlySharedRead.isFresh(new RLY_Release__c(Last_Synced__c = syncedAt(rel.Id))), 'Fresh for the next viewer');
        }
    }

    @IsTest
    static void lockedRowReturnsTheSavedRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, RlyFlowScenario.forRelease(rel).build());
            RlySharedRead.shareReads = true;
            RlySharedRead.lockedForTest = true;
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals('Retrieving', d.release.Status__c, 'The release as another viewer saved it, no error');
            System.assertEquals(null, d.release.Error_Message__c, 'No error on the release');
            System.assertEquals('Retrieving', RlyReleaseTestData.reload(rel.Id).Status__c, 'Nothing of this read was saved');
        }
    }

    @IsTest
    static void freshnessNeedsAReadTime() {
        System.runAs(RlyTestData.admin()) {
            RlySharedRead.shareReads = true;
            Test.startTest();
            Boolean neverRead = RlySharedRead.isFresh(new RLY_Release__c());
            Boolean justRead = RlySharedRead.isFresh(new RLY_Release__c(Last_Synced__c = System.now()));
            Boolean longAgo = RlySharedRead.isFresh(new RLY_Release__c(Last_Synced__c = System.now().addMinutes(-5)));
            Boolean checkNowWindow = RlySharedRead.isFresh(new RLY_Release__c(Last_Synced__c = System.now().addSeconds(-10)),
                RlySharedRead.CHECK_NOW_SECONDS);
            Test.stopTest();
            System.assert(!neverRead, 'Never read: read it');
            System.assert(justRead, 'Just read: share it');
            System.assert(!longAgo, 'Read minutes ago: read it again');
            System.assert(!checkNowWindow, 'Check now: 10 s is old enough to read again');
        }
    }

    @IsTest
    static void claimLockedByAnotherViewerReturnsTheSavedRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            RlySharedRead.shareReads = true;
            RlySharedRead.claimLockedForTest = true;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.refreshRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(0, mock.calls.size(), 'Another viewer is reading it: no callouts here: ' + mock.callLog());
            System.assertEquals('Retrieving', d.release.Status__c, 'The release as saved, no error');
            System.assertEquals(null, syncedAt(rel.Id), 'Nothing saved');
        }
    }

    @IsTest
    static void claimChecksFreshnessOnTheLockedRow() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c stale = RlyReleaseTestData.release('Retrieving', null);
            RLY_Release__c fresh = RlyReleaseTestData.release('Validating', 'hub');
            update new RLY_Release__c(Id = fresh.Id, Last_Synced__c = System.now());
            RlySharedRead.shareReads = true;
            Test.startTest();
            Boolean staleClaimed = RlySharedRead.claim(stale.Id, RlySharedRead.FRESH_SECONDS);
            Boolean freshClaimed = RlySharedRead.claim(fresh.Id, RlySharedRead.FRESH_SECONDS);
            Test.stopTest();
            System.assert(staleClaimed, 'Stale on the locked row: this viewer reads it');
            System.assert(!freshClaimed, 'Read meanwhile (fresh on the locked row): the saved release is returned');
        }
    }

    @IsTest
    static void checkNowReadsAfterFiveSeconds() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            update new RLY_Release__c(Id = rel.Id, Last_Synced__c = System.now().addSeconds(-10));
            RlySharedRead.shareReads = true;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.checkRelease(rel.Id);
            Test.stopTest();
            System.assert(!mock.calls.isEmpty(), 'Check now reads a release read 10 s ago');
            System.assertEquals('Workflow running', d.release.Status__c, 'Moved along: ' + d.release.Error_Message__c);
        }
    }

    @IsTest
    static void checkNowSharesAReadOfTheLastFiveSeconds() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            update new RLY_Release__c(Id = rel.Id, Last_Synced__c = System.now().addSeconds(-1));
            RlySharedRead.shareReads = true;
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = RlyFlowScenario.forRelease(rel).build();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyReleasesController.checkRelease(rel.Id);
            Test.stopTest();
            System.assertEquals(0, mock.calls.size(), 'Read a second ago: no callouts: ' + mock.callLog());
            System.assertEquals('Retrieving', d.release.Status__c, 'The saved status');
        }
    }

    // When the release was last read, as saved.
    private static Datetime syncedAt(Id relId) {
        return [SELECT Last_Synced__c FROM RLY_Release__c WHERE Id = :relId].Last_Synced__c;
    }
}
