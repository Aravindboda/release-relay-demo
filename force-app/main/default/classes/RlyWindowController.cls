/**
 * @description Release windows for the pages (build 39): an org's window on the Pipeline tab (read by everyone with the
 * tab, saved by admins), the notice and Deploy now anyway on a release waiting for its window, and the freezes starting
 * within a week for the Home tab. RlyReleaseWindow does the time arithmetic, RlyWindowText the words, RlyWindowInput
 * checks what admins save; RlyWindowGate holds and starts deploys.
 */
public with sharing class RlyWindowController {

    /** @description An org's window for the Pipeline tab. */
    public class WindowView {
        /** @description The org. */
        @AuraEnabled public Id orgId;
        /** @description The org's name. */
        @AuraEnabled public String orgName;
        /** @description Whether a window or a freeze is set. */
        @AuraEnabled public Boolean isSet = false;
        /** @description Whether a deploy could run now. */
        @AuraEnabled public Boolean openNow = true;
        /** @description The window in a few words ("Mon–Thu 6:00 PM–10:00 PM CST · next freeze 16 Nov 2026"). */
        @AuraEnabled public String summary;
        /** @description What happens now ("Open now", "Closed: deploys Tue 10 Nov, 6:00 PM CST", "Frozen until …"). */
        @AuraEnabled public String stateText;
        /** @description The chosen days (Mon, Tue, …). */
        @AuraEnabled public List<String> days = new List<String>();
        /** @description From, HH:mm, or blank (all day). */
        @AuraEnabled public String fromTime;
        /** @description To, HH:mm, or blank. */
        @AuraEnabled public String toTime;
        /** @description The time zone id. */
        @AuraEnabled public String timeZone;
        /** @description The freezes, earliest first. */
        @AuraEnabled public List<RlyWindowFreezes.Freeze> freezes = new List<RlyWindowFreezes.Freeze>();
        /** @description Whether the current user may edit it (admins). */
        @AuraEnabled public Boolean canEdit = false;
    }

    /** @description A freeze starting within a week (or running now), for the Home tab. */
    public class Upcoming {
        /** @description The org's name. */
        @AuraEnabled public String orgName;
        /** @description The line: "PROD freeze starts in 3 days (16 Nov 2026): Go-live week." */
        @AuraEnabled public String text;
        /** @description Whether it is running now. */
        @AuraEnabled public Boolean now = false;
    }

    /**
     * @description Every org releases deploy into, with its window.
     * @return the windows, by org name
     */
    @AuraEnabled
    public static List<WindowView> windows() {
        try {
            List<WindowView> out = new List<WindowView>();
            for (RLY_Org__c o : RlyWindowStore.deployOrgs()) {
                out.add(viewOf(o));
            }
            return out;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Saves an org's window (admins).
     * @param inputJson the window (RlyWindowInput)
     * @return the org's window as saved
     */
    @AuraEnabled
    public static WindowView saveWindow(String inputJson) {
        try {
            if (!RlyOrgController.isAdmin()) {
                throw new RlyReleaseException('Only a Release Relay admin can change a release window.');
            }
            RlyWindowInput w = RlyWindowInput.parse(inputJson);
            RLY_Org__c org = w == null ? null : RlyWindowStore.org(w.orgId);
            if (org == null) {
                throw new RlyReleaseException('That org isn\'t registered.');
            }
            RlyWindowStore.save(w.rowFor(org.Id));
            return viewOf(RlyWindowStore.org(org.Id));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description A release's place against its target's window (for a release Waiting for window).
     * @param releaseId the release
     * @return the notice
     */
    @AuraEnabled
    public static RlyWindowGate.Notice releaseNotice(Id releaseId) {
        try {
            return RlyWindowGate.noticeFor(RlyReleaseStore.release(releaseId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Starts a waiting release's deploy now, outside the window (admins, with a reason).
     * @param releaseId the release
     * @param reason why it can't wait
     * @return the release's status afterwards
     */
    @AuraEnabled
    public static String deployNow(Id releaseId, String reason) {
        try {
            RlyHubGuard.requireHub();
            RLY_Release__c rel = RlyReleaseStore.release(releaseId);
            RLY_Release__c prior = rel == null ? null : rel.clone(true, true, true, true);
            RlyWindowGate.deployNow(rel, reason);
            RlySlackCardSync.notifyChange(prior, rel); // the Slack card follows (callouts before any DML)
            RlyReleaseStore.save(rel);
            RlySlack.saveResults();
            RlyReleaseLog.flush();
            return rel.Status__c;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Freezes running now or starting within a week, for the Home tab.
     * @return the freezes, soonest first
     */
    @AuraEnabled
    public static List<Upcoming> upcomingFreezes() {
        try {
            List<Upcoming> out = new List<Upcoming>();
            Datetime at = RlyWindowGate.now();
            for (RLY_Org__c o : RlyWindowStore.deployOrgs()) {
                RlyReleaseWindow w = new RlyReleaseWindow(o);
                String line = RlyWindowText.soon(o.Name, w, at);
                if (line != null) {
                    out.add(upcomingRow(o.Name, line, w.freezeAt(at) != null));
                }
            }
            return out;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description An org's window for the page.
     * @param o the org with its window fields
     * @return the view
     */
    public static WindowView viewOf(RLY_Org__c o) {
        RlyReleaseWindow w = new RlyReleaseWindow(o);
        Datetime at = RlyWindowGate.now();
        WindowView v = new WindowView();
        v.orgId = o.Id;
        v.orgName = o.Name;
        v.isSet = w.isSet();
        v.openNow = w.isOpen(at);
        v.summary = RlyWindowText.summary(w, at);
        v.stateText = RlyWindowText.state(w, at);
        v.days = String.isBlank(o.Window_Days__c) ? new List<String>() : o.Window_Days__c.split(',');
        v.fromTime = o.Window_From__c;
        v.toTime = o.Window_To__c;
        v.timeZone = w.zoneId;
        v.freezes = w.freezes;
        v.canEdit = RlyOrgController.isAdmin();
        return v;
    }

    private static Upcoming upcomingRow(String orgName, String text, Boolean running) {
        Upcoming u = new Upcoming();
        u.orgName = orgName;
        u.text = text;
        u.now = running;
        return u;
    }

    private static AuraHandledException handled(Exception e) {
        AuraHandledException a = new AuraHandledException(e.getMessage());
        a.setMessage(e.getMessage());
        return a;
    }
}
