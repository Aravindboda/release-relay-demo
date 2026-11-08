/**
 * @description Tests for build 54's Cancel release (RlyReleaseCancel and its cancelFromPage, Detail.canCancel):
 * the raiser and an admin can cancel an open release, another developer can't, a closed release can't be cancelled, and
 * the pull request gets the comment and is closed. Users with the System Administrator profile and no Release Relay
 * permission sets stand for developers; every Git call is answered by RlyHttpMock. Records are inserted before
 * Test.startTest, callouts come after.
 */
@IsTest
private class RlyReleaseCancelTest {

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
        }
    }

    // A new user without Release Relay permission sets (a developer here); the tag keeps usernames apart.
    private static User developer(String tag) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User u = new User(Alias = 'rly' + tag.left(5), Email = 'rly.' + tag + '@example.com', EmailEncodingKey = 'UTF-8', LastName = tag,
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profileId, TimeZoneSidKey = 'America/Chicago',
            Username = 'rly.' + tag + '.' + UserInfo.getOrganizationId() + '.' + Datetime.now().getTime() + '@example.com');
        System.runAs(RlyTestData.admin()) {
            insert u;
        }
        return u;
    }

    // An open release from DEV1 into SIT with pull request #41, inserted as the running user (its raiser).
    private static RLY_Release__c raise(String status) {
        RLY_Release__c rel = new RLY_Release__c(Title__c = 'Region field', Status__c = status, Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Source_Org__c = orgId('DEV1'), Target_Org__c = orgId('SIT'), Org_Label__c = 'DEV1',
            Target_Branch__c = 'sit', Source_Environment__c = 'dev1', Target_Environment__c = 'sit', Scan_Status__c = 'Pending',
            Validation_Status__c = 'Pending', Approval_Status__c = 'Pending', Deploy_Status__c = 'Pending', Component_Count__c = 1,
            PR_Number__c = 41, PR_URL__c = 'https://github.com/acme/release/pull/41');
        insert rel;
        return rel;
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RlyHttpMock closingMock() {
        return new RlyHttpMock()
            .match('POST', '/repos/acme/release/issues/41/comments').reply(201, '{"id":1}')
            .match('PATCH', '/repos/acme/release/pulls/41').reply(200, '{"state":"closed"}');
    }

    private static String refusal(Exception e) {
        return e.getMessage();
    }

    @IsTest
    static void raiserCancelsAndThePullRequestIsClosedWithTheReason() {
        User raiser = developer('raiser');
        RLY_Release__c rel;
        System.runAs(raiser) {
            rel = raise('Ready for approval');
        }
        RlyHttpMock mock = closingMock();
        System.runAs(raiser) {
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Boolean could = RlyReleasesController.getRelease(rel.Id).canCancel;
            String noReason;
            try {
                RlyReleaseCancel.cancelRelease(rel.Id, '  ');
            } catch (RlyReleaseException e) {
                noReason = refusal(e);
            }
            RlyReleasesController.Detail d = RlyReleaseCancel.cancelFromPage(rel.Id, 'Replaced by a smaller release');
            Test.stopTest();
            System.assert(could, 'The raiser may cancel an open release');
            System.assert(noReason != null && noReason.contains('Say why'), 'A reason is needed: ' + noReason);
            System.assertEquals('Cancelled', d.release.Status__c, 'Cancelled');
            System.assertEquals(false, d.canCancel, 'A cancelled release can\'t be cancelled again');
            System.assert(d.release.Error_Message__c.startsWith('Cancelled by raiser: Replaced by a smaller release'),
                'The reason is on the release: ' + d.release.Error_Message__c);
            System.assert(mock.bodyFor('/issues/41/comments').contains('Cancelled in Release Relay by raiser: Replaced by a smaller release'),
                'The pull request gets the comment: ' + mock.callLog());
            System.assert(mock.callLog().contains('PATCH') && mock.bodyFor('/pulls/41').contains('closed'), 'And is closed: ' + mock.callLog());
            List<RLY_Release_Event__c> events = [SELECT Detail__c, Actor__c FROM RLY_Release_Event__c
                WHERE Release__c = :rel.Id AND Event_Type__c = 'Cancelled'];
            System.assertEquals(1, events.size(), 'History has the Cancelled event');
            System.assertEquals(raiser.Id, events[0].Actor__c, 'By the raiser');
        }
    }

    @IsTest
    static void anotherDeveloperCantCancel() {
        User raiser = developer('raiser');
        User other = developer('other');
        RLY_Release__c rel;
        System.runAs(raiser) {
            rel = raise('Checks failed');
        }
        System.runAs(other) {
            Test.startTest();
            Boolean could = RlyReleasesController.getRelease(rel.Id).canCancel;
            String refused;
            try {
                RlyReleaseCancel.cancelRelease(rel.Id, 'Not mine to cancel');
            } catch (RlyReleaseException e) {
                refused = refusal(e);
            }
            Test.stopTest();
            System.assertEquals(false, could, 'Another developer doesn\'t see Cancel release');
            System.assert(refused != null && refused.contains('Only the person who raised'), 'Refused: ' + refused);
            System.assertEquals('Checks failed', [SELECT Status__c FROM RLY_Release__c WHERE Id = :rel.Id].Status__c, 'Unchanged');
        }
    }

    @IsTest
    static void adminCancelsSomeoneElsesDeployingRelease() {
        User raiser = developer('raiser');
        RLY_Release__c rel;
        System.runAs(raiser) {
            rel = raise('Deploying');
        }
        System.runAs(RlyTestData.admin()) {
            update new RLY_Release__c(Id = rel.Id, Merge_Commit__c = 'abc1234');
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Release__c saved = RlyReleaseCancel.cancelRelease(rel.Id, 'Wrong target org');
            Test.stopTest();
            System.assertEquals('Cancelled', saved.Status__c, 'An admin cancels it');
            System.assertEquals(0, mock.calls.size(), 'A merged pull request is left as it is: ' + mock.callLog());
            System.assert(saved.Error_Message__c.contains(': Wrong target org'), 'The reason is kept: ' + saved.Error_Message__c);
        }
    }

    @IsTest
    static void closedReleaseCantBeCancelled() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = raise('Closed');
            Test.startTest();
            Boolean could = RlyReleaseCancel.mayCancel(RlyReleaseStore.release(rel.Id));
            String refused;
            try {
                RlyReleaseCancel.cancelRelease(rel.Id, 'Too late');
            } catch (RlyReleaseException e) {
                refused = refusal(e);
            }
            String missing;
            try {
                RlyReleaseCancel.cancelFromPage(null, 'Nothing');
            } catch (AuraHandledException e) {
                missing = refusal(e);
            }
            Test.stopTest();
            System.assertEquals(false, could, 'Closed: no Cancel release');
            System.assert(refused != null && refused.contains('is Closed'), 'Refused: ' + refused);
            System.assert(missing != null && missing.contains('Only an open release'), 'No release: ' + missing);
        }
    }
}
