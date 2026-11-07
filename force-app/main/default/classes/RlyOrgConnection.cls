/**
 * @description Several Git connections (build 45): the connection an org is registered on. Every developer and stage
 * org belongs to exactly one; with one connection it is picked automatically. The hub (the last stop of every route)
 * and back promote orgs have none. An org moves to another connection only when it has no open releases; its releases
 * without a connection keep the one they were raised in, so its history stays with the old repository.
 */
public with sharing class RlyOrgConnection {

    /** @description What the moved org needs before it is saved: whether it moves, and from where. */
    public class Move {
        /** @description The connection the org leaves, or null when it doesn't move. */
        public Id fromId;
    }

    /**
     * @description Sets the org's connection on the row to save, checked. Throws AuraHandledException with the reason.
     * @param row the row to save (with Role__c)
     * @param input what the page sent (Git_Connection__c only when the picker was shown)
     * @param saved the org as saved, or null for a new one
     * @return the move to record after the save
     */
    public static Move apply(RLY_Org__c row, RLY_Org__c input, RLY_Org__c saved) {
        Move m = new Move();
        if (hasNone(row)) {
            row.Git_Connection__c = null;
            return m;
        }
        List<RLY_Git_Connection__c> conns = RlyConnectionStore.connections();
        Id mainId = conns.isEmpty() ? null : conns[0].Id;
        Id picked = pickedOf(input, saved, conns);
        Id fromId = saved == null ? null : RlyConnectionRoutes.connectionIdOf(saved, mainId);
        Id toId = RlyConnectionRoutes.connectionIdOf(new RLY_Org__c(Git_Connection__c = picked), mainId);
        if (saved == null || fromId != toId) {
            checkTarget(conns, picked);
        }
        if (saved != null && fromId != toId) {
            requireNoOpenReleases(saved, conns, toId);
            m.fromId = fromId;
        }
        row.Git_Connection__c = picked;
        return m;
    }

    // The hub (the last stop of every route) and back promote orgs (hub-wide) have no connection.
    private static Boolean hasNone(RLY_Org__c row) {
        return row.Role__c == 'Hub' || row.Role__c == RlyBackPromote.ROLE;
    }

    // What the page picked; a new org with one active connection gets it automatically.
    private static Id pickedOf(RLY_Org__c input, RLY_Org__c saved, List<RLY_Git_Connection__c> conns) {
        Id picked = input.isSet('Git_Connection__c') ? input.Git_Connection__c : (saved == null ? null : saved.Git_Connection__c);
        if (picked != null || saved != null) {
            return picked;
        }
        List<RLY_Git_Connection__c> active = activeOf(conns);
        if (active.size() > 1) {
            throw problem('Pick the Git connection this org\'s releases go through.');
        }
        return active.isEmpty() ? null : active[0].Id;
    }

    // The connection an org moves to (or a new org starts on) must be there and active.
    private static void checkTarget(List<RLY_Git_Connection__c> conns, Id picked) {
        if (picked == null) {
            return;
        }
        RLY_Git_Connection__c target = find(conns, picked);
        if (target == null) {
            throw problem('That Git connection isn\'t there any more: pick another one.');
        }
        if (target.Active__c != true) {
            throw problem(RlyPromoteConnection.labelOf(conns, picked) + ' isn\'t active: pick an active Git connection.');
        }
    }

    /**
     * @description After the save: an org that moved keeps its history with the old repository.
     * @param row the org as saved
     * @param m the move from apply
     */
    public static void afterSave(RLY_Org__c row, Move m) {
        if (m != null && m.fromId != null) {
            RlyConnectionStore.keepHistory(row.Id, m.fromId);
        }
    }

    private static void requireNoOpenReleases(RLY_Org__c saved, List<RLY_Git_Connection__c> conns, Id toId) {
        List<String> open = RlyConnectionStore.openReleases(saved.Id);
        if (!open.isEmpty()) {
            throw problem(saved.Name + ' has open releases (' + String.join(open, ', ') + '). Deploy, reject or close them before '
                + 'moving it to ' + RlyPromoteConnection.labelOf(conns, toId) + '.');
        }
    }

    private static List<RLY_Git_Connection__c> activeOf(List<RLY_Git_Connection__c> conns) {
        List<RLY_Git_Connection__c> out = new List<RLY_Git_Connection__c>();
        for (RLY_Git_Connection__c c : conns) {
            if (c.Active__c == true) {
                out.add(c);
            }
        }
        return out;
    }

    private static RLY_Git_Connection__c find(List<RLY_Git_Connection__c> conns, Id connectionId) {
        for (RLY_Git_Connection__c c : conns) {
            if (c.Id == connectionId) {
                return c;
            }
        }
        return null;
    }

    private static AuraHandledException problem(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
