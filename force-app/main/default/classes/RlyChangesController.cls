/**
 * @description New Release, steps 1 and 2: pick the source developer org, then list what changed in it.
 *   getStart          developer orgs, where releases go (the first stage), and anything blocking
 *   describeTypes     every metadata type of the source org (the page lists them in parallel chunks)
 *   listChanges       changes of some types since a date
 *   listFolderChanges changes of one folder type
 *   listTracked       changes from source tracking (one call, when the org has it)
 *   detectTests       which of these Apex classes are tests
 *   findDeletions     components on the org's branch that the org doesn't have (orgs without source tracking)
 *   flowVersions      the latest and active version of selected flows (Tooling API FlowDefinition)
 * Calls are short, so the page runs several at once and keeps the results per org.
 * Raising the release is RlyReleasesController.raiseRelease.
 */
public with sharing class RlyChangesController {

    /** @description Most types listChanges takes per call. */
    public static final Integer MAX_TYPES_PER_CALL = 24;

    /**
     * @description Developer orgs, the first stage and anything blocking (RlyReleaseStart).
     * @return what step 1 shows
     */
    @AuraEnabled
    public static RlyReleaseStart.Start getStart() {
        return RlyReleaseStart.build();
    }

    /**
     * @description Every metadata type of the developer org.
     * @param orgId the developer org
     * @return the types
     */
    @AuraEnabled
    public static RlyMetadata.TypeList describeTypes(Id orgId) {
        try {
            return RlyMetadata.describe(source(orgId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Changes of some types since a date.
     * @param orgId the developer org
     * @param types 1 to 24 metadata types
     * @param sinceIso the earliest change (ISO date-time), or blank for any time
     * @return the changes
     */
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

    /**
     * @description Changes of one folder type since a date.
     * @param orgId the developer org
     * @param type a folder-based type such as Report
     * @param sinceIso the earliest change (ISO date-time), or blank for any time
     * @return the changes
     */
    @AuraEnabled
    public static List<RlyChangeFinder.Change> listFolderChanges(Id orgId, String type, String sinceIso) {
        try {
            return RlyChangeFinder.inFolders(source(orgId), type, since(sinceIso));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Changes from source tracking since a date.
     * @param orgId the developer org
     * @param sinceIso the earliest change (ISO date-time), or blank for any time
     * @return the changes
     */
    @AuraEnabled
    public static List<RlyChangeFinder.Change> listTracked(Id orgId, String sinceIso) {
        try {
            return RlyChangeFinder.tracked(source(orgId), since(sinceIso));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Which of these Apex classes are tests.
     * @param orgId the developer org
     * @param classNames Apex class names
     * @return the names that are tests
     */
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

    /**
     * @description Deletion candidates of an org without source tracking: on its branch, not in the org. They may also
     * have come from another org through the branch, so the page never pre-selects them.
     * @param orgId the developer org
     * @return the candidates, each with deleted = true
     */
    @AuraEnabled
    public static List<RlyChangeFinder.Change> findDeletions(Id orgId) {
        try {
            return RlyDeletionFinder.find(source(orgId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The versions of selected flows in the developer org: latest and active version numbers and the
     * latest version's status (Active, Draft, Obsolete, InvalidDraft). A Draft latest version deploys inactive.
     * @param orgId the developer org
     * @param names the flows' API names
     * @return one entry per flow, in the order asked
     */
    @AuraEnabled
    public static List<RlyFlowVersions.FlowInfo> flowVersions(Id orgId, List<String> names) {
        try {
            return RlyFlowVersions.read(source(orgId), names);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // The org to read: a registered developer org (hotfixes come from developer orgs too).
    private static RLY_Org__c source(Id orgId) {
        RLY_Org__c org = new Data().org(orgId);
        if (org == null || org.Role__c != 'Developer') {
            // Callers wrap it with handled(), which sets the message the page shows.
            throw new RlyReleaseException(org?.Role__c == 'Stage'
                ? RlyRaiseRoute.STAGE_RETIRED : 'Pick a registered developer org.');
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

    /** @description Registered orgs are shared hub records, read in system mode for every user. */
    private without sharing class Data {

        /**
         * @description One org with its sign-in fields, for the callouts only (never returned to the page).
         * @param orgId the org
         * @return the org, or null
         */
        public RLY_Org__c org(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Consumer_Key__c, Client_Id__c,
                                            Certificate__c, Branch__c, Source_Tracking__c
                                     FROM RLY_Org__c WHERE Id = :orgId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0];
        }
    }
}
