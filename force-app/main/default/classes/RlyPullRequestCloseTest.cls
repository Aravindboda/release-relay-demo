/**
 * @description Tests for RlyPullRequestClose: the comment and the close are independent, and each problem is
 * reported in words. Every test runs as an active System Administrator through System.runAs.
 */
@IsTest
private class RlyPullRequestCloseTest {

    private static void connect(String repository) {
        insert new RLY_Git_Connection__c(Provider__c = 'GitHub', Repository__c = repository, Named_Credential__c = 'RLY_GitHub');
    }

    private static RLY_Release__c pr42() {
        return new RLY_Release__c(PR_Number__c = 42);
    }

    @IsTest
    static void bothWork() {
        System.runAs(RlyTestData.admin()) {
            connect('acme/release');
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/issues/42/comments').reply(201, '{"id":1}')
                .match('PATCH', '/pulls/42').reply(200, '{"state":"closed"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<String> problems = RlyPullRequestClose.closeWithComment(pr42(), 'Rejected');
            Test.stopTest();
            System.assert(problems.isEmpty(), 'No problems: ' + problems);
            System.assertEquals(2, mock.calls.size(), 'Commented and closed');
        }
    }

    @IsTest
    static void bothFailAreReported() {
        System.runAs(RlyTestData.admin()) {
            connect('acme/release');
            RlyHttpMock mock = new RlyHttpMock()
                .match('POST', '/issues/42/comments').reply(500, '{"message":"Server error"}')
                .match('PATCH', '/pulls/42').reply(403, '{"message":"Resource not accessible"}');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<String> problems = RlyPullRequestClose.closeWithComment(pr42(), 'Rejected');
            Test.stopTest();
            System.assertEquals(2, problems.size(), 'Two problems: ' + problems);
            System.assert(problems[0].startsWith('the comment couldn\'t be posted'), problems[0]);
            System.assert(problems[1].startsWith('the pull request couldn\'t be closed'), problems[1]);
        }
    }

    @IsTest
    static void badConnectionStopsEarly() {
        System.runAs(RlyTestData.admin()) {
            connect('not a repository');
            RlyHttpMock mock = new RlyHttpMock();
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            List<String> problems = RlyPullRequestClose.closeWithComment(pr42(), 'Rejected');
            Test.stopTest();
            System.assertEquals(1, problems.size(), 'One problem: ' + problems);
            System.assert(problems[0].startsWith('the pull request couldn\'t be closed'), problems[0]);
            System.assert(mock.calls.isEmpty(), 'No callouts');
        }
    }
}
