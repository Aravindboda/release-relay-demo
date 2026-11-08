/**
 * @description Tests for build 55's packages per org (RlyOrgPackages, RlyOrgPackageStore, RlyOrgPackagesController,
 * RlyOrgPackageNightly) and raising from a stage (RlyRaiseRoute, RlyReleaseStart): the options every run gets
 * (known, sourceMissing on a raise only, targetMissing, a higher org that lacks a package, "treat as not installed",
 * an org never read, no packages at all), the matrix, Check now (one tooling query per org, mocked), the marks, Can
 * raise releases and the nightly read. Every test runs as RlyTestData.admin(); the orgs are inserted by each test.
 */
@IsTest
private class RlyOrgPackagesTest {

    private static final String ARCH = '{"ns":"arch","name":"Archiver","version":"2.14"}';
    private static final String DOCGEN = '{"ns":"docgen","name":"Document Generator","version":"5.1"}';
    private static final String SVK = '{"ns":"svk","name":"Survey Kit","version":"1.3"}';

    @TestSetup
    static void setup() {
        RlyTestData.assignPermissionSet('RLY_Admin');
    }

    // DEV1 (docgen) → SIT (arch, docgen) → PROD (arch, docgen 5.0, svk): the board's route.
    private static void packagedRoute() {
        RlyReleaseTestData.route();
        Datetime at = System.now().addMinutes(-5);
        update new List<RLY_Org__c>{
            new RLY_Org__c(Id = orgId('DEV1'), Packages__c = '[' + DOCGEN + ']', Packages_Checked__c = at),
            new RLY_Org__c(Id = orgId('SIT'), Packages__c = '[' + ARCH + ',' + DOCGEN + ']', Packages_Checked__c = at),
            new RLY_Org__c(Id = orgId('PROD'), Packages__c = '[' + ARCH + ',' + DOCGEN.replace('5.1', '5.0') + ',' + SVK + ']',
                Packages_Checked__c = at)
        };
    }

    private static Id orgId(String name) {
        return [SELECT Id FROM RLY_Org__c WHERE Name = :name LIMIT 1].Id;
    }

    private static RLY_Release__c rel(String sourceName, String targetName) {
        return new RLY_Release__c(Source_Org__c = orgId(sourceName), Target_Org__c = orgId(targetName));
    }

    // The option's list, comma separated.
    private static String listOf(Map<String, Object> p, String key) {
        return String.join((List<String>) p.get(key), ',');
    }

    @IsTest
    static void raiseFromDev1KeepsWhatDev1LacksAndLeavesOutWhatSitLacks() {
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
            Test.startTest();
            Map<String, Object> raise = RlyOrgPackages.optionsFor(rel('DEV1', 'SIT'), 'hub', RlyOrgPackageStore.orgs());
            Map<String, Object> check = RlyOrgPackages.optionsFor(rel('DEV1', 'SIT'), 'check', RlyOrgPackageStore.orgs());
            Test.stopTest();
            System.assertEquals('arch,docgen,svk', listOf(raise, 'known'), 'Every namespace on the route');
            System.assertEquals('arch,svk', listOf(raise, 'sourceMissing'), 'DEV1 lacks arch and svk');
            System.assertEquals('svk', listOf(raise, 'targetMissing'), 'SIT lacks svk');
            System.assertEquals('', listOf(check, 'sourceMissing'), 'Only a raise or added changes put references back');
            System.assertEquals('svk', listOf(check, 'targetMissing'), 'Check again leaves svk out of SIT');
        }
    }

    @IsTest
    static void higherOrgThatLacksAPackageGetsTargetMissing() {
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
            // PROD (the higher org) lacks arch; SIT has it.
            update new RLY_Org__c(Id = orgId('PROD'), Packages__c = '[' + DOCGEN + ',' + SVK + ']');
            Test.startTest();
            Map<String, Object> promote = RlyOrgPackages.optionsFor(rel('SIT', 'PROD'), 'promote', RlyOrgPackageStore.orgs());
            Map<String, Object> mergeRun = RlyOrgPackages.optionsFor(rel('SIT', 'PROD'), 'mergeRun', RlyOrgPackageStore.orgs());
            Map<String, Object> backPromote = RlyOrgPackages.optionsFor(rel('PROD', 'DEV1'), 'sync', RlyOrgPackageStore.orgs());
            Test.stopTest();
            System.assertEquals('arch', listOf(promote, 'targetMissing'), 'The higher org lacks arch: left out there');
            System.assertEquals('', listOf(promote, 'sourceMissing'), 'A promotion puts nothing back');
            System.assertEquals('arch', listOf(mergeRun, 'targetMissing'), 'The deploy into PROD leaves arch out too');
            System.assertEquals('arch,svk', listOf(backPromote, 'targetMissing'), 'Back promote to DEV1');
        }
    }

    @IsTest
    static void treatAsNotInstalledCountsAsMissing() {
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
            Test.startTest();
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackagesController.markNotInstalled(orgId('SIT'), 'ARCH');
            Map<String, Object> check = RlyOrgPackages.optionsFor(rel('DEV1', 'SIT'), 'check', RlyOrgPackageStore.orgs());
            RlyOrgPackageMatrix.Matrix back = RlyOrgPackagesController.countInstalled(orgId('SIT'), 'arch');
            Test.stopTest();
            System.assert(m.message.contains('treated as not installed in SIT'), 'Says so: ' + m.message);
            System.assertEquals('arch,svk', listOf(check, 'targetMissing'), 'Marked arch is left out of SIT');
            System.assert(listOf(check, 'known').contains('arch'), 'PROD still has arch, so it stays known');
            System.assertEquals(null, [SELECT Packages_Off__c FROM RLY_Org__c WHERE Id = :orgId('SIT')].Packages_Off__c, 'Mark taken off');
            System.assert(back.message.contains('counts as installed'), 'Says so: ' + back.message);
        }
    }

    @IsTest
    static void noPackagesOrNeverReadChangesNothing() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c relCheck = RlyReleaseTestData.release('Checks failed', 'hub');
            Test.startTest();
            Map<String, Object> none = RlyPipelineOptions.forMode(RlyReleaseStore.release(relCheck.Id), 'check');
            update new RLY_Org__c(Id = orgId('PROD'), Packages__c = '[' + ARCH + ']', Packages_Checked__c = System.now());
            Map<String, Object> unread = RlyOrgPackages.optionsFor(rel('DEV1', 'SIT'), 'hub',
                [SELECT Id, Name, Packages__c, Packages_Checked__c, Packages_Off__c FROM RLY_Org__c]);
            Test.stopTest();
            System.assert(!none.containsKey(RlyOrgPackages.OPTION), 'No package anywhere: no packages option: ' + none);
            System.assertEquals('', listOf(unread, 'sourceMissing'), 'DEV1 was never read: nothing put back');
            System.assertEquals('', listOf(unread, 'targetMissing'), 'SIT was never read: nothing left out');
            System.assertEquals(null, RlyOrgPackages.optionsFor(null, 'hub', new List<RLY_Org__c>()), 'No orgs: no option');
        }
    }

    @IsTest
    static void everyRunOfAReleaseCarriesThePackages() {
        System.runAs(RlyTestData.admin()) {
            RLY_Release__c relCheck = RlyReleaseTestData.release('Checks failed', 'hub');
            Datetime at = System.now();
            update new List<RLY_Org__c>{
                new RLY_Org__c(Id = orgId('DEV1'), Packages__c = '[]', Packages_Checked__c = at),
                new RLY_Org__c(Id = orgId('SIT'), Packages__c = '[' + ARCH + ']', Packages_Checked__c = at)
            };
            Test.startTest();
            Map<String, Object> options = RlyPipelineOptions.forMode(RlyReleaseStore.release(relCheck.Id), 'hub');
            Test.stopTest();
            Map<String, Object> p = (Map<String, Object>) options.get(RlyOrgPackages.OPTION);
            System.assertNotEquals(null, p, 'The packages option is there: ' + options);
            System.assertEquals('arch', listOf(p, 'sourceMissing'), 'DEV1 lacks arch: ' + p);
            System.assertEquals('', listOf(p, 'targetMissing'), 'SIT has it: ' + p);
        }
    }

    @IsTest
    static void matrixShowsVersionsAndMissing() {
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
            Test.startTest();
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackagesController.matrix();
            Test.stopTest();
            System.assertEquals(new List<String>{ 'DEV1', 'SIT', 'PROD' }, new List<String>{ m.orgs[0].name, m.orgs[1].name, m.orgs[2].name },
                'Developer orgs, then the route');
            System.assertEquals('Archiver', m.packages[0].name, 'Packages by name');
            System.assertEquals(false, m.packages[0].cells[0].installed, 'Archiver isn\'t in DEV1');
            System.assertEquals('2.14', m.packages[0].cells[1].version, 'Archiver 2.14 in SIT');
            System.assertEquals(new List<String>{ 'DEV1' }, m.packages[0].missingIn, 'Missing in DEV1 only');
            System.assertEquals('5.0', m.packages[1].cells[2].version, 'Different versions are shown');
            System.assertEquals(true, m.isAdmin, 'An admin marks and checks');
            System.assertEquals(true, m.orgs[0].canRaise, 'Developer orgs raise releases');
            System.assertEquals(true, m.orgs[1].canRaiseSwitch, 'SIT can be switched');
            System.assertEquals('PROD', m.orgs[1].raisesInto, 'SIT raises into PROD');
            System.assertEquals(false, m.orgs[2].canRaiseSwitch, 'The hub is the last stop');
        }
    }

    @IsTest
    static void checkNowReadsEveryOrgOnceAndSavesItsPackages() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            RlyHttpMock mock = new RlyHttpMock()
                .match('GET', 'sit.my.salesforce.com').reply(200, '{"done":true,"records":[{"SubscriberPackage":{"Name":"Archiver",'
                    + '"NamespacePrefix":"arch"},"SubscriberPackageVersion":{"MajorVersion":2,"MinorVersion":14,"PatchVersion":0}},'
                    + '{"SubscriberPackage":{"Name":"Unmanaged","NamespacePrefix":null},"SubscriberPackageVersion":{"MajorVersion":1,"MinorVersion":0}}]}')
                .match('GET', 'dev1.my.salesforce.com').reply(200, '{"done":true,"records":[]}')
                .match('GET', 'prod.my.salesforce.com').reply(500, '[{"message":"Down","errorCode":"SERVER_UNAVAILABLE"}]');
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackagesController.checkNow();
            Test.stopTest();
            RLY_Org__c sit = [SELECT Packages__c, Packages_Checked__c FROM RLY_Org__c WHERE Id = :orgId('SIT')];
            RLY_Org__c dev = [SELECT Packages__c FROM RLY_Org__c WHERE Id = :orgId('DEV1')];
            RLY_Org__c prod = [SELECT Packages__c, Packages_Checked__c FROM RLY_Org__c WHERE Id = :orgId('PROD')];
            System.assert(sit.Packages__c.contains('"ns":"arch"') && sit.Packages__c.contains('2.14'), 'SIT has Archiver: ' + sit.Packages__c);
            System.assert(!sit.Packages__c.contains('Unmanaged'), 'Packages without a namespace aren\'t tracked: ' + sit.Packages__c);
            System.assertEquals('[]', dev.Packages__c, 'DEV1 read, no packages');
            System.assertEquals(null, prod.Packages_Checked__c, 'PROD couldn\'t be read: it keeps what it had');
            System.assert(m.errors.containsKey('PROD'), 'The page says PROD wasn\'t read: ' + m.errors);
            System.assert(m.message.startsWith('Checked: 1 package in 2 orgs, 1 org not read'), m.message);
            System.assertEquals(3, mock.calls.size(), 'One query per org: ' + mock.callLog());
        }
    }

    @IsTest
    static void canRaiseReleasesFromAStage() {
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
            String retired;
            try {
                RlyRaiseRoute.source(orgId('SIT'));
            } catch (RlyReleaseException e) {
                retired = e.getMessage();
            }
            Test.startTest();
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackagesController.allowRaising(orgId('SIT'));
            RLY_Org__c source = RlyRaiseRoute.source(orgId('SIT'));
            RLY_Org__c target = RlyRaiseRoute.target(source);
            RlyReleaseStart.Start s = RlyReleaseStart.build();
            String devRefused;
            try {
                RlyOrgPackagesController.allowRaising(orgId('DEV1'));
            } catch (Exception e) {
                devRefused = e.getMessage();
            }
            Test.stopTest();
            System.assertEquals(RlyRaiseRoute.STAGE_RETIRED, retired, 'Off: a stage isn\'t a source');
            System.assert(m.orgs[1].canRaise, 'SIT raises releases now');
            System.assertEquals('PROD', target.Name, 'A release from SIT goes to the next stop');
            System.assertEquals('PROD', s.raiseTargets.get(String.valueOf(orgId('SIT'))).name, 'New release says where it goes');
            Boolean offered = false;
            for (RLY_Org__c o : s.developers) {
                offered = offered || o.Name == 'SIT';
            }
            System.assert(offered, 'New release offers SIT as a source');
            System.assertEquals(3, s.packages.size(), 'Every org\'s packages for Review');
            System.assertNotEquals(null, devRefused, 'Developer orgs aren\'t switched');
        }
    }

    @IsTest
    static void onlyAdminsChangeTheMatrix() {
        User plain = RlyTestData.plainUser();
        System.runAs(RlyTestData.admin()) {
            packagedRoute();
        }
        System.runAs(plain) {
            Test.startTest();
            RlyOrgPackageMatrix.Matrix m = RlyOrgPackagesController.matrix();
            Integer refused = 0;
            try {
                RlyOrgPackagesController.markNotInstalled(m.orgs[1].id, 'arch');
            } catch (Exception e) {
                refused++;
            }
            try {
                RlyOrgPackagesController.checkNow();
            } catch (Exception e) {
                refused++;
            }
            Test.stopTest();
            System.assertEquals(false, m.isAdmin, 'Not an admin');
            System.assertEquals(2, refused, 'Marks and Check now are for admins');
        }
    }

    @IsTest
    static void nightlyReadsOnTheFirstCallAndSavesAfter() {
        System.runAs(RlyTestData.admin()) {
            RlyReleaseTestData.route();
            RlyOrgSession.testToken = RlyTestData.TOKEN;
            Test.setMock(HttpCalloutMock.class, new RlyHttpMock().match('GET', 'InstalledSubscriberPackage').reply(200,
                '{"done":true,"records":[{"SubscriberPackage":{"Name":"Archiver","NamespacePrefix":"arch"},'
                + '"SubscriberPackageVersion":{"MajorVersion":2,"MinorVersion":14,"PatchVersion":1}}]}'));
            Test.startTest();
            RlySyncPackages.Packages later = RlyOrgPackageNightly.readFirst('{"runId":"a0B000000000001"}');
            RlySyncPackages.Packages p = RlyOrgPackageNightly.readFirst(null);
            Map<String, Object> answer = new Map<String, Object>();
            RlyOrgPackageNightly.saveAfter(null, answer);
            RlyOrgPackageNightly.saveAfter(p, answer);
            RlySyncPackages.Packages failed = new RlySyncPackages.Packages();
            failed.orgs.add('SIT');
            failed.errors.put('SIT', 'SIT answered HTTP 401');
            Map<String, Object> failedAnswer = new Map<String, Object>();
            RlyOrgPackageNightly.saveAfter(failed, failedAnswer);
            Test.stopTest();
            System.assertEquals('Not read: SIT answered HTTP 401', failedAnswer.get('packages'), 'Nothing read: nothing saved, and it says why');
            System.assertEquals(null, later, 'Later calls of the night don\'t read');
            System.assertNotEquals(null, p, 'The first call reads');
            System.assertEquals('1 package in 3 orgs', answer.get('packages'), 'The answer says what it found');
            System.assert([SELECT Packages__c FROM RLY_Org__c WHERE Id = :orgId('SIT')].Packages__c.contains('2.14.1'), 'Saved per org');
        }
    }
}
