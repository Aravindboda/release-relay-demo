/**
 * New Release in the hub, steps 1 and 2: pick the source developer org, then list what changed in it.
 *   getStart          developer orgs, where releases go (the first stage), and anything blocking
 *   describeTypes     every metadata type of the source org (the page lists them in parallel chunks)
 *   listChanges       changes of some types since a date
 *   listFolderChanges changes of one folder type
 *   listTracked       changes from source tracking (one call, when the org has it)
 *   detectTests       which of these Apex classes are tests
 * Calls are short, so the page runs several at once and keeps the results per org.
 */
public with sharing class RlyNewReleaseController {

    public static final Integer MAX_TYPES_PER_CALL = 24;

    public class Start {
        @AuraEnabled public List<RLY_Org__c> developers = new List<RLY_Org__c>();
        @AuraEnabled public String targetName;
        @AuraEnabled public String targetBranch;
        @AuraEnabled public String repository;
        @AuraEnabled public String hubUserName;
        @AuraEnabled public List<String> problems = new List<String>();
    }

    @AuraEnabled
    public static Start getStart() {
        Data data = new Data();
        Start s = new Start();
        s.hubUserName = UserInfo.getName();
        List<RLY_Org__c> stages = new List<RLY_Org__c>();
        for (RLY_Org__c o : data.orgs()) {
            if (o.Role__c == 'Developer') {
                s.developers.add(o);
            } else if (o.Role__c == 'Stage') {
                stages.add(o);
            }
        }
        RLY_Org__c target;
        for (RLY_Org__c o : stages) {
            if (target == null || (o.Stage_Order__c != null && (target.Stage_Order__c == null || o.Stage_Order__c < target.Stage_Order__c))) {
                target = o;
            }
        }
        if (target != null) {
            s.targetName = target.Name;
            s.targetBranch = target.Branch__c;
        }
        RLY_Git_Connection__c git = data.git();
        s.repository = git == null ? null : git.Repository__c;
        if (git == null || git.Status__c != 'Connected') {
            s.problems.add('The Git connection isn\'t set up and checked yet (Pipeline tab).');
        }
        if (target == null || String.isBlank(target.Branch__c)) {
            s.problems.add('No stage to release into yet: register SIT with its branch (Pipeline tab).');
        }
        if (s.developers.isEmpty()) {
            s.problems.add('No developer org registered yet (Pipeline tab).');
        }
        return s;
    }

    @AuraEnabled
    public static RlyMetadata.TypeList describeTypes(Id orgId) {
        try {
            return RlyMetadata.describe(source(orgId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static List<RlyChangeFinder.Change> listChanges(Id orgId, List<String> types, String sinceIso) {
        if (types == null || types.isEmpty() || types.size() > MAX_TYPES_PER_CALL) {
            throw new AuraHandledException('List 1 to ' + MAX_TYPES_PER_CALL + ' types per call.');
        }
        try {
            return RlyChangeFinder.listed(source(orgId), types, since(sinceIso));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static List<RlyChangeFinder.Change> listFolderChanges(Id orgId, String type, String sinceIso) {
        try {
            return RlyChangeFinder.inFolders(source(orgId), type, since(sinceIso));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static List<RlyChangeFinder.Change> listTracked(Id orgId, String sinceIso) {
        try {
            return RlyChangeFinder.tracked(source(orgId), since(sinceIso));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    @AuraEnabled
    public static List<String> detectTests(Id orgId, List<String> classNames) {
        if (classNames == null || classNames.isEmpty()) {
            return new List<String>();
        }
        try {
            return RlyChangeFinder.testClasses(source(orgId), classNames);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** Raises the release: starts the retrieve in the developer org and saves it. Returns the release Id. */
    @AuraEnabled
    public static Id raise(String requestJson) {
        try {
            RlyReleaseFlow.RaiseRequest req = (RlyReleaseFlow.RaiseRequest) JSON.deserialize(requestJson, RlyReleaseFlow.RaiseRequest.class);
            return RlyReleaseFlow.raise(req);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /** The developer org to read; only registered developer orgs can be a source. */
    private static RLY_Org__c source(Id orgId) {
        RLY_Org__c org = new Data().org(orgId);
        if (org == null || org.Role__c != 'Developer') {
            throw new AuraHandledException('Pick a registered developer org.');
        }
        return org;
    }

    @TestVisible
    private static Datetime since(String sinceIso) {
        if (String.isBlank(sinceIso)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + sinceIso + '"', Datetime.class);
        } catch (Exception e) {
            throw new AuraHandledException('That date isn\'t valid.');
        }
    }

    private static AuraHandledException handled(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }

    /** Registered orgs and the Git connection are read by every hub user. */
    private without sharing class Data {
        public List<RLY_Org__c> orgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Stage_Order__c, Git_Environment__c, Status__c, Source_Tracking__c,
                           Org_Type__c, Is_Sandbox__c
                    FROM RLY_Org__c ORDER BY Name LIMIT 200];
        }
        public RLY_Org__c org(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Client_Id__c, Certificate__c,
                                            Branch__c, Source_Tracking__c
                                     FROM RLY_Org__c WHERE Id = :orgId];
            return rows.isEmpty() ? null : rows[0];
        }
        public RLY_Git_Connection__c git() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Repository__c, Status__c FROM RLY_Git_Connection__c ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
