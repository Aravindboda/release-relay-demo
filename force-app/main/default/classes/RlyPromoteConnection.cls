/**
 * @description Several Git connections (build 45): the repository a promotion (a bundle) lives in. A promotion only
 * combines releases from one connection, and that is the stage's connection: the releases it carries stay in the
 * repository they were raised in. A release without a connection counts as on the hub's main connection.
 */
public with sharing class RlyPromoteConnection {

    /**
     * @description The stage's connection, checked against every carried release.
     * @param stage the stage the releases wait in (with Role__c and Git_Connection__c)
     * @param carried the releases to carry (with Git_Connection__c)
     * @return the connection, or null when the hub has none
     */
    public static RLY_Git_Connection__c of(RLY_Org__c stage, List<RLY_Release__c> carried) {
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        Id mainId = conns.isEmpty() ? null : conns[0].Id;
        Id stageId = RlyConnectionRoutes.connectionIdOf(stage, mainId);
        for (RLY_Release__c r : carried) {
            Id relId = r.Git_Connection__c == null ? mainId : r.Git_Connection__c;
            if (relId != stageId) {
                throw new RlyReleaseException(r.Name + ' is in ' + labelOf(conns, relId) + ', but ' + stage.Name + ' is on '
                    + labelOf(conns, stageId) + ' now. A promotion only combines releases from one Git connection: '
                    + 'promote it from ' + stage.Name + ' after moving it back, or raise it again.');
            }
        }
        return find(conns, stageId);
    }

    /**
     * @description A connection's name as people know it: the provider and the repository.
     * @param conns the connections
     * @param connectionId the connection
     * @return for example GitLab release-relay-group/release-relay-gitlab
     */
    public static String labelOf(List<RLY_Git_Connection__c> conns, Id connectionId) {
        RLY_Git_Connection__c c = find(conns, connectionId);
        return c == null ? 'another Git connection' : nameOf(c);
    }

    /**
     * @description A connection's name as people know it.
     * @param c the connection
     * @return the provider and the repository, for example GitHub owner/repo
     */
    public static String nameOf(RLY_Git_Connection__c c) {
        String provider = RlyGitName.labelFor(c);
        return (provider == null ? c.Provider__c : provider) + ' ' + c.Repository__c;
    }

    private static RLY_Git_Connection__c find(List<RLY_Git_Connection__c> conns, Id connectionId) {
        for (RLY_Git_Connection__c c : conns) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return null;
    }
}
