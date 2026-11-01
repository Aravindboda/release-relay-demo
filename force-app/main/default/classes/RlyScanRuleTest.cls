/**
 * @description Tests for the per-org code scan choice: RlyScanRule (Follow, On, Off against the Git connection's
 * switch), RlyPipelineOptions (the scan off option follows the release's target org) and saving the choice through
 * RlyOrgSettings. Every test runs as an existing active System Administrator through System.runAs.
 */
@IsTest
private class RlyScanRuleTest {

    private static final String SCAN_OPTION = 'scan';

    private static RLY_Git_Connection__c connection(Boolean scanOn) {
        return new RLY_Git_Connection__c(Provider__c = 'GitHub', Code_Scan__c = scanOn);
    }

    private static RLY_Org__c target(String choice) {
        return new RLY_Org__c(Name = 'Stage one', Role__c = 'Stage', Code_Scan__c = choice);
    }

    @IsTest
    static void followsTheConnection() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyScanRule.isOn(connection(true), target(RlyScanRule.FOLLOW)), 'Follow + connection on');
            System.assert(!RlyScanRule.isOn(connection(false), target(RlyScanRule.FOLLOW)), 'Follow + connection off');
            System.assert(RlyScanRule.isOn(connection(true), null), 'No target: the connection decides');
            System.assert(RlyScanRule.isOn(connection(true), target(null)), 'Blank follows');
            System.assert(!RlyScanRule.isOn(null, null), 'No connection, no scan');
            System.assertEquals('Pending', RlyScanRule.statusFor(connection(true), target(RlyScanRule.FOLLOW)), 'Scan pending');
            System.assertEquals('Not configured', RlyScanRule.statusFor(connection(false), target(null)), 'Scan not configured');
        }
    }

    @IsTest
    static void orgChoiceWins() {
        System.runAs(RlyTestData.admin()) {
            System.assert(RlyScanRule.isOn(connection(false), target(RlyScanRule.ALWAYS_SCAN)), 'Always scan');
            System.assert(!RlyScanRule.isOn(connection(true), target(RlyScanRule.NO_SCAN)), 'Don\'t scan');
            System.assertEquals('Not configured', RlyScanRule.statusFor(connection(true), target(RlyScanRule.NO_SCAN)), 'Off: not configured');
            System.assertEquals('Pending', RlyScanRule.statusFor(null, target(RlyScanRule.ALWAYS_SCAN)), 'On: pending');
            System.assertEquals(RlyScanRule.FOLLOW, RlyScanRule.choiceOf(target('Sometimes')), 'Unknown values follow');
        }
    }

    @IsTest
    static void targetOfRelease() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            RLY_Org__c sit = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1];
            update new RLY_Org__c(Id = sit.Id, Code_Scan__c = RlyScanRule.NO_SCAN);
            RLY_Release__c stored = RlyReleaseStore.release(rel.Id);
            System.assertEquals(RlyScanRule.NO_SCAN, RlyScanRule.choiceOf(RlyScanRule.targetOf(stored)), 'Read with the release');
            RLY_Release__c inMemory = new RLY_Release__c(Target_Org__c = sit.Id);
            System.assertEquals(RlyScanRule.NO_SCAN, RlyScanRule.choiceOf(RlyScanRule.targetOf(inMemory)), 'Read again');
            System.assertEquals(null, RlyScanRule.targetOf(new RLY_Release__c()), 'No target');
            System.assertEquals(null, RlyScanRule.targetOf(null), 'No release');
        }
    }

    @IsTest
    static void pipelineOptionsUseTheTarget() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c rel = RlyReleaseTestData.release('Validating', 'check');
            RLY_Org__c sit = [SELECT Id FROM RLY_Org__c WHERE Name = 'SIT' LIMIT 1];
            System.assert(!RlyPipelineOptions.forMode(RlyReleaseStore.release(rel.Id), 'check').containsKey(SCAN_OPTION), 'Follows: scan on');
            update new RLY_Org__c(Id = sit.Id, Code_Scan__c = RlyScanRule.NO_SCAN);
            System.assertEquals('off', RlyPipelineOptions.forMode(RlyReleaseStore.release(rel.Id), 'check').get(SCAN_OPTION), 'Don\'t scan');
            RLY_Git_Connection__c conn = [SELECT Id FROM RLY_Git_Connection__c LIMIT 1];
            update new RLY_Git_Connection__c(Id = conn.Id, Code_Scan__c = false);
            update new RLY_Org__c(Id = sit.Id, Code_Scan__c = RlyScanRule.ALWAYS_SCAN);
            System.assert(!RlyPipelineOptions.forMode(RlyReleaseStore.release(rel.Id), 'check').containsKey(SCAN_OPTION), 'Always scan');
        }
    }

    @IsTest
    static void savedFromThePage() {
        System.runAs(RlyTestData.admin()) {
            RLY_Org__c row = new RLY_Org__c(Name = 'Stage one', Role__c = 'Stage', Code_Scan__c = RlyScanRule.NO_SCAN);
            RlyOrgSettings.apply(row, '{"Name":"Stage one"}');
            System.assertEquals(RlyScanRule.NO_SCAN, row.Code_Scan__c, 'Kept when the page doesn\'t send it');
            RlyOrgSettings.apply(row, '{"Code_Scan__c":"On"}');
            System.assertEquals(RlyScanRule.ALWAYS_SCAN, row.Code_Scan__c, 'Always scan');
            RlyOrgSettings.apply(row, '{"Code_Scan__c":""}');
            System.assertEquals(RlyScanRule.FOLLOW, row.Code_Scan__c, 'Blank follows');
            String refused;
            try {
                RlyOrgSettings.apply(row, '{"Code_Scan__c":"Sometimes"}');
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            System.assert(refused != null && refused.startsWith('Pick a code scan choice'), refused);
        }
    }
}
