/**
 * @description The Migration tab's state on RLY_Migration__c.State__c (build 46, JSON): each checklist item's done mark
 * with who and when, every step's event, each org's check against the new repository, the accepted differences and the
 * branches read from the current repository. No SOQL, DML or callouts.
 */
public with sharing class RlyMigrationState {

    /** @description The value of a done mark. */
    public static final String DONE = 'done';
    /** @description The value of a cleared mark. */
    public static final String NOT_DONE = 'open';

    private static final Integer MAX_EVENTS = 300;

    /** @description Each checklist item's done mark, by key. */
    public Map<String, Mark> marks = new Map<String, Mark>();
    /** @description Every step's event, oldest first. */
    public List<Event> events = new List<Event>();
    /** @description Each org's check, by org Id. */
    public Map<String, OrgCheck> orgChecks = new Map<String, OrgCheck>();
    /** @description The current repository's branches (first page). */
    public List<String> branches = new List<String>();
    /** @description More branches than listed. */
    public Boolean moreBranches = false;
    /** @description When the branches were read. */
    public Datetime branchesReadOn;
    /** @description The new repository's check, in words. */
    public String targetCheck;
    /** @description How many branches the new repository held at its check. */
    public Integer targetBranches;
    /** @description Open pull or merge requests in the current repository, read after the run. */
    public List<RlyMigrationRepo.OpenRequest> requests = new List<RlyMigrationRepo.OpenRequest>();
    /** @description Why the admin accepted the listed differences (blank: not accepted). */
    public String acceptReason;
    /** @description The releases Switch now cancelled (build 54). */
    public List<RlyMigrationView.CancelledRelease> cancelled = new List<RlyMigrationView.CancelledRelease>();

    /** @description A done mark. */
    public class Mark {
        /** @description Done or not. */
        public Boolean done = false;
        /** @description Who set it. */
        public String who;
        /** @description When. */
        public Datetime stamp;
    }

    /** @description One step's event. */
    public class Event {
        /** @description The step. */
        public String step;
        /** @description What happened. */
        public String what;
        /** @description Who did it. */
        public String who;
        /** @description When. */
        public Datetime stamp;
    }

    /** @description One org's check against its branch in the new repository. */
    public class OrgCheck {
        /** @description The Sync status check's id (SYN-…). */
        public String syncId;
        /** @description drift or parts. */
        public String mode;
        /** @description Running, In sync, Differs or Failed. */
        public String status;
        /** @description How many components differ, or why it failed. */
        public String detail;
        /** @description When it was last read. */
        public Datetime stamp;
    }

    /**
     * @description The state saved on a migration.
     * @param raw State__c
     * @return the state (empty when blank or unreadable)
     */
    public static RlyMigrationState of(String raw) {
        if (String.isBlank(raw)) {
            return new RlyMigrationState();
        }
        try {
            return (RlyMigrationState) JSON.deserialize(raw, RlyMigrationState.class);
        } catch (JSONException e) {
            return new RlyMigrationState();
        }
    }

    /**
     * @description The state to save.
     * @return JSON
     */
    public String toJson() {
        while (events.size() > MAX_EVENTS) {
            events.remove(0);
        }
        return JSON.serialize(this);
    }

    /**
     * @description Records a step's event as the current user, now.
     * @param step the step
     * @param what what happened
     */
    public void log(String step, String what) {
        Event e = new Event();
        e.step = step;
        e.what = String.isBlank(what) ? '' : what.left(1000);
        e.who = UserInfo.getName();
        e.stamp = System.now();
        events.add(e);
    }

    /**
     * @description Sets or clears a checklist item's done mark as the current user, now.
     * @param key the item
     * @param value done, or anything else to clear it
     */
    public void mark(String key, String value) {
        Mark m = new Mark();
        m.done = value == DONE;
        m.who = UserInfo.getName();
        m.stamp = System.now();
        marks.put(key, m);
    }

    /**
     * @description Whether an item is done.
     * @param key the item
     * @return true when done
     */
    public Boolean isDone(String key) {
        Mark m = marks.get(key);
        return m != null && m.done == true;
    }
}
