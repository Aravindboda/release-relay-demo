/**
 * @description Tests for RlyReleaseSize: a release past the size limits, or an add past MAX_ADD, is refused with a clear
 * message instead of being cut short. No callouts, no org data. Every test runs as an active System Administrator
 * through System.runAs.
 */
@IsTest
private class RlyReleaseSizeTest {

    private static List<RlyRaiseService.Item> items(Integer n, Integer nameLength) {
        List<RlyRaiseService.Item> out = new List<RlyRaiseService.Item>();
        for (Integer i = 0; i < n; i++) {
            RlyRaiseService.Item it = new RlyRaiseService.Item();
            it.type = 'ApexClass';
            it.name = ('C' + i).rightPad(nameLength, 'x');
            out.add(it);
        }
        return out;
    }

    private static String refusal(RlyRaiseService.RaiseRequest req) {
        try {
            RlyReleaseSize.checkRaise(req);
            return null;
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
    }

    @IsTest
    static void bigReleasesAreRefusedClearly() {
        System.runAs(RlyTestData.admin()) {
            RlyRaiseService.RaiseRequest tooMany = new RlyRaiseService.RaiseRequest();
            tooMany.items = items(RlyReleaseSize.MAX_COMPONENTS + 1, 10);
            RlyRaiseService.RaiseRequest tooLong = new RlyRaiseService.RaiseRequest();
            tooLong.items = items(300, 250);
            RlyRaiseService.RaiseRequest deletes = new RlyRaiseService.RaiseRequest();
            deletes.deletions = items(RlyReleaseSize.MAX_DELETIONS + 1, 10);
            RlyRaiseService.RaiseRequest fine = new RlyRaiseService.RaiseRequest();
            fine.items = items(50, 20);
            Test.startTest();
            String a = refusal(tooMany);
            String b = refusal(tooLong);
            String c = refusal(deletes);
            String d = refusal(fine);
            Test.stopTest();
            System.assert(a != null && a.contains('split the release'), 'Too many components: ' + a);
            System.assert(b != null && b.contains('too long for one pipeline run'), 'Names too long: ' + b);
            System.assert(c != null && c.contains('deletions'), 'Too many deletions: ' + c);
            System.assertEquals(null, d, 'A normal release passes');
        }
    }

    @IsTest
    static void anAddTakesAtMostMaxAdd() {
        System.runAs(RlyTestData.admin()) {
            String big;
            String full;
            Test.startTest();
            try {
                RlyReleaseSize.checkAdd(10, items(RlyReleaseSize.MAX_ADD + 1, 10), new List<String>());
            } catch (RlyReleaseException e) {
                big = e.getMessage();
            }
            try {
                RlyReleaseSize.checkAdd(RlyReleaseSize.MAX_COMPONENTS, items(1, 10), null);
            } catch (RlyReleaseException e) {
                full = e.getMessage();
            }
            RlyReleaseSize.checkAdd(5, items(3, 10), new List<String>{ 'ApexClass:Old' });
            Test.stopTest();
            System.assert(big != null && big.contains('at most ' + RlyReleaseSize.MAX_ADD), 'Add capped: ' + big);
            System.assert(full != null && full.contains('split the release'), 'The release is full: ' + full);
        }
    }
}
