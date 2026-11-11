/**
 * @description Tests for the lines a release keeps or takes out (build 60, D40): RlyKeepRules and RlyKeepFile. Every test
 * runs as an existing active System Administrator through System.runAs; releases are inserted by RlyReleaseTestData.
 */
@IsTest
private class RlyKeepRulesTest {

    private static RlyKeepRules.KeepItem item(String component, String line) {
        RlyKeepRules.KeepItem i = new RlyKeepRules.KeepItem();
        i.component = component;
        i.item = line;
        return i;
    }

    @IsTest
    static void checksLinesAndCommitsThem() {
        System.runAs(RlyTestData.admin()) {
            Set<String> brought = new Set<String>{ 'Layout:Account-Account Layout', 'PermissionSet:E2E_XML_Perms' };
            List<RlyKeepRules.KeepItem> items = RlyKeepRules.checked(new List<RlyKeepRules.KeepItem>{
                item(' layout:account-account layout ', 'layoutItems:Fax'), item('PermissionSet:E2E_XML_Perms', 'fieldPermissions:Account.SLA__c') }, brought);
            System.assertEquals(2, items.size(), 'Both lines are checked');
            System.assertEquals('layout:account-account layout', items[0].component, 'Trimmed; the case is matched without changing it');
            System.assertEquals(null, RlyKeepRules.toField(new List<RlyKeepRules.KeepItem>()), 'Nothing taken out: the field stays empty');
            System.assertEquals(0, RlyKeepRules.checked(null, brought).size(), 'No lines sent');
            System.assertEquals(0, RlyKeepRules.fromField('not json').size(), 'An unreadable value reads as none');

            RLY_Release__c rel = RlyReleaseTestData.release('Retrieving', null);
            System.assertEquals(null, RlyKeepFile.fileFor(rel, 'feature/x'), 'No file while nothing is taken out');
            update new RLY_Release__c(Id = rel.Id, Remove_On_Purpose__c = RlyKeepRules.toField(items));
            RlyGitFile f = RlyKeepFile.fileFor(rel, 'feature/x');
            String body = EncodingUtil.base64Decode(f.base64Content).toString();
            System.assertEquals('.relay-inbox/' + rel.Name + '-keep.json', f.path, 'The inbox file beside the zip');
            System.assert(body.contains('"removeOnPurpose"') && body.contains('layoutItems:Fax') && body.contains('fieldPermissions:Account.SLA__c'), body);
        }
    }

    @IsTest
    static void refusesLinesItCantTakeOut() {
        System.runAs(RlyTestData.admin()) {
            Set<String> brought = new Set<String>{ 'Layout:Account-Account Layout', 'Profile:Admin' };
            System.assert(refused(item('Layout:Account-Account Layout', 'sections:Info'), brought).contains('isn\'t a line'), 'Unknown element');
            System.assert(refused(item('Layout:Account-Account Layout', 'layoutItems:'), brought).contains('isn\'t a line'), 'No key');
            System.assert(refused(item('Layout:Other', 'layoutItems:Fax'), brought).contains('isn\'t in this release'), 'Not in the release');
            System.assert(refused(item('Profile:Admin', 'fieldPermissions:Account.SLA__c'), brought).contains('isn\'t in this release'), 'Profiles go through Profile access');
            List<RlyKeepRules.KeepItem> many = new List<RlyKeepRules.KeepItem>();
            for (Integer n = 0; n <= RlyKeepRules.MAX_ITEMS; n++) {
                many.add(item('Layout:Account-Account Layout', 'layoutItems:F' + n));
            }
            String message;
            try {
                RlyKeepRules.checked(many, brought);
            } catch (RlyReleaseException e) {
                message = e.getMessage();
            }
            System.assert(message != null && message.contains(String.valueOf(RlyKeepRules.MAX_ITEMS)), 'Too many lines');
        }
    }

    private static String refused(RlyKeepRules.KeepItem i, Set<String> brought) {
        try {
            RlyKeepRules.checked(new List<RlyKeepRules.KeepItem>{ i }, brought);
        } catch (RlyReleaseException e) {
            return e.getMessage();
        }
        return '';
    }
}
