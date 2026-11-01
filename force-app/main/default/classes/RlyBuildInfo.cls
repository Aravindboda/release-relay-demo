/**
 * @description "What's built" tab: what the Release Relay package uses in this org right now. Apex size per class
 * (the tab splits test from non-test with its own list), Release Relay record counts, the org limits the hub draws on
 * (data storage, API requests today), the hub's async Apex today (none by design), static resource sizes and when the
 * Release Relay code last changed. Read only, no callouts, no DML.
 */
public with sharing class RlyBuildInfo {

    private static final Integer COUNT_CAP = 7000;
    private static final Integer ASYNC_CAP = 100;
    private static final String CLASS_PATTERN = 'Rly%';
    private static final String RESOURCE_PATTERN = 'RLY%';
    private static final List<String> LIMIT_NAMES = new List<String>{ 'DataStorageMB', 'DailyApiRequests' };

    /** @description Everything the tab's live part shows. */
    public class BuildInfo {
        /** @description Characters without comments of every Release Relay class (tests included). */
        @AuraEnabled public Long apexChars = 0;
        /** @description Each Release Relay class with its size. */
        @AuraEnabled public List<ClassSize> classes = new List<ClassSize>();
        /** @description Release Relay record counts. */
        @AuraEnabled public List<RecordCount> records = new List<RecordCount>();
        /** @description The org limits the hub draws on. */
        @AuraEnabled public List<Usage> usage = new List<Usage>();
        /** @description Release Relay static resources with their size. */
        @AuraEnabled public List<ResourceSize> resources = new List<ResourceSize>();
        /** @description Async Apex jobs of Release Relay classes in the last day (none by design). */
        @AuraEnabled public Integer asyncJobs = 0;
        /** @description When a Release Relay class last changed (the last deploy of the code). */
        @AuraEnabled public Datetime codeChangedOn;
    }

    /** @description One Apex class and its size. */
    public class ClassSize {
        /** @description Class name. */
        @AuraEnabled public String name;
        /** @description Characters without comments. */
        @AuraEnabled public Integer chars;
    }

    /** @description How many records of one Release Relay object exist. */
    public class RecordCount {
        /** @description Object API name. */
        @AuraEnabled public String objectName;
        /** @description What the tab calls it. */
        @AuraEnabled public String label;
        /** @description Records counted (at most the cap). */
        @AuraEnabled public Integer total;
        /** @description The count reached the cap, so there are at least this many. */
        @AuraEnabled public Boolean capped;
    }

    /** @description One org limit: used and maximum. */
    public class Usage {
        /** @description Limit name, for example DataStorageMB. */
        @AuraEnabled public String name;
        /** @description Used so far. */
        @AuraEnabled public Integer used;
        /** @description The org's maximum. */
        @AuraEnabled public Integer maxValue;
    }

    /** @description One static resource and its size. */
    public class ResourceSize {
        /** @description Resource name. */
        @AuraEnabled public String name;
        /** @description Size in bytes. */
        @AuraEnabled public Integer bytes;
    }

    /**
     * @description What the package uses in this org now.
     * @return the live figures
     */
    @AuraEnabled(cacheable=false)
    public static BuildInfo read() {
        Data data = new Data();
        BuildInfo info = new BuildInfo();
        for (ApexClass c : data.classes()) {
            ClassSize s = new ClassSize();
            s.name = c.Name;
            s.chars = c.LengthWithoutComments == null ? 0 : c.LengthWithoutComments;
            info.apexChars += s.chars;
            info.classes.add(s);
            if (info.codeChangedOn == null || c.LastModifiedDate > info.codeChangedOn) {
                info.codeChangedOn = c.LastModifiedDate;
            }
        }
        info.records = data.counts();
        info.usage = usage(OrgLimits.getMap());
        info.resources = data.resources();
        info.asyncJobs = data.asyncJobs();
        return info;
    }

    /**
     * @description The org limits the tab shows, from the org's limit map.
     * @param orgLimitMap OrgLimits.getMap()
     * @return the limits found
     */
    @TestVisible
    private static List<Usage> usage(Map<String, System.OrgLimit> orgLimitMap) {
        List<Usage> out = new List<Usage>();
        for (String limitName : LIMIT_NAMES) {
            System.OrgLimit l = orgLimitMap == null ? null : orgLimitMap.get(limitName);
            if (l != null) {
                Usage u = new Usage();
                u.name = limitName;
                u.used = l.getValue();
                u.maxValue = l.getLimit();
                out.add(u);
            }
        }
        return out;
    }

    /**
     * @description A record count for the tab.
     * @param objectName object API name
     * @param label what the tab calls it
     * @param total records counted, at most COUNT_CAP
     * @return the count
     */
    @TestVisible
    private static RecordCount recordCount(String objectName, String label, Integer total) {
        RecordCount r = new RecordCount();
        r.objectName = objectName;
        r.label = label;
        r.total = total;
        r.capped = total >= COUNT_CAP;
        return r;
    }

    /** @description Apex classes, static resources, async jobs and Release Relay records are org-wide: read in system mode. */
    private without sharing class Data {

        /**
         * @description The Release Relay classes with their size.
         * @return the classes
         */
        public List<ApexClass> classes() {
            return [SELECT Name, LengthWithoutComments, LastModifiedDate FROM ApexClass
                    WHERE Name LIKE :CLASS_PATTERN AND NamespacePrefix = null WITH SYSTEM_MODE ORDER BY Name LIMIT 1000];
        }

        /**
         * @description Release Relay record counts, each capped so the counts stay inside the query row limit.
         * @return the counts
         */
        public List<RecordCount> counts() {
            return new List<RecordCount>{
                recordCount('RLY_Release__c', 'Releases',
                    [SELECT COUNT() FROM RLY_Release__c WITH SYSTEM_MODE LIMIT :COUNT_CAP]),
                recordCount('RLY_Release_Item__c', 'Release items',
                    [SELECT COUNT() FROM RLY_Release_Item__c WITH SYSTEM_MODE LIMIT :COUNT_CAP]),
                recordCount('RLY_Release_Event__c', 'History events',
                    [SELECT COUNT() FROM RLY_Release_Event__c WITH SYSTEM_MODE LIMIT :COUNT_CAP]),
                recordCount('RLY_Manual_Step__c', 'Manual steps',
                    [SELECT COUNT() FROM RLY_Manual_Step__c WITH SYSTEM_MODE LIMIT :COUNT_CAP]),
                recordCount('RLY_Manual_Step_Run__c', 'Manual step runs',
                    [SELECT COUNT() FROM RLY_Manual_Step_Run__c WITH SYSTEM_MODE LIMIT :COUNT_CAP]),
                recordCount('RLY_Org__c', 'Orgs',
                    [SELECT COUNT() FROM RLY_Org__c WITH SYSTEM_MODE LIMIT :COUNT_CAP])
            };
        }

        /**
         * @description The Release Relay static resources with their size.
         * @return the resources
         */
        public List<ResourceSize> resources() {
            List<ResourceSize> out = new List<ResourceSize>();
            for (StaticResource r : [SELECT Name, BodyLength FROM StaticResource
                                     WHERE Name LIKE :RESOURCE_PATTERN AND NamespacePrefix = null
                                     WITH SYSTEM_MODE ORDER BY Name LIMIT 100]) {
                ResourceSize s = new ResourceSize();
                s.name = r.Name;
                s.bytes = r.BodyLength;
                out.add(s);
            }
            return out;
        }

        /**
         * @description Async Apex jobs of Release Relay classes started in the last day.
         * @return the count (0 by design)
         */
        public Integer asyncJobs() {
            return [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name LIKE :CLASS_PATTERN
                    AND CreatedDate = LAST_N_DAYS:1 WITH SYSTEM_MODE LIMIT :ASYNC_CAP];
        }
    }
}
