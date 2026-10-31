/**
 * @description Tests for RlyGitAdvice: the advice shown when a Git call fails or can't reach the provider.
 * Every test runs as the current user through System.runAs.
 */
@IsTest
private class RlyGitAdviceTest {

    private static RLY_Git_Connection__c conn() {
        return new RLY_Git_Connection__c(Provider__c = 'GitHub', Named_Credential__c = 'RLY_GitHub', Repository__c = 'acme/release');
    }

    private static HttpResponse response(Integer code, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(code);
        res.setBody(body);
        return res;
    }

    private static String failure(Integer code) {
        try {
            RlyGitAdvice.requireSuccess(response(code, '{"message":"x"}'), 'Reading', conn());
        } catch (RlyGit.GitException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void successPassesThrough() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assertEquals(null, failure(200), 'A 2xx answer is not an error');
            System.assertEquals(null, failure(204), 'No content is fine');
        }
    }

    @IsTest
    static void knownStatusesGetAdvice() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            System.assert(failure(401).contains('Named Credential RLY_GitHub was refused'), 'Names the credential');
            System.assert(failure(403).contains('lacks permission'), 'Permission advice');
            System.assert(failure(404).contains('Not found'), 'Not found advice');
            System.assert(failure(422).contains('rejected the request'), 'Rejected advice');
        }
    }

    @IsTest
    static void unknownStatusStillExplains() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String m = failure(500);
            System.assert(m.startsWith('Reading failed with HTTP 500.'), 'Says what failed: ' + m);
        }
    }

    @IsTest
    static void calloutProblemsGetAdvice() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String credential = RlyGitAdvice.forCallout('The callout couldn\'t access the endpoint: callout:RLY_GitHub', conn());
            String other = RlyGitAdvice.forCallout('Read timed out', conn());
            String blank = RlyGitAdvice.forCallout(null, conn());
            System.assert(credential.contains('External Credential Principal Access'), 'Credential advice');
            System.assert(other.startsWith('Couldn\'t reach GitHub: Read timed out'), 'Reach advice: ' + other);
            System.assert(blank.startsWith('Couldn\'t reach GitHub'), 'Blank message handled');
        }
    }
}
