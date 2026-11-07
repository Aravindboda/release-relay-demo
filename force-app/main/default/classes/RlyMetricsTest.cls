/**
 * @description Tests for the Metrics tab (RlyMetricsController and the RlyMetrics* classes): deploys, lead time through a
 * promotion's carried release, change failure rate with a failed deploy, a rollback and a hotfix, time to restore, approval
 * wait, checks failing with a code scan, why checks fail and conflict files, the developer org filter, the filter's
 * defaults, weeks and months, and medians. History events are inserted directly, dated relative to one moment; nothing
 * depends on org data. Every test runs as an active System Administrator through System.runAs.
 */
@IsTest
private class RlyMetricsTest {

    private static final Datetime NOW = System.now();
    private static Id devOrgId;

    private class World {
        private Id dev;
        private Id sit;
        private Id prod;
        private RLY_Release__c feature;
        private RLY_Release__c hotfix;
        private RLY_Release__c later;
        private RLY_Release__c promotion;
    }

    private static RLY_Release__c release(String title, Id target, Integer daysAgo) {
        RLY_Release__c r = new RLY_Release__c(Title__c = title, Status__c = 'Deployed', Mode__c = 'Org changes',
            Request_Type__c = 'Changes', Source_Org__c = devOrgId, Target_Org__c = target, Org_Label__c = 'DEV1',
            Target_Branch__c = 'sit', Scan_Status__c = 'Passed', Validation_Status__c = 'Passed', Approval_Status__c = 'Approved',
            Deploy_Status__c = 'Deployed', Component_Count__c = 1);
        insert r;
        Test.setCreatedDate(r.Id, NOW.addDays(-daysAgo));
        return r;
    }

    // "Validation Failed" → a Validation event saying Failed (with a conflict); the org is the release's target.
    private static RLY_Release_Event__c event(RLY_Release__c r, String typeAndOutcome, Decimal daysAgo) {
        String type = typeAndOutcome.substringBefore(' ');
        String outcome = typeAndOutcome.substringAfter(' ');
        String detail = type == 'Scan' ? 'Code scan ' + outcome + ' (2 blocking)'
            : type + ' ' + outcome + (outcome == 'Failed' ? ': conflicts with the target branch' : '');
        return new RLY_Release_Event__c(Release__c = r.Id, Event_Type__c = type, Org__c = type == 'Scan' ? null : r.Target_Org__c,
            Occurred_On__c = NOW.addMinutes(-(daysAgo * 24 * 60).intValue()), Detail__c = detail);
    }

    // A feature raised 20 days ago (conflict, then passed, deployed to SIT, promoted to PROD 4 days ago), a hotfix that
    // failed then deployed to PROD, another deploy, a rollback, a failed code scan and one deploy in the period before.
    private static World world() {
        World w = new World();
        w.dev = RlyReleaseTestData.route().Id;
        devOrgId = w.dev;
        for (RLY_Org__c o : [SELECT Id, Name FROM RLY_Org__c WHERE Name IN ('SIT', 'PROD')]) {
            if (o.Name == 'SIT') {
                w.sit = o.Id;
            } else {
                w.prod = o.Id;
            }
        }
        w.feature = release('Invoice totals', w.sit, 20);
        w.hotfix = release('Tax fix', w.prod, 10);
        w.later = release('Labels', w.prod, 3);
        w.promotion = release('Promote to PROD', w.prod, 5);
        update new List<RLY_Release__c>{
            new RLY_Release__c(Id = w.hotfix.Id, Is_Hotfix__c = true),
            new RLY_Release__c(Id = w.promotion.Id, Release_Type__c = 'Promotion', Carried_Releases__c = w.feature.Id),
            new RLY_Release__c(Id = w.feature.Id, Validation_Status__c = 'Failed',
                Validation_Result__c = '{"status":"Conflict","conflicts":[{"file":"force-app/main/default/classes/InvoiceTotals.cls"}]}')
        };
        insert new List<RLY_Release_Event__c>{
            event(w.feature, 'Validation Failed', 19), event(w.feature, 'Validation Passed', 18),
            event(w.feature, 'Approved', 17), event(w.feature, 'Deployed', 16),
            event(w.promotion, 'Validation Passed', 6), event(w.promotion, 'Approved', 5), event(w.promotion, 'Deployed', 4),
            event(w.hotfix, 'Scan Failed', 3.5), event(w.hotfix, 'Deploy_Failed', 3), event(w.hotfix, 'Deployed', 2),
            event(w.later, 'Deployed', 1.5), event(w.later, 'Rolled_Back', 1), event(w.later, 'Deployed', 100)
        };
        return w;
    }

    private static Map<String, RlyMetricsViews.Tile> tiles(RlyMetricsViews.Metrics m) {
        Map<String, RlyMetricsViews.Tile> out = new Map<String, RlyMetricsViews.Tile>();
        for (RlyMetricsViews.Tile t : m.tiles) {
            out.put(t.key, t);
        }
        return out;
    }

    private static String filter(Id orgId, Id devOrgId, Integer days) {
        return JSON.serialize(new Map<String, Object>{ 'orgId' => orgId, 'devOrgId' => devOrgId, 'days' => days });
    }

    @IsTest
    static void productionGetsTheFourMeasures() {
        System.runAs(RlyTestData.admin()) {
            World w = world();
            Test.startTest();
            RlyMetricsViews.Metrics m = RlyMetricsController.metrics(filter(w.prod, null, 90));
            Test.stopTest();
            Map<String, RlyMetricsViews.Tile> t = tiles(m);
            System.assertEquals(3, t.get('deploys').value.intValue(), 'Three deploys to PROD in 90 days');
            System.assertEquals(1, t.get('deploys').previous.intValue(), 'One in the 90 days before');
            System.assert(t.get('deploys').higherIsBetter && t.get('deploys').dora, 'More deploys is better; a DORA measure');
            // Lead time: the promotion carries the feature raised 20 days ago (16 days), the hotfix 8 days, the later one 1.5.
            System.assertEquals(192.0, t.get('leadTime').value, 'Median of 384, 192 and 36 hours');
            System.assertEquals('median of 3', t.get('leadTime').detail, 'Three releases measured');
            System.assertEquals(75, t.get('failureRate').value.intValue(), 'Failed deploy, rollback and hotfix over four tries');
            System.assertEquals('3 of 4', t.get('failureRate').detail, 'Its counts');
            System.assertEquals(24.0, t.get('restore').value, 'From the failed deploy to the next deploy');
            System.assertEquals(24.0, t.get('approvalWait').value, 'From the passed check to the approval');
            System.assertEquals(50, t.get('checksFailing').value.intValue(), 'A failed scan and a passed validation');
            System.assertEquals(1, m.scanFailures, 'The scan counts as a code scan failure');
            System.assertEquals(true, m.byWeek, 'Weeks up to 90 days');
            System.assertEquals(6, m.series.size(), 'A chart per tile');
        }
    }

    @IsTest
    static void whyChecksFailAndTheFilesInConflicts() {
        System.runAs(RlyTestData.admin()) {
            World w = world();
            Test.startTest();
            RlyMetricsViews.Metrics m = RlyMetricsController.metrics(filter(w.sit, null, 30));
            RlyMetricsViews.Reasons r = RlyMetricsController.checkReasons(m.failedReleaseIds);
            List<Id> orgIds = new List<Id>{ w.dev, w.sit, w.prod };
            RlyMetricsViews.Reasons none = RlyMetricsController.checkReasons(orgIds);
            List<RLY_Release__c> many = new List<RLY_Release__c>();
            for (Integer i = 0; i < 11; i++) {
                many.add(new RLY_Release__c(Title__c = 'R' + i, Status__c = 'Closed', Mode__c = 'Org changes', Request_Type__c = 'Changes',
                    Source_Org__c = w.dev, Target_Org__c = w.sit));
            }
            insert many;
            String tooMany;
            try {
                RlyMetricsController.checkReasons(new List<Id>(new Map<Id, RLY_Release__c>(many).keySet()));
            } catch (AuraHandledException e) {
                tooMany = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(new List<Id>{ w.feature.Id }, m.failedReleaseIds, 'The release whose check failed');
            System.assertEquals('Conflicts with the branch', r.reasons[0].label, 'Sorted by its latest result');
            System.assertEquals('InvoiceTotals.cls', r.files[0].label, 'The file in the conflict');
            System.assertEquals(50, tiles(m).get('checksFailing').value.intValue(), 'One of two validations failed');
            System.assert(none.reasons.isEmpty(), 'Ids of other objects are left out');
            System.assert(tooMany != null && tooMany.contains('at most 10'), 'Ten releases a call: ' + tooMany);
        }
    }

    @IsTest
    static void theDeveloperOrgFilterAndAllOrgs() {
        System.runAs(RlyTestData.admin()) {
            World w = world();
            Test.startTest();
            RlyMetricsViews.Metrics other = RlyMetricsController.metrics(filter(w.prod, w.sit, 90));
            RlyMetricsViews.Metrics everyOrg = RlyMetricsController.metrics(filter(null, w.dev, 365));
            Test.stopTest();
            System.assertEquals(null, tiles(other).get('leadTime').value, 'No release came from that org');
            System.assertEquals(3, tiles(other).get('deploys').value.intValue(), 'Deploys are per org, not per developer org');
            System.assertEquals(5, tiles(everyOrg).get('deploys').value.intValue(), 'Every org over a year: SIT, PROD and the older one');
            System.assertEquals(false, everyOrg.byWeek, 'Months beyond 90 days');
        }
    }

    @IsTest
    static void optionsAndFilterDefaults() {
        System.runAs(RlyTestData.admin()) {
            World w = world();
            Test.startTest();
            RlyMetricsViews.Options o = RlyMetricsController.options();
            RlyMetricsFilter bad = RlyMetricsFilter.parse('{not json');
            RlyMetricsFilter odd = RlyMetricsFilter.parse(filter(null, null, 45));
            RlyMetricsFilter wrongId = RlyMetricsFilter.parse(JSON.serialize(new Map<String, Object>{ 'orgId' => w.feature.Id, 'days' => '180' }));
            Test.stopTest();
            System.assertEquals(w.prod, o.defaultOrgId, 'Production first');
            System.assertEquals(1, o.devOrgs.size(), 'DEV1 is a developer org');
            System.assertEquals(2, o.orgs.size(), 'SIT and PROD');
            System.assertEquals(90, bad.days, 'Bad JSON: the default period');
            System.assertEquals(90, odd.days, 'Only the periods offered');
            System.assertEquals(null, wrongId.orgId, 'Only an org Id');
            System.assertEquals(180, wrongId.days, 'Digits as text are read');
        }
    }

    @IsTest
    static void bucketsAndMedians() {
        System.runAs(RlyTestData.admin()) {
            RlyMetricsFilter f = RlyMetricsFilter.parse(filter(null, null, 30));
            Test.startTest();
            RlyMetricsBuckets weeks = new RlyMetricsBuckets(f);
            List<RlyMetricsViews.Point> points = weeks.points();
            Date firstDay = Date.valueOf(points[0].day);
            Integer dow = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(firstDay), 7);
            Test.stopTest();
            System.assertEquals(0, dow, 'Weeks start on a Monday');
            System.assertEquals(0, weeks.indexOf(firstDay), 'The first day is in the first week');
            System.assertEquals(-1, weeks.indexOf(firstDay.addDays(-1)), 'Before the period');
            System.assertEquals(-1, weeks.indexOf((Date) null), 'No day');
            System.assertEquals(2.5, RlyMetricsBuckets.median(new List<Decimal>{ 4, 1, 2, 3 }), 'Even count: the two middle ones');
            System.assertEquals(3.0, RlyMetricsBuckets.median(new List<Decimal>{ 5, 3, 1 }), 'Odd count: the middle one');
            System.assertEquals(null, RlyMetricsBuckets.median(new List<Decimal>()), 'Nothing to measure');
        }
    }

    @IsTest
    static void eachReasonFromALatestResult() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c failed = new RLY_Release__c(Validation_Status__c = 'Failed');
            Test.startTest();
            String gates = RlyMetricsChecks.reasonOf(failed, (Map<String, Object>) JSON.deserializeUntyped('{"gates":{"passed":false}}'));
            String tests = RlyMetricsChecks.reasonOf(failed, (Map<String, Object>) JSON.deserializeUntyped('{"testFailures":[{"name":"T"}]}'));
            String deploy = RlyMetricsChecks.reasonOf(failed, (Map<String, Object>) JSON.deserializeUntyped('{"componentErrors":[{"name":"C"}]}'));
            String coverage = RlyMetricsChecks.reasonOf(failed, (Map<String, Object>) JSON.deserializeUntyped('{"coverageWarnings":[{"name":"C"}]}'));
            String other = RlyMetricsChecks.reasonOf(failed, new Map<String, Object>());
            String fixedSince = RlyMetricsChecks.reasonOf(new RLY_Release__c(Validation_Status__c = 'Passed'), new Map<String, Object>());
            String scanAccepted = RlyMetricsFlow.outcomeOf(new RLY_Release_Event__c(Event_Type__c = 'Scan', Detail__c = 'Code scan findings accepted: ok'));
            String validationError = RlyMetricsFlow.outcomeOf(new RLY_Release_Event__c(Event_Type__c = 'Validation', Detail__c = 'Validation in SIT Error'));
            Test.stopTest();
            System.assertEquals('Quality gates', gates, 'A gate that didn\'t pass');
            System.assertEquals('Test failures', tests, 'Failed tests');
            System.assertEquals('Deploy errors', deploy, 'Component errors');
            System.assertEquals('Code coverage', coverage, 'Coverage only');
            System.assertEquals('Other', other, 'Nothing to tell');
            System.assertEquals('Fixed since', fixedSince, 'Passed since');
            System.assertEquals(null, scanAccepted, 'An accepted scan isn\'t a run check');
            System.assertEquals('Failed', validationError, 'An error counts as failed');
        }
    }
}
