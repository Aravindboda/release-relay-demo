/**
 * @description Data access for the release flow. Releases, their items, the registered orgs and the Git connection
 * are shared hub records: the flow reads and updates them on behalf of every Release Relay user (a developer's
 * page moves a release along; an approver approves someone else's release). That access runs in system mode,
 * in the private inner without sharing class, and only the flow's own fields are written.
 */
public with sharing class RlyReleaseStore {

    /**
     * @description A registered org with its sign-in fields (consumer key included: for Apex only, never sent to the page).
     * @param orgId the org record
     * @return the org, or null
     */
    public static RLY_Org__c org(Id orgId) {
        return new SystemAccess().readOrg(orgId);
    }

    /**
     * @description The first stage of the route (lowest Stage_Order__c): where releases go.
     * @return the stage, or null
     */
    public static RLY_Org__c firstStage() {
        return new SystemAccess().readFirstStage();
    }

    /**
     * @description The stages and the hub, by name: the route a hotfix's next stop is found on.
     * @return the orgs, without sign-in fields
     */
    public static List<RLY_Org__c> routeOrgs() {
        return new SystemAccess().readRouteOrgs();
    }

    /**
     * @description The branches of the registered developer orgs, each once, by org name.
     * @return the branch names
     */
    public static List<String> developerBranches() {
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (RLY_Org__c o : new SystemAccess().readDevelopers()) {
            if (String.isNotBlank(o.Branch__c) && seen.add(o.Branch__c.trim())) {
                out.add(o.Branch__c.trim());
            }
        }
        return out;
    }

    /**
     * @description The hub's Git connection.
     * @return the connection, or null
     */
    public static RLY_Git_Connection__c git() {
        return new SystemAccess().readGit();
    }

    /**
     * @description A release with everything the flow and the page need.
     * @param releaseId the release
     * @return the release, or null
     */
    public static RLY_Release__c release(Id releaseId) {
        return new SystemAccess().readRelease(releaseId);
    }

    /**
     * @description A release's components.
     * @param releaseId the release
     * @return the items, by type and name
     */
    public static List<RLY_Release_Item__c> items(Id releaseId) {
        return new SystemAccess().readItems(releaseId);
    }

    /**
     * @description Releases for a list view: mine (raised by the current user), all, or approvals (waiting for an approver).
     * @param view mine, all or approvals
     * @return up to 200 releases, newest first
     */
    public static List<RLY_Release__c> releases(String view) {
        SystemAccess access = new SystemAccess();
        if (view == 'approvals') {
            return access.waitingForApproval();
        }
        return view == 'all' ? access.allReleases() : access.raisedBy(UserInfo.getUserId());
    }

    /**
     * @description Saves a new release and its items.
     * @param rel the release
     * @param items its items (Release__c is set here)
     */
    public static void insertRelease(RLY_Release__c rel, List<RLY_Release_Item__c> items) {
        new SystemAccess().insertAll(rel, items);
    }

    /**
     * @description Saves the fields the flow owns.
     * @param rel the release, as the flow changed it
     */
    public static void save(RLY_Release__c rel) {
        new SystemAccess().updateFlowFields(rel);
    }

    /** @description Shared hub records, read and written in system mode for the flow. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyReleaseStore.org.
         * @param orgId the org record
         * @return the org, or null
         */
        public RLY_Org__c readOrg(Id orgId) {
            List<RLY_Org__c> rows = [SELECT Id, Name, Role__c, My_Domain__c, Login_Type__c, Username__c, Consumer_Key__c, Client_Id__c,
                                            Certificate__c, Branch__c, Git_Environment__c, Stage_Order__c
                                     FROM RLY_Org__c WHERE Id = :orgId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description See RlyReleaseStore.firstStage.
         * @return the stage, or null
         */
        public RLY_Org__c readFirstStage() {
            List<RLY_Org__c> rows = [SELECT Id, Name, Branch__c, Git_Environment__c FROM RLY_Org__c
                                     WHERE Role__c = 'Stage' WITH SYSTEM_MODE ORDER BY Stage_Order__c ASC NULLS LAST, Name LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description The stages and the hub.
         * @return the orgs, by name
         */
        public List<RLY_Org__c> readRouteOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Git_Environment__c, Stage_Order__c, Status__c, Source_Tracking__c
                    FROM RLY_Org__c WHERE Role__c IN ('Stage', 'Hub') WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description Registered developer orgs that have a branch.
         * @return the orgs, by name
         */
        public List<RLY_Org__c> readDevelopers() {
            return [SELECT Id, Name, Branch__c FROM RLY_Org__c WHERE Role__c = 'Developer' AND Branch__c != null
                    WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description See RlyReleaseStore.git.
         * @return the connection, or null
         */
        public RLY_Git_Connection__c readGit() {
            List<RLY_Git_Connection__c> rows = [SELECT Id, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c,
                                                       Source_Path__c, Code_Scan__c, Status__c
                                                FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description See RlyReleaseStore.release.
         * @param releaseId the release
         * @return the release, or null
         */
        public RLY_Release__c readRelease(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Id, Name, Title__c, Description__c, Status__c, Source_Org__c, Source_Org__r.Name,
                    Source_Org__r.Role__c, Source_Org__r.Branch__c,
                    Target_Org__c, Target_Org__r.Name, Org_Label__c, Source_Branch__c, Target_Branch__c, Source_Environment__c,
                    Target_Environment__c, Retrieve_Id__c, PR_Number__c, PR_URL__c, Run_ID__c, Run_URL__c, Pending_Run__c,
                    Checks_Requested__c, Last_Synced__c, Error_Message__c, Component_Count__c, Test_Classes__c,
                    Scan_Status__c, Scan_Violations__c, Scan_Blocking__c, Scan_Result__c, Scan_Bypassed_By__c, Scan_Bypassed_By__r.Name,
                    Scan_Bypass_Reason__c, Validation_Status__c, Validation_Result__c,
                    Approval_Status__c, Approved_By__c, Approved_By__r.Name, Approved_On__c, Approval_Comment__c,
                    Merge_Commit__c, Deploy_Status__c, Deploy_Result__c, CreatedDate, CreatedBy.Name, CreatedById
                FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description See RlyReleaseStore.items.
         * @param releaseId the release
         * @return the items
         */
        public List<RLY_Release_Item__c> readItems(Id releaseId) {
            return [SELECT Id, Metadata_Type__c, Component_Name__c FROM RLY_Release_Item__c
                    WHERE Release__c = :releaseId WITH SYSTEM_MODE ORDER BY Metadata_Type__c, Component_Name__c LIMIT 5000];
        }

        /**
         * @description Releases whose checks finished and that wait for an approver.
         * @return the releases
         */
        public List<RLY_Release__c> waitingForApproval() {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND Status__c IN ('Ready for approval', 'Checks failed')
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description Every release raised from a developer org.
         * @return the releases
         */
        public List<RLY_Release__c> allReleases() {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                    FROM RLY_Release__c WHERE Source_Org__c != null WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description Releases one user raised.
         * @param userId the user
         * @return the releases
         */
        public List<RLY_Release__c> raisedBy(Id userId) {
            return [SELECT Id, Name, Title__c, Status__c, Source_Org__r.Name, Source_Org__r.Role__c, Target_Org__r.Name, Target_Branch__c, CreatedBy.Name,
                           CreatedDate, Component_Count__c, Scan_Status__c, Validation_Status__c
                    FROM RLY_Release__c WHERE Source_Org__c != null AND CreatedById = :userId
                    WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 200];
        }

        /**
         * @description See RlyReleaseStore.insertRelease.
         * @param rel the release
         * @param items its items
         */
        public void insertAll(RLY_Release__c rel, List<RLY_Release_Item__c> items) {
            insert as system rel;
            for (RLY_Release_Item__c i : items) {
                i.Release__c = rel.Id;
            }
            insert as system items;
        }

        /**
         * @description See RlyReleaseStore.save. Only the fields the flow owns; relationship fields from the query can't be saved.
         * @param rel the release
         */
        public void updateFlowFields(RLY_Release__c rel) {
            update as system new RLY_Release__c(Id = rel.Id, Status__c = rel.Status__c, Source_Branch__c = rel.Source_Branch__c,
                PR_Number__c = rel.PR_Number__c, PR_URL__c = rel.PR_URL__c, Run_ID__c = rel.Run_ID__c, Run_URL__c = rel.Run_URL__c,
                Pending_Run__c = rel.Pending_Run__c, Checks_Requested__c = rel.Checks_Requested__c, Last_Synced__c = rel.Last_Synced__c,
                Error_Message__c = rel.Error_Message__c, Scan_Status__c = rel.Scan_Status__c, Scan_Violations__c = rel.Scan_Violations__c,
                Scan_Blocking__c = rel.Scan_Blocking__c, Scan_Result__c = rel.Scan_Result__c, Scan_Bypassed_By__c = rel.Scan_Bypassed_By__c,
                Scan_Bypass_Reason__c = rel.Scan_Bypass_Reason__c, Validation_Status__c = rel.Validation_Status__c,
                Validation_Result__c = rel.Validation_Result__c, Approval_Status__c = rel.Approval_Status__c,
                Approved_By__c = rel.Approved_By__c, Approved_On__c = rel.Approved_On__c, Approval_Comment__c = rel.Approval_Comment__c,
                Merge_Commit__c = rel.Merge_Commit__c, Deploy_Status__c = rel.Deploy_Status__c, Deploy_Result__c = rel.Deploy_Result__c);
        }
    }
}
