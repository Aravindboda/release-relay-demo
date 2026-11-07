/**
 * @description Holds a deploy outside its target org's release window (build 39). An approved release, promotion or
 * back promote sync whose target org has a window that is closed (or a freeze) doesn't start its merge and deploy: it
 * becomes Waiting for window (History: Window_Held) and its checks and approval stay as they are. Every read of the
 * release (RlyStatusReader: the release page, the Releases list, Home) tries again; once the window is open the deploy
 * starts as the approval would have started it, or the checks run again when the target branch moved meanwhile. An admin
 * can start it at once with a reason (deployNow: History Window_Override, which the evidence PDF lists, and the Slack
 * card's thread). Not held: rollbacks (they don't come through here), branch-only back promotes (no deploy), releases of
 * only manual steps, and orgs without a window. Callouts only in resume and deployNow; callers save the release.
 */
public with sharing class RlyWindowGate {

    /** @description The status of a release waiting for its target's window. */
    public static final String WAITING = 'Waiting for window';
    /** @description History: held by the window or a freeze. */
    public static final String EVENT_HELD = 'Window_Held';
    /** @description History: deployed outside the window by an admin. */
    public static final String EVENT_OVERRIDE = 'Window_Override';

    @TestVisible
    private static Datetime nowForTest;
    // Set while an admin's Deploy now anyway starts the deploy: the gate lets it through once.
    private static Boolean letThrough = false;

    /** @description Where a release stands against its target's window, for the release page. */
    public class Notice {
        /** @description waiting, frozen or none. */
        @AuraEnabled public String kind = 'none';
        /** @description The line for the page: "Waiting for PROD's release window: deploys Tue 10 Nov, 6:00 PM CST." */
        @AuraEnabled public String text;
        /** @description The window in a few words. */
        @AuraEnabled public String windowText;
        /** @description Whether the current user may deploy now anyway (admins). */
        @AuraEnabled public Boolean canDeployNow = false;
    }

    /**
     * @description The time the gate goes by (tests set it).
     * @return now
     */
    public static Datetime now() {
        return nowForTest != null ? nowForTest : System.now();
    }

    /**
     * @description Holds the release when its target's window is closed or frozen: Waiting for window, with a History
     * event the first time. Nothing is changed otherwise.
     * @param rel the release about to start its deploy
     * @return true when held (the caller doesn't start the deploy)
     */
    public static Boolean holds(RLY_Release__c rel) {
        if (letThrough || rel == null || rel.Target_Org__c == null || String.isBlank(rel.Target_Environment__c)) {
            return false;
        }
        RLY_Org__c org = RlyWindowStore.org(rel.Target_Org__c);
        RlyReleaseWindow w = new RlyReleaseWindow(org);
        Datetime at = now();
        if (!w.isSet() || w.isOpen(at)) {
            return false;
        }
        Boolean already = rel.Status__c == WAITING;
        rel.Status__c = WAITING;
        rel.Error_Message__c = null;
        if (!already) {
            RlyReleaseLog.add(rel, EVENT_HELD, text(org, w, at)).inOrg(org.Id);
        }
        return true;
    }

    /**
     * @description A read of a waiting release: starts the deploy once the window is open (or the checks again when the
     * target branch moved since they passed; the release is then approved again).
     * @param rel the release (Waiting for window)
     */
    public static void resume(RLY_Release__c rel) {
        RlyReleaseWindow w = new RlyReleaseWindow(RlyWindowStore.org(rel.Target_Org__c));
        if (w.isSet() && !w.isOpen(now())) {
            return;
        }
        RlyApprovalRuns.startApproved(rel, 'The release window is open, but the deploy couldn\'t start: ');
    }

    /**
     * @description An admin starts a waiting release's deploy now, outside the window, with a reason.
     * @param rel the release (Waiting for window)
     * @param reason why it can't wait (required)
     */
    public static void deployNow(RLY_Release__c rel, String reason) {
        if (!RlyOrgController.isAdmin()) {
            throw new RlyReleaseException('Only a Release Relay admin can deploy outside the release window.');
        }
        if (rel == null || rel.Status__c != WAITING) {
            throw new RlyReleaseException('Only a release waiting for the window can be deployed now.');
        }
        String why = reason == null ? '' : reason.normalizeSpace();
        if (why.length() < 5) {
            throw new RlyReleaseException('Say why it can\'t wait for the window.');
        }
        RLY_Org__c org = RlyWindowStore.org(rel.Target_Org__c);
        letThrough = true;
        try {
            RlyApprovalRuns.startApproved(rel, 'The deploy couldn\'t start: ');
        } finally {
            letThrough = false;
        }
        RlyReleaseLog.add(rel, EVENT_OVERRIDE, ('Deployed outside ' + org.Name + '\'s release window by ' + UserInfo.getName() + ': '
            + why).left(2000)).inOrg(org.Id);
    }

    /**
     * @description Where a release stands against its target's window.
     * @param rel the release
     * @return the notice (kind none when it isn't waiting)
     */
    public static Notice noticeFor(RLY_Release__c rel) {
        Notice n = new Notice();
        if (rel == null || rel.Status__c != WAITING || rel.Target_Org__c == null) {
            return n;
        }
        RLY_Org__c org = RlyWindowStore.org(rel.Target_Org__c);
        RlyReleaseWindow w = new RlyReleaseWindow(org);
        Datetime at = now();
        n.kind = w.freezeAt(at) != null ? 'frozen' : 'waiting';
        n.text = text(org, w, at);
        n.windowText = RlyWindowText.summary(w, at);
        n.canDeployNow = RlyOrgController.isAdmin();
        return n;
    }

    /**
     * @description The line for a held release: "Frozen until 2 Jan 2027 in PROD: Year-end close." or "Waiting for
     * PROD's release window: deploys Tue 10 Nov, 6:00 PM CST."
     * @param org the target org
     * @param w its window
     * @param at the moment
     * @return the line
     */
    public static String text(RLY_Org__c org, RlyReleaseWindow w, Datetime at) {
        RlyWindowFreezes.Freeze f = w.freezeAt(at);
        Datetime next = w.nextOpen(at);
        String when = next == null ? '' : ' Deploys ' + RlyWindowText.momentText(w, next) + '.';
        if (f != null) {
            return 'Frozen until ' + RlyWindowText.dateText(f.toDate) + ' in ' + org.Name
                + (String.isBlank(f.reason) ? '.' : ': ' + f.reason + '.') + when;
        }
        return 'Waiting for ' + org.Name + '\'s release window (' + RlyWindowText.dayText(w) + ' ' + RlyWindowText.hoursText(w) + ').' + when;
    }
}
