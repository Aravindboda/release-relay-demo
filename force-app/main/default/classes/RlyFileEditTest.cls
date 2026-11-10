/**
 * @description Tests for build 55's Edit a file (RlyFileEdit): who may edit and when, reading a component's files on
 * the release branch and the target branch, saving an edit (the commit on the release branch, History "Edited by", the
 * checks run again) through GitHub and GitLab, and the refusals (the file changed since it was opened, a file that
 * isn't the release's, another developer). Every Git call is answered by RlyHttpMock; records are inserted before
 * Test.startTest, callouts come after. Users with the System Administrator profile and no Release Relay permission
 * sets stand for developers.
 */
@IsTest
private class RlyFileEditTest {

    // A file text that is also the JSON the GitHub contents API answers (the commit reads the file's sha from it).
    private static final String ON_BRANCH = '{"sha":"abc123","note":"Region field"}';
    private static final String CLASS_PATH = 'classes/AccountService.cls';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // A release with checks failed and pull request 42 (route, items AccountService and its test).
    private static RLY_Release__c openRelease() {
        RLY_Release__c rel = RlyReleaseTestData.release('Checks failed', 'hub');
        update new RLY_Release__c(Id = rel.Id, PR_Number__c = 42, Scan_Status__c = 'Passed', Validation_Status__c = 'Failed');
        return RlyReleaseStore.release(rel.Id);
    }

    private static RlyFileEdit.EditRequest edit(String path, String content, String expected) {
        RlyFileEdit.EditRequest r = new RlyFileEdit.EditRequest();
        r.path = path;
        r.content = content;
        r.expected = expected;
        return r;
    }

    private static RlyHttpMock gitHubMock() {
        return new RlyHttpMock()
            .match('GET', '/contents/force-app/main/default/' + CLASS_PATH + '?ref=feature/').reply(200, ON_BRANCH)
            .match('GET', '/contents/force-app/main/default/' + CLASS_PATH + '?ref=sit').reply(200, '{"sha":"def456"}')
            .match('PUT', '/contents/force-app/main/default/' + CLASS_PATH).reply(200, '{"commit":{"html_url":"https://github.com/acme/release/commit/1"}}')
            .match('POST', '/dispatches').reply(204, '');
    }

    @IsTest
    static void raiserReadsTheFilesOfAComponent() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            Test.setMock(HttpCalloutMock.class, gitHubMock());
            Test.startTest();
            RlyFileEdit.Files f = RlyFileEdit.files(rel.Id);
            List<RlyFileEdit.FileText> files = RlyFileEdit.readFile(rel.Id, 'ApexClass:AccountService');
            Test.stopTest();
            System.assert(f.canEdit, 'The raiser (an admin here) may edit: ' + f.whyNot);
            System.assertEquals(rel.Source_Branch__c, f.releaseBranch, 'Saved on the release branch');
            System.assert(f.sourceReadable, 'DEV1\'s copy can be read through Compare');
            System.assert(!f.items.isEmpty() && f.items[0].editable, 'The components are listed');
            System.assertEquals(CLASS_PATH, files[0].path, 'The class first');
            System.assertEquals(ON_BRANCH, files[0].release, 'What will be deployed');
            System.assertEquals('{"sha":"def456"}', files[0].target, 'What the target branch has');
            System.assertEquals(CLASS_PATH + '-meta.xml', files[1].path, 'Then its meta file');
        }
    }

    @IsTest
    static void savingCommitsRecordsAndChecksAgain() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            RlyHttpMock mock = gitHubMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyReleasesController.Detail d = RlyFileEdit.saveFile(rel.Id,
                JSON.serialize(edit(CLASS_PATH, 'public class AccountService {}', ON_BRANCH)));
            Test.stopTest();
            System.assertEquals('Validating', d.release.Status__c, 'The checks run again');
            String put = mock.bodyFor('/contents/force-app/main/default/' + CLASS_PATH);
            System.assert(put.contains('"branch":"' + rel.Source_Branch__c + '"') && put.contains('"sha":"abc123"'), 'Committed on the release branch: ' + put);
            System.assert(mock.bodyFor('/dispatches').contains('"mode":"check"'), 'Mode check: ' + mock.callLog());
            RLY_Release_Event__c e = [SELECT Detail__c, Actor__c, Reference__c FROM RLY_Release_Event__c
                WHERE Release__c = :rel.Id AND Event_Type__c = :RlyFileEdit.EVENT];
            System.assertEquals('Edited by ' + UserInfo.getName() + ': ' + CLASS_PATH, e.Detail__c, 'History says who edited what');
            System.assertEquals(UserInfo.getUserId(), e.Actor__c, 'By the user');
            System.assertEquals('https://github.com/acme/release/commit/1', e.Reference__c, 'Linked to the commit');
        }
    }

    @IsTest
    static void savingThroughGitLab() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            update new RLY_Git_Connection__c(Id = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1].Id, Provider__c = 'GitLab',
                Named_Credential__c = 'RLY_GitLab');
            RlyReleaseStore.forgetGit();
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', '/repository/files/force-app/main/default/' + CLASS_PATH + '/raw?ref=feature/').reply(200, 'old text')
                .match('HEAD', '/repository/files/').reply(200, '')
                .match('POST', '/repository/commits').reply(201, '{"web_url":"https://gitlab.com/acme/release/-/commit/1"}')
                .match('POST', '/pipeline').reply(201, '{"id":7}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RLY_Release__c saved = RlyFileEdit.commitEdit(rel.Id, edit(CLASS_PATH, 'new text', 'old text'));
            Test.stopTest();
            System.assertEquals('Validating', saved.Status__c, 'The checks run again');
            String commitBody = mock.bodyFor('/repository/commits');
            System.assert(commitBody.contains('"action":"update"') && commitBody.contains(rel.Source_Branch__c), 'Committed: ' + commitBody);
        }
    }

    @IsTest
    static void refusesAChangedFileAFileOfAnotherReleaseAndNothingChanged() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = openRelease();
            RlyHttpMock mock = gitHubMock();
            Test.setMock(HttpCalloutMock.class, mock);
            List<String> refused = new List<String>();
            Test.startTest();
            for (List<String> attempt : new List<List<String>>{
                    new List<String>{ CLASS_PATH, 'new', 'what it was when opened' },
                    new List<String>{ 'classes/Other.cls', 'new', ON_BRANCH },
                    new List<String>{ '../secrets.txt', 'new', ON_BRANCH },
                    new List<String>{ CLASS_PATH, ON_BRANCH, ON_BRANCH },
                    new List<String>{ CLASS_PATH, '  ', ON_BRANCH } }) {
                try {
                    RlyFileEdit.commitEdit(rel.Id, edit(attempt[0], attempt[1], attempt[2]));
                } catch (RlyReleaseException e) {
                    refused.add(e.getMessage());
                }
            }
            Test.stopTest();
            System.assertEquals(5, refused.size(), 'All refused: ' + refused);
            System.assert(refused[0].contains('changed on ' + rel.Source_Branch__c), 'Changed since opened: ' + refused[0]);
            System.assert(refused[1].contains('isn\'t a file of'), 'Not the release\'s: ' + refused[1]);
            System.assert(refused[3].startsWith('Nothing changed'), 'Nothing to save: ' + refused[3]);
            System.assert(refused[4].contains('empty'), 'A blank file is refused (D23): ' + refused[4]);
            System.assert(!mock.callLog().contains('PUT'), 'Nothing committed: ' + mock.callLog());
        }
    }

    @IsTest
    static void anotherDeveloperAndARunningReleaseCantEdit() {
        User other = RlyTestData.plainUser();
        RLY_Release__c rel;
        System.runAs(RlyTestData.admin()) {
            rel = openRelease();
        }
        System.runAs(other) {
            Test.startTest();
            RlyFileEdit.Files f = RlyFileEdit.files(rel.Id);
            String refused;
            try {
                RlyFileEdit.commitEdit(rel.Id, edit(CLASS_PATH, 'x', ON_BRANCH));
            } catch (RlyReleaseException e) {
                refused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(false, f.canEdit, 'Another developer can\'t edit');
            System.assert(refused != null && refused.contains('Only the person who raised'), 'Refused: ' + refused);
        }
        System.runAs(RlyTestData.admin()) {
            update new RLY_Release__c(Id = rel.Id, Status__c = 'Validating');
            System.assert(RlyFileEdit.whyNot(RlyReleaseStore.release(rel.Id)).contains('no run is going'), 'Not while a run goes');
        }
    }

    @IsTest
    static void pathsOfComponentTypes() {
        System.runAs(RlyTestData.admin()) {
            Test.startTest();
            List<String> layout = RlyFileEditPaths.pathsFor('Layout:Account-Account Layout');
            List<String> field = RlyFileEditPaths.pathsFor('CustomField:Account.Region__c');
            List<String> profile = RlyFileEditPaths.pathsFor('Profile:Admin');
            List<String> bundle = RlyFileEditPaths.pathsFor('LightningComponentBundle:accountCard');
            List<String> unknown = RlyFileEditPaths.pathsFor('StaticResource:logo');
            Test.stopTest();
            System.assertEquals('layouts/Account-Account Layout.layout-meta.xml', layout[0], 'Layouts as Compare reads them');
            System.assertEquals('objects/Account/fields/Region__c.field-meta.xml', field[0], 'Fields in their object');
            System.assertEquals('profiles/Admin.profile-meta.xml', profile[0], 'Profiles');
            System.assertEquals(null, bundle, 'Bundles are listed from the branch');
            System.assert(unknown.isEmpty(), 'Static resources aren\'t edited here');
        }
    }
}
