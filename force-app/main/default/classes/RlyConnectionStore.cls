/**
 * @description Several Git connections (build 45): data access for the Pipeline tab's Git connections cards and for
 * moving an org to another connection. Connections, orgs and releases are shared hub records: read in system mode
 * here, written only after the callers' admin checks.
 */
public with sharing class RlyConnectionStore {

    /** @description Release statuses that end a release: any other status is open (an org with one can't move). */
    public static final Set<String> ENDED = new Set<String>{ 'Deployed', 'Rejected', 'Cancelled', 'Closed' };

    /**
     * @description Every connection, the main one first (the oldest active).
     * @return the connections
     */
    public static List<RLY_Git_Connection__c> connections() {
        return new SystemAccess().readConnections();
    }

    /**
     * @description One connection.
     * @param connectionId the connection
     * @return the connection, or null
     */
    public static RLY_Git_Connection__c byId(Id connectionId) {
        for (RLY_Git_Connection__c c : connections()) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return null;
    }

    /**
     * @description One connection, or the main one when it's blank or gone.
     * @param connectionId the connection, or null
     * @return the connection, or null when the hub has none
     */
    public static RLY_Git_Connection__c orMain(Id connectionId) {
        List<RLY_Git_Connection__c> conns = connections();
        for (RLY_Git_Connection__c c : conns) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return conns.isEmpty() ? null : conns[0];
    }

    /**
     * @description A release's connection and source org (RlyConnectionRoutes.forRelease).
     * @param releaseId the release
     * @return the release with Git_Connection__c and Source_Org__c, or null
     */
    public static RLY_Release__c releaseConnection(Id releaseId) {
        List<RLY_Release__c> rows = new SystemAccess().readReleaseConnection(releaseId);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description The registered orgs with their connection (no sign-in fields).
     * @return the orgs, by name
     */
    public static List<RLY_Org__c> orgs() {
        return new SystemAccess().readOrgs();
    }

    /**
     * @description The orgs on one connection and the hub (the last stop of every route). Back promote orgs are on the
     * main connection (back promote is hub-wide).
     * @param connectionId the connection
     * @param mainId the main connection's Id
     * @return the orgs
     */
    public static List<RLY_Org__c> orgsOn(Id connectionId, Id mainId) {
        List<RLY_Org__c> out = new List<RLY_Org__c>();
        for (RLY_Org__c o : orgs()) {
            Id own = o.Role__c == RlyBackPromote.ROLE ? mainId : RlyConnectionRoutes.connectionIdOf(o, mainId);
            if (o.Role__c == 'Hub' || own == connectionId) {
                out.add(o);
            }
        }
        return out;
    }

    /**
     * @description Saves a connection (admins only; checked by the callers).
     * @param row the fields to save
     */
    public static void save(RLY_Git_Connection__c row) {
        new SystemAccess().saveConnection(row);
    }

    /**
     * @description The open releases from or into an org (any status that doesn't end a release), up to five.
     * @param orgId the org
     * @return their numbers
     */
    public static List<String> openReleases(Id orgId) {
        List<String> out = new List<String>();
        for (RLY_Release__c r : new SystemAccess().readOpen(orgId)) {
            out.add(r.Name);
        }
        return out;
    }

    /**
     * @description Before an org moves to another connection: its releases without a connection keep the one they were
     * raised in, so their history stays with the old repository.
     * @param orgId the org
     * @param connectionId the connection it leaves
     */
    public static void keepHistory(Id orgId, Id connectionId) {
        if (orgId != null && connectionId != null) {
            new SystemAccess().stamp(orgId, connectionId);
        }
    }

    /** @description System-mode reads and writes of the hub records. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyConnectionStore.connections.
         * @return the connections
         */
        public List<RLY_Git_Connection__c> readConnections() {
            return [SELECT Id, Name, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c, Source_Path__c,
                           Code_Scan__c, Status__c, Status_Message__c, Last_Checked__c, Back_Promote__c, Active__c, CreatedDate
                    FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY Active__c DESC, CreatedDate ASC, Id ASC LIMIT 20];
        }

        /**
         * @description See RlyConnectionStore.releaseConnection.
         * @param releaseId the release
         * @return the rows
         */
        public List<RLY_Release__c> readReleaseConnection(Id releaseId) {
            return [SELECT Id, Git_Connection__c, Source_Org__c FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE];
        }

        /**
         * @description See RlyConnectionStore.orgs.
         * @return the orgs
         */
        public List<RLY_Org__c> readOrgs() {
            return [SELECT Id, Name, Role__c, Branch__c, Git_Environment__c, Stage_Order__c, Status__c, Git_Connection__c
                    FROM RLY_Org__c WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        }

        /**
         * @description See RlyConnectionStore.save.
         * @param row the fields to save
         */
        public void saveConnection(RLY_Git_Connection__c row) {
            upsert as system row;
        }

        /**
         * @description See RlyConnectionStore.openReleases.
         * @param orgId the org
         * @return the releases
         */
        public List<RLY_Release__c> readOpen(Id orgId) {
            return [SELECT Id, Name FROM RLY_Release__c WHERE (Source_Org__c = :orgId OR Target_Org__c = :orgId)
                    AND Status__c NOT IN :ENDED WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 5];
        }

        /**
         * @description See RlyConnectionStore.keepHistory.
         * @param orgId the org
         * @param connectionId the connection it leaves
         */
        public void stamp(Id orgId, Id connectionId) {
            List<RLY_Release__c> rows = [SELECT Id FROM RLY_Release__c WHERE Source_Org__c = :orgId AND Git_Connection__c = null
                                         WITH SYSTEM_MODE LIMIT 9000];
            for (RLY_Release__c r : rows) {
                r.Git_Connection__c = connectionId;
            }
            update as system rows;
        }
    }
}
