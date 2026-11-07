/**
 * @description Work items (build 40) for the pages: the work tracking settings (Pipeline tab card; admins save), the
 * Work items tab, a release's tickets (release page and Approvals: read, edit, post to the tracker) and the ticket
 * input on New Release (the settings tell it the format and whether tickets are required).
 */
public with sharing class RlyWorkItemsController {

    /**
     * @description The settings (everyone reads them: the format and links).
     * @return the settings
     */
    @AuraEnabled
    public static RlyWorkTypes.Settings settings() {
        try {
            return RlyWorkSettings.viewOf(RlyWorkStore.trackingSettings());
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Saves the settings (admins).
     * @param settingsJson the settings as JSON
     * @return the saved settings
     */
    @AuraEnabled
    public static RlyWorkTypes.Settings saveSettings(String settingsJson) {
        try {
            RlyHubGuard.requireHub();
            if (!RlyOrgController.isAdmin()) {
                throw new RlyReleaseException('Only a Release Relay admin changes work tracking.');
            }
            RlyWorkTypes.Settings v = String.isBlank(settingsJson) ? new RlyWorkTypes.Settings()
                : (RlyWorkTypes.Settings) JSON.deserialize(settingsJson, RlyWorkTypes.Settings.class);
            RlyWorkStore.saveSettings(RlyWorkSettings.checked(v));
            return RlyWorkSettings.viewOf(RlyWorkStore.trackingSettings());
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The Work items tab.
     * @return the board
     */
    @AuraEnabled
    public static RlyWorkTypes.Board board() {
        try {
            return RlyWorkBoard.build();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description The Work items tab's Sync now: posts the newest moments their tickets haven't had.
     * @return how many tickets were updated
     */
    @AuraEnabled
    public static Integer syncRecent() {
        try {
            RlyHubGuard.requireHub();
            return RlyWorkSync.postRecent();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description A release's tickets.
     * @param releaseId the release
     * @return the tickets
     */
    @AuraEnabled
    public static RlyWorkTypes.ReleaseTickets releaseTickets(Id releaseId) {
        try {
            return ticketsOf(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Replaces a release's tickets (until it is deployed, rejected or closed).
     * @param releaseId the release
     * @param tickets the tickets
     * @return the tickets as saved
     */
    @AuraEnabled
    public static RlyWorkTypes.ReleaseTickets setReleaseTickets(Id releaseId, List<String> tickets) {
        try {
            RlyHubGuard.requireHub();
            RlyWorkItems.replace(releaseId, tickets);
            return ticketsOf(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Posts the release's moment to its tickets (and lets a release waiting for an approved change deploy
     * once allowed). The release page calls it after each check; Try again calls it too.
     * @param releaseId the release
     * @return the tickets afterwards
     */
    @AuraEnabled
    public static RlyWorkTypes.ReleaseTickets syncRelease(Id releaseId) {
        try {
            if (RlyHubGuard.isHub()) {
                RlyWorkSync.postRelease(releaseId);
            }
            return ticketsOf(releaseId);
        } catch (Exception e) {
            throw handled(e);
        }
    }

    private static RlyWorkTypes.ReleaseTickets ticketsOf(Id releaseId) {
        RLY_Work_Tracking__c s = RlyWorkStore.trackingSettings();
        RLY_Release__c rel = RlyWorkStore.release(releaseId);
        RlyWorkTypes.ReleaseTickets out = new RlyWorkTypes.ReleaseTickets();
        out.trackerLabel = RlyWorkBoard.trackerLabel(s);
        out.canEdit = rel != null && !RlyWorkItems.CLOSED.contains(rel.Status__c);
        for (RLY_Work_Item__c w : RlyWorkStore.forRelease(releaseId)) {
            RlyWorkTypes.TicketView t = new RlyWorkTypes.TicketView();
            t.ticket = w.Ticket__c;
            t.link = RlyWorkLinks.linkOf(w.Ticket__c, s);
            t.status = w.Sync_Status__c;
            t.posted = w.Posted_State__c;
            t.message = w.Sync_Message__c;
            t.syncedOn = w.Synced_On__c;
            out.tickets.add(t);
        }
        return out;
    }

    private static AuraHandledException handled(Exception e) {
        String message = e instanceof RlyReleaseException ? e.getMessage() : 'Work items: ' + e.getMessage();
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
