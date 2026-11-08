/**
 * @description One active Git connection (build 46). A client has one repository provider at a time: every new release
 * starts in the active connection's repository, and the Migration tab switches the whole hub to another provider at
 * once (switchTo). When no connection is marked active, the oldest one counts (hubs from before build 46). A release
 * keeps the connection stamped on it at raise (Git_Connection__c; blank means the oldest connection), so a release
 * raised before a switch keeps working against its old repository.
 */
public with sharing class RlyGitConnections {

    /** @description Release statuses that end a release: any other status is open. */
    public static final Set<String> ENDED = new Set<String>{ 'Deployed', 'Rejected', 'Cancelled', 'Closed' };

    private static List<RLY_Git_Connection__c> cached;

    /**
     * @description Every connection: the active one first, then the oldest.
     * @return the connections
     */
    public static List<RLY_Git_Connection__c> connections() {
        if (cached == null) {
            cached = new SystemAccess().readAll();
        }
        return cached;
    }

    /**
     * @description Reads the connections again on the next call (after a connection is saved in this request).
     */
    public static void forget() {
        cached = null;
    }

    /**
     * @description The active connection, else the oldest.
     * @return its Id, or null when the hub has none
     */
    public static Id activeId() {
        List<RLY_Git_Connection__c> rows = connections();
        return rows.isEmpty() ? null : rows[0].Id;
    }

    /**
     * @description The oldest connection (what a release with a blank Git_Connection__c belongs to).
     * @return its Id, or null when the hub has none
     */
    public static Id oldestId() {
        RLY_Git_Connection__c oldest;
        for (RLY_Git_Connection__c c : connections()) {
            if (oldest == null || c.CreatedDate < oldest.CreatedDate) {
                oldest = c;
            }
        }
        return oldest == null ? null : oldest.Id;
    }

    /**
     * @description One connection.
     * @param connectionId the connection
     * @return the connection, or null
     */
    public static RLY_Git_Connection__c byId(Id connectionId) {
        for (RLY_Git_Connection__c c : connectionId == null ? new List<RLY_Git_Connection__c>() : connections()) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return null;
    }

    /**
     * @description The connection a release belongs to: its Git_Connection__c (read again when the release was read
     * without it), else the oldest connection.
     * @param rel the release
     * @return the connection's Id, or null when the hub has none
     */
    public static Id connectionIdOf(RLY_Release__c rel) {
        if (rel == null) {
            return activeId();
        }
        Map<String, Object> present = rel.getPopulatedFieldsAsMap();
        Id own;
        if (present.containsKey('Git_Connection__c')) {
            own = (Id) present.get('Git_Connection__c');
        } else if (rel.Id != null) {
            own = new SystemAccess().readConnectionOf(rel.Id);
        } else {
            return activeId(); // not raised yet: it will start in the active connection
        }
        return own == null ? oldestId() : own;
    }

    /**
     * @description The releases still open on a connection (any status but Deployed, Rejected, Cancelled or Closed).
     * A release with a blank Git_Connection__c counts as the oldest connection's.
     * @param connectionId the connection
     * @return up to 200 releases, oldest first (Name, Title__c, Status__c, PR_URL__c)
     */
    public static List<RLY_Release__c> openReleases(Id connectionId) {
        if (connectionId == null) {
            return new List<RLY_Release__c>();
        }
        // A blank Git_Connection__c is the oldest connection's: matched as null only for it.
        return new SystemAccess().readOpen(connectionId, connectionId == oldestId() ? null : connectionId);
    }

    /**
     * @description Switches the hub to another connection, all at once: it becomes the only active one. Refused while
     * releases are still open on the current connection. The caller checks the user is an admin and records the reason.
     * @param newConnectionId the connection to switch on
     * @param reason why (shown in the Migration report)
     */
    public static void switchTo(Id newConnectionId, String reason) {
        if (String.isBlank(reason)) {
            throw new RlyReleaseException('Say why the hub switches (it goes in the Migration report).');
        }
        RLY_Git_Connection__c target = byId(newConnectionId);
        if (target == null) {
            throw new RlyReleaseException('That Git connection isn\'t there any more.');
        }
        requireNoneOpen(activeId(), newConnectionId);
        List<RLY_Git_Connection__c> rows = new List<RLY_Git_Connection__c>();
        for (RLY_Git_Connection__c c : connections()) {
            Boolean isTarget = c.Id == newConnectionId;
            if (c.Active__c != isTarget) {
                rows.add(new RLY_Git_Connection__c(Id = c.Id, Active__c = isTarget));
            }
        }
        new SystemAccess().saveRows(rows);
        cached = null;
    }

    private static void requireNoneOpen(Id current, Id newConnectionId) {
        List<String> open = new List<String>();
        for (RLY_Release__c r : current == newConnectionId ? new List<RLY_Release__c>() : openReleases(current)) {
            open.add(r.Name);
        }
        if (!open.isEmpty()) {
            throw new RlyReleaseException('Releases are still open on the current connection (' + String.join(open, ', ')
                + '). Deploy, reject or close them first.');
        }
    }

    /** @description Connections and releases are shared hub records: read and switched in system mode. */
    private without sharing class SystemAccess {

        /**
         * @description See RlyGitConnections.connections.
         * @return the connections
         */
        public List<RLY_Git_Connection__c> readAll() {
            return [SELECT Id, Name, Provider__c, Repository__c, Named_Credential__c, Pipeline__c, Pipeline_Branch__c, Source_Path__c,
                           Code_Scan__c, Status__c, Status_Message__c, Last_Checked__c, Back_Promote__c, Active__c, CreatedDate,
                           Retention_Days__c, Archive_Nightly__c
                    FROM RLY_Git_Connection__c WITH SYSTEM_MODE ORDER BY Active__c DESC, CreatedDate ASC, Id ASC LIMIT 20];
        }

        /**
         * @description A release's stamped connection.
         * @param releaseId the release
         * @return the connection's Id, or null
         */
        public Id readConnectionOf(Id releaseId) {
            List<RLY_Release__c> rows = [SELECT Git_Connection__c FROM RLY_Release__c WHERE Id = :releaseId WITH SYSTEM_MODE];
            return rows.isEmpty() ? null : rows[0].Git_Connection__c;
        }

        /**
         * @description See RlyGitConnections.openReleases.
         * @param connectionId the connection
         * @param blankAs null to take the releases with no connection too (the oldest connection's), else connectionId
         * @return the releases
         */
        public List<RLY_Release__c> readOpen(Id connectionId, Id blankAs) {
            return [SELECT Id, Name, Title__c, Status__c, PR_URL__c, PR_Number__c FROM RLY_Release__c
                    WHERE Status__c NOT IN :ENDED AND (Git_Connection__c = :connectionId OR Git_Connection__c = :blankAs)
                    WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 200];
        }

        /**
         * @description Saves the switch.
         * @param rows the connections whose Active__c changes
         */
        public void saveRows(List<RLY_Git_Connection__c> rows) {
            update as system rows;
            RlyReleaseStore.forgetGit();
        }
    }
}
