/**
 * @description "What's built" tab (a technical document of the package): what Release Relay uses in this org right now.
 * Build 31: every method first calls RlyBuildLock.requireUnlocked() (the tab can be locked with a password); the
 * generated document data is no longer in the page bundle but in the Document RLY_BuildData in the hidden folder
 * RLY_Private, returned by buildData(); and every Rly / RLY component read here comes back with its name (and last
 * change), so the tab counts only the ones in the package list carried in that data and lists the rest as extras.
 * read(): Apex size per class (the tab splits test from non-test with its own list), Release Relay record counts, the
 * org limits the hub draws on (whole org: data storage, API requests today), the hub's async Apex today (none by
 * design), static resource sizes and when the code last changed. counts(): the document's counts read live from setup
 * objects (Apex classes, permission sets with what each grants, custom permissions, tabs, custom fields per object,
 * static resources); the tab falls back to its generated figures for anything not read. Read only, no callouts, no DML.
 */
public with sharing class RlyBuildInfo {

    private static final Integer COUNT_CAP = 7000;
    private static final Integer ASYNC_CAP = 100;
    private static final String CLASS_PATTERN = 'Rly%';
    private static final String RESOURCE_PATTERN = 'RLY%';
    private static final List<String> LIMIT_NAMES = new List<String>{ 'DataStorageMB', 'DailyApiRequests' };
    private static final String SETUP_PATTERN = 'RLY%';
    private static final Integer SETUP_ROW_CAP = 5000;
    private static final String MISSING_DATA = 'The What\'s built data (Document RLY_BuildData in the folder RLY_Private) is not in this org. Deploy the package again.';
    /** @description The Document (hidden folder RLY_Private) that holds the generated data. */
    @TestVisible
    private static String dataName = 'RLY_BuildData';
    /** @description The objects the Data model section documents (User: only its Release Relay fields count). */
    @TestVisible
    private static final List<String> DOCUMENTED_OBJECTS = new List<String>{
        'RLY_Release__c', 'RLY_Release_Item__c', 'RLY_Release_Event__c', 'RLY_Manual_Step__c', 'RLY_Manual_Step_Run__c',
        'RLY_Org__c', 'RLY_Git_Connection__c', 'RLY_Notification__c', 'RLY_Archive_Run__c', 'RLY_Lock__c', 'User'
    };

    /** @description The document's counts read live from setup objects; null where a count couldn't be read. */
    public class Counts {
        /** @description Release Relay Apex classes (tests included). */
        @AuraEnabled public Integer apexClasses;
        /** @description Release Relay permission sets. */
        @AuraEnabled public Integer permissionSets;
        /** @description Release Relay custom permissions. */
        @AuraEnabled public Integer customPermissions;
        /** @description Release Relay tabs (null when tab definitions can't be read). */
        @AuraEnabled public Integer tabs;
        /** @description Release Relay static resources. */
        @AuraEnabled public Integer staticResources;
        /** @description The Rly classes found (the tab keeps the ones in the package list). */
        @AuraEnabled public List<String> classNames = new List<String>();
        /** @description The RLY custom permissions found. */
        @AuraEnabled public List<String> customPermissionNames = new List<String>();
        /** @description The RLY tabs found (null when tab definitions can't be read). */
        @AuraEnabled public List<String> tabNames;
        /** @description The RLY static resources found, with their size. */
        @AuraEnabled public List<ResourceSize> resourceSizes = new List<ResourceSize>();
        /** @description Their size in bytes. */
        @AuraEnabled public Long staticResourceBytes = 0;
        /** @description Custom fields of the documented objects (on User only the RLY_ ones); null when not described. */
        @AuraEnabled public Integer customFields;
        /** @description Custom fields per documented object. */
        @AuraEnabled public Map<String, Integer> fieldsByObject;
        /** @description What each Release Relay permission set grants. */
        @AuraEnabled public List<PermissionSetCount> permissionSetCounts = new List<PermissionSetCount>();
        /** @description When the counts were read. */
        @AuraEnabled public Datetime readOn;
    }

    /** @description What one permission set grants, counted. */
    public class PermissionSetCount {
        /** @description Permission set API name. */
        @AuraEnabled public String name;
        /** @description Its label. */
        @AuraEnabled public String label;
        /** @description Apex classes enabled. */
        @AuraEnabled public Integer classes = 0;
        /** @description Custom permissions enabled. */
        @AuraEnabled public Integer customPermissions = 0;
        /** @description Tab settings. */
        @AuraEnabled public Integer tabs = 0;
        /** @description Objects with any access. */
        @AuraEnabled public Integer objects = 0;
        /** @description Field permissions. */
        @AuraEnabled public Integer fields = 0;
    }

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
        /** @description When it last changed (the tab lists Rly classes not in the package with it). */
        @AuraEnabled public Datetime lastModified;
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
        /** @description When it last changed. */
        @AuraEnabled public Datetime lastModified;
    }

    /**
     * @description What the package uses in this org now.
     * @return the live figures
     */
    @AuraEnabled(cacheable=false)
    public static BuildInfo read() {
        RlyBuildLock.requireUnlocked();
        Data data = new Data();
        BuildInfo info = new BuildInfo();
        for (ApexClass c : data.classes()) {
            ClassSize s = new ClassSize();
            s.name = c.Name;
            s.chars = c.LengthWithoutComments == null ? 0 : c.LengthWithoutComments;
            s.lastModified = c.LastModifiedDate;
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
     * @description The document's generated data (JSON, the shape buildData.js had, plus the package list), read from the
     * hidden Document RLY_BuildData once this user may see the tab.
     * @return the JSON
     */
    @AuraEnabled(cacheable=false)
    public static String buildData() {
        RlyBuildLock.requireUnlocked();
        String body = new Data().document(dataName);
        if (String.isBlank(body)) {
            AuraHandledException e = new AuraHandledException(MISSING_DATA);
            e.setMessage(MISSING_DATA);
            throw e;
        }
        return body;
    }

    /**
     * @description The document's counts, read live from setup objects (not cached: the lock is checked on every call),
     * with the names found so the tab counts only the ones in the package list. Anything that can't be read stays null
     * and the tab shows its generated figure.
     * @return the counts
     */
    @AuraEnabled(cacheable=false)
    public static Counts counts() {
        RlyBuildLock.requireUnlocked();
        Setup setup = new Setup();
        Counts c = new Counts();
        c.readOn = System.now();
        c.classNames = setup.apexClassNames();
        c.apexClasses = c.classNames.size();
        c.customPermissionNames = setup.customPermissionNames();
        c.customPermissions = c.customPermissionNames.size();
        c.tabNames = setup.tabNames();
        c.tabs = c.tabNames == null ? null : c.tabNames.size();
        c.resourceSizes = new Data().resources();
        for (ResourceSize r : c.resourceSizes) {
            c.staticResourceBytes += r.bytes == null ? 0 : r.bytes;
        }
        c.staticResources = c.resourceSizes.size();
        Map<Id, PermissionSetCount> byId = new Map<Id, PermissionSetCount>();
        for (PermissionSet p : setup.permissionSets()) {
            PermissionSetCount pc = new PermissionSetCount();
            pc.name = p.Name;
            pc.label = p.Label;
            byId.put(p.Id, pc);
            c.permissionSetCounts.add(pc);
        }
        c.permissionSets = byId.size();
        setup.countGrants(byId);
        c.fieldsByObject = customFieldCounts(DOCUMENTED_OBJECTS);
        if (c.fieldsByObject != null) {
            c.customFields = 0;
            for (Integer n : c.fieldsByObject.values()) {
                c.customFields += n;
            }
        }
        return c;
    }

    /**
     * @description Custom fields per object from the schema (deferred describe). On User only the Release Relay fields
     * (RLY_) count. Null when an object can't be described (not deployed yet).
     * @param objectNames the objects
     * @return object name to custom field count, or null
     */
    @TestVisible
    private static Map<String, Integer> customFieldCounts(List<String> objectNames) {
        try {
            Map<String, Integer> out = new Map<String, Integer>();
            for (Schema.DescribeSObjectResult d : Schema.describeSObjects(objectNames, SObjectDescribeOptions.DEFERRED)) {
                out.put(d.getName(), countCustom(d.getName(), d.fields.getMap().keySet()));
            }
            return out;
        } catch (Exception e) {
            // describeSObjects throws InvalidParameterValueException for an object that isn't deployed yet
            return null;
        }
    }

    /**
     * @description How many of an object's fields are custom ones the document lists.
     * @param objectName the object
     * @param fieldNames its field names (lower case, as the describe gives them)
     * @return the count
     */
    @TestVisible
    private static Integer countCustom(String objectName, Set<String> fieldNames) {
        Integer n = 0;
        Boolean onlyOurs = objectName == 'User';
        for (String f : fieldNames) {
            if (f.endsWith('__c') && (!onlyOurs || f.startsWithIgnoreCase('rly_'))) {
                n++;
            }
        }
        return n;
    }

    /**
     * @description Adds one setup row to its permission set's counts.
     * @param byId the permission sets by Id
     * @param parentId the row's permission set
     * @param kind ApexClass, CustomPermission, Tab, Object or Field
     */
    @TestVisible
    private static void addGrant(Map<Id, PermissionSetCount> byId, Id parentId, String kind) {
        PermissionSetCount pc = byId.get(parentId);
        if (pc == null) {
            return;
        }
        if (kind == 'ApexClass') {
            pc.classes++;
        } else if (kind == 'CustomPermission') {
            pc.customPermissions++;
        } else if (kind == 'Tab') {
            pc.tabs++;
        } else if (kind == 'Object') {
            pc.objects++;
        } else if (kind == 'Field') {
            pc.fields++;
        }
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

    /** @description Setup objects (classes, permission sets and what they grant, custom permissions, tabs) are org-wide: read in system mode. */
    private without sharing class Setup {

        /**
         * @description Apex classes named Rly, tests included (the tab keeps the ones in the package list).
         * @return their names
         */
        public List<String> apexClassNames() {
            List<String> out = new List<String>();
            for (ApexClass c : [SELECT Name FROM ApexClass WHERE Name LIKE :CLASS_PATTERN AND NamespacePrefix = null
                                WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                out.add(c.Name);
            }
            return out;
        }

        /**
         * @description Custom permissions named RLY.
         * @return their names
         */
        public List<String> customPermissionNames() {
            List<String> out = new List<String>();
            for (CustomPermission p : [SELECT DeveloperName FROM CustomPermission WHERE DeveloperName LIKE :SETUP_PATTERN
                                       AND NamespacePrefix = null WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                out.add(p.DeveloperName);
            }
            return out;
        }

        /**
         * @description Tabs named RLY.
         * @return their names, or null when tab definitions can't be read here
         */
        public List<String> tabNames() {
            try {
                List<String> out = new List<String>();
                for (TabDefinition t : [SELECT Name FROM TabDefinition WHERE Name LIKE :SETUP_PATTERN WITH SYSTEM_MODE LIMIT 200]) {
                    out.add(t.Name);
                }
                return out;
            } catch (QueryException e) {
                return null;
            }
        }

        /**
         * @description Release Relay permission sets (not the ones owned by profiles).
         * @return the permission sets
         */
        public List<PermissionSet> permissionSets() {
            return [SELECT Id, Name, Label FROM PermissionSet WHERE Name LIKE :SETUP_PATTERN AND IsOwnedByProfile = false
                    AND NamespacePrefix = null WITH SYSTEM_MODE ORDER BY Name LIMIT 50];
        }

        /**
         * @description Counts what each permission set grants: classes and custom permissions, tabs, objects, fields.
         * @param byId the permission sets by Id (counts are added to them)
         */
        public void countGrants(Map<Id, PermissionSetCount> byId) {
            Set<Id> ids = byId.keySet();
            for (SetupEntityAccess a : [SELECT ParentId, SetupEntityType FROM SetupEntityAccess WHERE ParentId IN :ids
                                        AND SetupEntityType IN ('ApexClass', 'CustomPermission') WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                addGrant(byId, a.ParentId, a.SetupEntityType);
            }
            for (PermissionSetTabSetting t : [SELECT ParentId FROM PermissionSetTabSetting WHERE ParentId IN :ids
                                              WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                addGrant(byId, t.ParentId, 'Tab');
            }
            for (ObjectPermissions o : [SELECT ParentId FROM ObjectPermissions WHERE ParentId IN :ids
                                        WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                addGrant(byId, o.ParentId, 'Object');
            }
            for (FieldPermissions f : [SELECT ParentId FROM FieldPermissions WHERE ParentId IN :ids
                                       WITH SYSTEM_MODE LIMIT :SETUP_ROW_CAP]) {
                addGrant(byId, f.ParentId, 'Field');
            }
        }
    }

    /** @description Apex classes, static resources, async jobs, Release Relay records and the hidden Document are org-wide: read in system mode. */
    private without sharing class Data {

        /**
         * @description The generated data: the body of the Document in the hidden folder (users can't open it by URL).
         * @param developerName the Document's API name
         * @return its text, or null when it isn't in this org
         */
        public String document(String developerName) {
            List<Document> docs = [SELECT Body FROM Document WHERE DeveloperName = :developerName WITH SYSTEM_MODE LIMIT 1];
            return docs.isEmpty() ? null : docs[0].Body.toString();
        }

        /**
         * @description The Rly classes with their size (the tab keeps the ones in the package list).
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
         * @description The RLY static resources with their size and last change (the tab keeps the ones in the package list).
         * @return the resources
         */
        public List<ResourceSize> resources() {
            List<ResourceSize> out = new List<ResourceSize>();
            for (StaticResource r : [SELECT Name, BodyLength, LastModifiedDate FROM StaticResource
                                     WHERE Name LIKE :RESOURCE_PATTERN AND NamespacePrefix = null
                                     WITH SYSTEM_MODE ORDER BY Name LIMIT 100]) {
                ResourceSize s = new ResourceSize();
                s.name = r.Name;
                s.bytes = r.BodyLength;
                s.lastModified = r.LastModifiedDate;
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
