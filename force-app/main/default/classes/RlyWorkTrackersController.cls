/**
 * @description Work items (build 47) for the Pipeline tab's Work tracking card: add or edit a tracker, turn it on or
 * off, move it in the routing order, and Test its sign-in. Admins only. Each call returns the settings with every
 * tracker (RlyWorkItemsController.settings reads them).
 */
public with sharing class RlyWorkTrackersController {

    /** @description setTrackerActive: turn on. */
    public static final String STATE_ON = 'on';
    /** @description moveTracker: one place up (tried earlier). */
    public static final String DIRECTION_UP = 'up';

    /**
     * @description Adds or edits a tracker.
     * @param trackerJson the tracker as JSON (id set when editing)
     * @return the settings with every tracker
     */
    @AuraEnabled
    public static RlyWorkTypes.Settings saveTracker(String trackerJson) {
        try {
            requireAdmin();
            if (String.isBlank(trackerJson)) {
                throw new RlyReleaseException('Nothing to save.');
            }
            RlyWorkStore.adoptLegacy();
            RlyWorkTypes.TrackerView v = (RlyWorkTypes.TrackerView) JSON.deserialize(trackerJson, RlyWorkTypes.TrackerView.class);
            RlyWorkStore.saveTrackers(new List<RLY_Work_Tracker__c>{ RlyWorkTrackerCheck.checked(v) });
            return view();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Turns a tracker on or off. Turning on checks its pattern against the other active trackers.
     * @param trackerId the tracker
     * @param state on or off
     * @return the settings with every tracker
     */
    @AuraEnabled
    public static RlyWorkTypes.Settings setTrackerActive(Id trackerId, String state) {
        try {
            requireAdmin();
            RlyWorkTypes.TrackerView v = RlyWorkSettings.trackerView(trackerFound(trackerId), 0);
            v.active = state == STATE_ON;
            RlyWorkStore.saveTrackers(new List<RLY_Work_Tracker__c>{ RlyWorkTrackerCheck.checked(v) });
            return view();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Moves a tracker one place up or down in the routing order.
     * @param trackerId the tracker
     * @param direction up or down
     * @return the settings with every tracker
     */
    @AuraEnabled
    public static RlyWorkTypes.Settings moveTracker(Id trackerId, String direction) {
        try {
            requireAdmin();
            trackerFound(trackerId);
            RlyWorkStore.saveTrackers(reordered(trackerId, direction == DIRECTION_UP ? -1 : 1));
            return view();
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Test: a read that needs the tracker's sign-in. Callout only, no save.
     * @param trackerId the tracker
     * @return what the tracker answered
     */
    @AuraEnabled
    public static RlyWorkTypes.Outcome testTracker(Id trackerId) {
        try {
            requireAdmin();
            return RlyWorkTracker.signIn(trackerFound(trackerId));
        } catch (Exception e) {
            throw handled(e);
        }
    }

    /**
     * @description Refuses a caller who isn't a Release Relay admin on the hub.
     */
    public static void requireAdmin() {
        RlyHubGuard.requireHub();
        if (!RlyOrgController.isAdmin()) {
            throw new RlyReleaseException('Only a Release Relay admin changes work tracking.');
        }
    }

    // Every tracker's new order, with one moved by step (-1 up, 1 down).
    private static List<RLY_Work_Tracker__c> reordered(Id trackerId, Integer step) {
        List<RLY_Work_Tracker__c> rows = new List<RLY_Work_Tracker__c>(RlyWorkStore.trackers());
        Integer at = 0;
        while (rows[at].Id != trackerId) {
            at++;
        }
        Integer other = at + step;
        if (other >= 0 && other < rows.size()) {
            RLY_Work_Tracker__c moved = rows[at];
            rows[at] = rows[other];
            rows[other] = moved;
        }
        List<RLY_Work_Tracker__c> out = new List<RLY_Work_Tracker__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            out.add(new RLY_Work_Tracker__c(Id = rows[i].Id, Sort_Order__c = i + 1));
        }
        return out;
    }

    private static RLY_Work_Tracker__c trackerFound(Id trackerId) {
        RLY_Work_Tracker__c t = trackerId == null ? null : RlyWorkRouting.byId(trackerId);
        if (t == null) {
            throw new RlyReleaseException('That tracker wasn\'t found: read the page again.');
        }
        return t;
    }

    private static RlyWorkTypes.Settings view() {
        return RlyWorkSettings.viewOf(RlyWorkStore.trackingSettings());
    }

    private static AuraHandledException handled(Exception e) {
        String message = e instanceof RlyReleaseException ? e.getMessage() : 'Work tracking: ' + e.getMessage();
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
