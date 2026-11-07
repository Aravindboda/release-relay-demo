/**
 * @description Work items (build 40): the ServiceNow change gate. When the admin turns on "Require an approved change"
 * (ServiceNow), a deploy into production (the hub org) starts only while the release has a change request (a ticket in
 * the change format) that ServiceNow shows approved with now inside its planned start and end. Otherwise the deploy
 * doesn't start: the release keeps its approval and says what it's waiting for, and each read of its page (RlyWorkSync)
 * checks again and starts the deploy once the change allows it. Callouts only (the callers save the release).
 */
public with sharing class RlyWorkGate {

    /** @description Start of the release's message while it waits. */
    public static final String WAITING = 'Waiting for an approved change:';
    /** @description The production org's role. */
    private static final String HUB_ROLE = 'Hub';

    /**
     * @description Whether a deploy must wait (and, if so, records why on the release). Called where a deploy starts
     * (RlyApprovalRuns.dispatchMerge).
     * @param rel the release about to deploy
     * @return true to hold the deploy
     */
    public static Boolean holds(RLY_Release__c rel) {
        RLY_Work_Tracking__c s = RlyWorkStore.trackingSettings();
        if (!needsChange(s) || rel == null || rel.Target_Org__c == null || !intoProduction(rel)) {
            return false;
        }
        String changeNo = changeOf(rel.Id, s);
        if (changeNo == null) {
            rel.Error_Message__c = (WAITING + ' add the ServiceNow change request to the release\'s work items.').left(2000);
            return true;
        }
        RlyWorkTypes.Change c = RlyWorkTracker.change(s, changeNo);
        if (c.allowed) {
            if (isWaiting(rel)) {
                rel.Error_Message__c = null;
            }
            return false;
        }
        rel.Error_Message__c = (WAITING + ' ' + c.message).left(2000);
        return true;
    }

    /**
     * @description Whether a release is waiting for an approved change.
     * @param rel the release
     * @return true while it waits
     */
    public static Boolean isWaiting(RLY_Release__c rel) {
        return rel != null && rel.Error_Message__c != null && rel.Error_Message__c.startsWith(WAITING);
    }

    /**
     * @description An approved release that waits for its change: checks again and starts the deploy when allowed.
     * @param rel the release
     * @return true when the release changed (deploy started, or a new reason to wait)
     */
    public static Boolean retry(RLY_Release__c rel) {
        if (!isWaiting(rel) || rel.Approval_Status__c != 'Approved' || rel.Status__c != 'Ready for approval') {
            return false;
        }
        String before = rel.Error_Message__c;
        RlyApprovalRuns.dispatchMerge(rel, RlyGit.forConnection(RlyReleaseStore.git()));
        return rel.Status__c != 'Ready for approval' || rel.Error_Message__c != before;
    }

    private static Boolean needsChange(RLY_Work_Tracking__c s) {
        return s != null && s.Require_Change__c == true && s.Tracker__c == RlyWorkTracker.SERVICENOW && String.isNotBlank(s.Named_Credential__c);
    }

    private static Boolean intoProduction(RLY_Release__c rel) {
        RLY_Org__c target = RlyReleaseStore.org(rel.Target_Org__c);
        return target != null && target.Role__c == HUB_ROLE;
    }

    // The release's first ticket in the change format (CHG\d{7} when the admin left it blank).
    private static String changeOf(Id releaseId, RLY_Work_Tracking__c s) {
        String format = String.isBlank(s.Change_Pattern__c) ? 'CHG\\d{7}' : s.Change_Pattern__c.trim();
        Pattern p;
        try {
            p = Pattern.compile('(?i)^(?:' + format + ')$');
        } catch (Exception e) {
            p = Pattern.compile('(?i)^CHG\\d{7}$');
        }
        for (RLY_Work_Item__c w : RlyWorkStore.forRelease(releaseId)) {
            if (p.matcher(w.Ticket__c).matches()) {
                return w.Ticket__c;
            }
        }
        return null;
    }
}
