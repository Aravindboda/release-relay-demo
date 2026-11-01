/**
 * @description The Home tab (rlyHome): the landing page of the app. One read of saved records, no callouts: the KPI
 * tiles (RlyHomeStats), what needs the viewer per role (RlyHomeNeeds), the route board (RlyHomeRoute), the recent
 * activity and the deploys per week (RlyHomeStats) and the health line from the last saved checks (RlyHomeHealth).
 * Every part reads shared hub records in system mode in its own private inner without sharing class, and only reads.
 */
public with sharing class RlyHomeController {

    /** @description Everything the Home tab shows. */
    public class Home {
        /** @description The viewer's first name (or full name when there is none), for the greeting. */
        @AuraEnabled public String firstName;
        /** @description The viewer is a Release Relay admin (the health line links to Pipeline). */
        @AuraEnabled public Boolean isAdmin = false;
        /** @description The KPI tiles. */
        @AuraEnabled public RlyHomeStats.Kpis kpis;
        /** @description What needs the viewer, per role. */
        @AuraEnabled public RlyHomeNeeds.Needs needs;
        /** @description The route board. */
        @AuraEnabled public RlyHomeRoute.Route route;
        /** @description The 50 newest events of every release, newest first. */
        @AuraEnabled public List<RlyHomeStats.ActivityRow> activity;
        /** @description Deploys and failed deploys per week, the last 8 weeks, oldest first. */
        @AuraEnabled public List<RlyHomeStats.WeekBar> weeks;
        /** @description Deploys and failed deploys since Monday, per org. */
        @AuraEnabled public List<RlyHomeStats.OrgWeek> weekByOrg;
        /** @description The health line. */
        @AuraEnabled public RlyHomeHealth.Health health;
    }

    /**
     * @description Reads the whole Home tab from saved records (no callouts).
     * @return the page
     */
    @AuraEnabled
    public static Home read() {
        try {
            Home h = new Home();
            h.firstName = String.isBlank(UserInfo.getFirstName()) ? UserInfo.getName() : UserInfo.getFirstName();
            h.isAdmin = RlyOrgController.isAdmin();
            h.needs = RlyHomeNeeds.forViewer();
            h.kpis = RlyHomeStats.kpis(h.needs.approvalCount);
            h.route = RlyHomeRoute.read();
            h.activity = RlyHomeStats.activity();
            h.weeks = RlyHomeStats.weeks();
            h.weekByOrg = RlyHomeStats.thisWeekByOrg();
            h.health = RlyHomeHealth.read();
            return h;
        } catch (Exception e) {
            throw handled(e);
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
}
